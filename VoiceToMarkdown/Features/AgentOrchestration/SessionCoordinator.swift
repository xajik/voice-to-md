import AppKit
import AVFoundation
import Foundation

@MainActor
final class SessionCoordinator: ObservableObject {
    @Published var session: VTMDSession?
    @Published var transcript = ""
    @Published var markdown = ""
    @Published var error: String?
    /// True while a formatting call is in flight; orthogonal to session.state
    /// so recording/paused is never lost while the LLM works.
    @Published var isProcessing = false
    @Published var mode: AgentMode = .format
    /// Persisted across launches; changing it mid-session migrates the
    /// document file to the new extension.
    @Published var outputFormat: OutputFormat = BackendSettings.shared.resolvedOutputFormat {
        didSet {
            guard outputFormat != oldValue else { return }
            backendSettings.outputFormat = outputFormat.rawValue
            migrateSessionDocument()
        }
    }
    /// Latest editor selection, read at flush time in edit mode. Not @Published —
    /// no UI reads it and it changes on every caret move.
    var editorSelection: String?

    private let fileManager = VTMDFileManager.shared
    private let backendSettings = BackendSettings.shared
    private let buffer = TranscriptBuffer()
    private var llmService: LocalLLMService?
    private var llmModel = ""
    private var audioService: AudioCaptureService?
    private var whisper: WhisperService?
    private var fileWatcher: FileWatcher?

    // Audio accumulation: whisper-cli reloads the model on every invocation,
    // so tap buffers (~85 ms each) are batched into multi-second chunks and
    // transcribed serially via a FIFO task chain.
    private var pcmChunks: [AVAudioPCMBuffer] = []
    private var pcmFrames: AVAudioFrameCount = 0
    private var transcriptionTask: Task<Void, Never>?
    private let transcribeChunkSeconds: Double = 4

    // LLM flushes run on their own serialized chain so a long formatting
    // call never blocks transcription; TranscriptBuffer's busy/pending
    // logic orders the text between the two pipelines.
    private var flushTask: Task<Void, Never>?

    func startSession(modelSize: ModelSize) async {
        guard session == nil else { return }

        vtmdLog("SESSION", "Starting session: model=\(modelSize.rawValue)")
        transcript = ""
        markdown = ""
        error = nil
        mode = .format
        editorSelection = nil

        var newSession = VTMDSession(modelSize: modelSize, baseDir: fileManager.vtmdRoot, format: outputFormat)
        newSession.state = .initializing
        session = newSession

        do {
            _ = try fileManager.createSessionDirectory(id: newSession.id)
            try await connectServices(modelSize: modelSize)

            startFileWatcher(docPath: newSession.docPath)
            vtmdLog("SESSION", "Ready: model=\(llmModel) doc=\(newSession.docPath.path)")
            // No separate ready state — go straight into recording
            await beginRecording()
        } catch {
            vtmdLog("SESSION", "Error starting session: \(error.localizedDescription)")
            self.error = error.localizedDescription
            llmService = nil
            session = nil
        }
    }

    func startRecording() {
        guard session?.state == .paused else { return }
        Task { await beginRecording() }
    }

    /// Loads a prior session from disk (see `VTMDFileManager.listSessions()`)
    /// so recording/editing can continue where it left off. Its files are
    /// already persisted, so replacing an active session here is non-destructive.
    func restoreSession(_ listing: SessionListing) async {
        if session != nil {
            await stopSession()
        }
        vtmdLog("SESSION", "Restoring session: \(listing.id)")
        guard let modelSize = BackendSettings.shared.resolvedWhisperModel() else {
            error = "No Whisper model downloaded. Pick one in Settings."
            return
        }

        transcript = fileManager.readMarkdown(from: listing.txtPath)
        error = nil
        mode = .format
        editorSelection = nil
        outputFormat = listing.format
        markdown = fileManager.readMarkdown(from: listing.docPath)

        var restored = VTMDSession(restoring: listing, modelSize: modelSize)

        do {
            try await connectServices(modelSize: modelSize)

            restored.state = .paused
            session = restored
            startFileWatcher(docPath: restored.docPath)
            vtmdLog("SESSION", "Restored: doc=\(restored.docPath.path)")
        } catch {
            vtmdLog("SESSION", "Error restoring session: \(error.localizedDescription)")
            self.error = error.localizedDescription
            llmService = nil
            session = nil
        }
    }

    /// Shared by `startSession`/`restoreSession`: resolves the LLM + wires
    /// whisper and audio capture. Assigns `llmService`/`llmModel`/`whisper`/
    /// `audioService`; throws before any assignment happens on failure.
    private func connectServices(modelSize: ModelSize) async throws {
        guard let baseURL = backendSettings.baseURL else { throw SessionError.invalidBaseURL }
        let service = LocalLLMService(baseURL: baseURL)
        let models = try await service.listModels()
        guard !models.isEmpty else { throw LocalLLMError.noModels }
        llmModel = backendSettings.localModel.isEmpty ? models[0] : backendSettings.localModel
        llmService = service

        whisper = WhisperService(modelPath: modelSize.localPath(in: fileManager.modelsDir))
        audioService = AudioCaptureService()
        audioService?.delegate = self
    }

    private func beginRecording() async {
        guard session != nil else { return }
        guard await AudioCaptureService.requestPermission() else {
            vtmdLog("SESSION", "Microphone permission denied")
            error = "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone."
            session?.state = .paused
            return
        }
        do {
            try audioService?.start()
            session?.state = .recording
            vtmdLog("SESSION", "Recording started")
        } catch {
            vtmdLog("SESSION", "Recording start error: \(error.localizedDescription)")
            self.error = error.localizedDescription
            session?.state = .paused
        }
    }

    /// Manual flush: transcribe captured audio and send the buffer to the LLM
    /// immediately, without waiting for the word threshold or silence.
    func flushNow() {
        guard session?.state == .recording, !isProcessing else { return }
        vtmdLog("SESSION", "Manual flush requested")
        drainPendingAudio()
        enqueueAfterTranscription { $0.launchFlush() }
    }

    func pauseRecording() {
        guard session?.state == .recording else { return }
        audioService?.stop()
        session?.state = .paused
        vtmdLog("SESSION", "Recording paused")
        drainPendingAudio()
        enqueueAfterTranscription { $0.launchFlush() }
    }

    func stopSession() async {
        vtmdLog("SESSION", "Stopping session")
        audioService?.stop()

        // Transcribe any captured audio, then force flush remaining text
        drainPendingAudio()
        await transcriptionTask?.value
        launchFlush(drainAll: true)
        await flushTask?.value

        fileWatcher?.stop()
        await buffer.clear()
        pcmChunks = []
        pcmFrames = 0
        transcriptionTask = nil
        flushTask = nil
        fileWatcher = nil
        audioService = nil
        whisper = nil
        llmService = nil
        session = nil
        vtmdLog("SESSION", "Session stopped")
    }

    func resetSession() async {
        vtmdLog("SESSION", "Resetting session")
        audioService?.stop()

        transcriptionTask?.cancel()
        transcriptionTask = nil
        flushTask?.cancel()
        flushTask = nil

        pcmChunks = []
        pcmFrames = 0
        transcript = ""
        markdown = ""
        error = nil
        editorSelection = nil
        isProcessing = false

        await buffer.clear()

        if let session {
            try? fileManager.writeMarkdown("", to: session.txtPath)
            try? fileManager.writeMarkdown("", to: session.docPath)
        }

        session?.state = .paused
        vtmdLog("SESSION", "Session reset complete")
    }

    /// Opens the session document in the default app for its type
    /// (e.g. the browser for .html).
    func openPreview() {
        guard let sess = session else { return }
        let path = sess.docPath
        if !FileManager.default.fileExists(atPath: path.path) {
            try? fileManager.writeMarkdown(markdown, to: path)
        }
        NSWorkspace.shared.open(path)
    }

    private func startFileWatcher(docPath: URL) {
        fileWatcher = FileWatcher(url: docPath) { [weak self] in
            Task { @MainActor in
                guard let self, let path = self.session?.docPath else { return }
                self.markdown = self.fileManager.readMarkdown(from: path)
            }
        }
        fileWatcher?.start()
    }

    /// Mid-session format switch: move the document file to the new extension
    /// and re-watch it. Content is not converted — the next format-mode flush
    /// regenerates the whole document in the new format.
    private func migrateSessionDocument() {
        guard var sess = session else { return }
        fileWatcher?.stop()
        let oldPath = sess.docPath
        sess.format = outputFormat
        let newPath = sess.docPath
        if FileManager.default.fileExists(atPath: oldPath.path) {
            try? FileManager.default.moveItem(at: oldPath, to: newPath)
        }
        session = sess
        startFileWatcher(docPath: newPath)
        vtmdLog("SESSION", "Output format → \(outputFormat.rawValue): \(newPath.lastPathComponent)")
    }

    // Publish, persist, unblock buffer after each formatted result.
    private func handleAgentMarkdown(_ markdown: String) async {
        self.markdown = markdown
        if let path = session?.docPath {
            try? fileManager.writeMarkdown(markdown, to: path)
        }
        let shouldFlush = await buffer.agentDone()
        if shouldFlush { await flushBuffer() }
    }

    private func sendBufferText(_ text: String) async {
        guard !text.isEmpty, let sess = session, let service = llmService else { return }
        isProcessing = true
        defer { isProcessing = false }
        // Mode, format and selection are read once per flush so a mid-stream
        // change can't corrupt an in-flight request.
        let mode = self.mode
        let format = self.outputFormat
        vtmdLog("SESSION", "Flushing buffer (\(mode.rawValue)/\(format.rawValue)): \(text.prefix(120))")

        let currentDocument = fileManager.readMarkdown(from: sess.docPath)
        do {
            let final: String
            switch mode {
            case .format:
                final = try await streamReplacing(service.formatTranscript(
                    currentDocument: currentDocument,
                    newTranscript: text,
                    model: llmModel,
                    format: format
                ))
            case .edit:
                final = try await streamReplacing(service.editDocument(
                    currentDocument: currentDocument,
                    instruction: text,
                    userFocus: editorSelection,
                    model: llmModel,
                    format: format
                ))
            case .append:
                let context = LocalLLMService.lastSentences(currentDocument, count: Self.appendContextSentences)
                var latest = ""
                for try await partial in service.appendTranscript(
                    recentContext: context,
                    newTranscript: text,
                    model: llmModel,
                    format: format
                ) {
                    latest = partial
                    markdown = LocalLLMService.joinAppended(base: currentDocument, delta: partial)
                }
                final = LocalLLMService.joinAppended(base: currentDocument, delta: latest)
            }
            vtmdLog("SESSION", "LLM response (\(final.count) chars)")
            await handleAgentMarkdown(final)
        } catch {
            vtmdLog("SESSION", "LLM error: \(error.localizedDescription)")
            self.error = error.localizedDescription
            _ = await buffer.agentDone()
        }
    }

    private static let appendContextSentences = 3

    /// Streams a full-document response into the editor as tokens arrive.
    private func streamReplacing(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var latest = ""
        for try await partial in stream {
            latest = partial
            markdown = partial
        }
        return latest
    }

    private func flushBuffer() async {
        let text = await buffer.flush()
        await sendBufferText(text)
    }

    private func launchFlush(drainAll: Bool = false) {
        let previous = flushTask
        flushTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let text = drainAll ? await self.buffer.flushAll() : await self.buffer.flush()
            await self.sendBufferText(text)
        }
    }

    // Moves accumulated PCM into the serialized transcription queue
    private func drainPendingAudio() {
        guard !pcmChunks.isEmpty else { return }
        let buffers = pcmChunks
        pcmChunks = []
        pcmFrames = 0
        enqueueAfterTranscription { await $0.transcribe(buffers: buffers) }
    }

    // FIFO chain: each enqueued job runs after all previously enqueued ones
    private func enqueueAfterTranscription(_ job: @escaping (SessionCoordinator) async -> Void) {
        let previous = transcriptionTask
        transcriptionTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await job(self)
        }
    }

    private func transcribe(buffers: [AVAudioPCMBuffer]) async {
        guard let whisper else { return }
        let wavURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vtmd_chunk_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }

        do {
            try AudioConverter.writePCMBuffersToWAV(buffers, to: wavURL)
            guard let text = try await whisper.transcribe(wavFile: wavURL) else { return }
            vtmdLog("WHISPER", "Transcribed: \(text)")
            transcript += text + " "

            let shouldFlush = await buffer.add(text)
            if shouldFlush { launchFlush() }

            if let session {
                try? fileManager.appendTranscript(text, to: session.txtPath)
            }
        } catch {
            vtmdLog("WHISPER", "Transcription error: \(error.localizedDescription)")
        }
    }
}

extension SessionCoordinator: AudioCaptureDelegate {
    nonisolated func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer) {
        Task { @MainActor in
            self.pcmChunks.append(buffer)
            self.pcmFrames += buffer.frameLength
            let seconds = Double(self.pcmFrames) / buffer.format.sampleRate
            if seconds >= self.transcribeChunkSeconds {
                self.drainPendingAudio()
            }
        }
    }

    // 5s silence → transcribe remainder, then flush to the LLM.
    // The enqueued job only *launches* the flush so the transcription
    // chain is never blocked by the LLM call.
    nonisolated func audioCaptureDidDetectSilence() {
        Task { @MainActor in
            self.drainPendingAudio()
            self.enqueueAfterTranscription { $0.launchFlush() }
        }
    }

    nonisolated func audioCaptureDidFail(_ error: Error) {
        Task { @MainActor in self.error = error.localizedDescription }
    }
}

enum SessionError: Error, LocalizedError {
    case invalidBaseURL

    var errorDescription: String? {
        "Invalid local LLM API base URL. Check Settings."
    }
}
