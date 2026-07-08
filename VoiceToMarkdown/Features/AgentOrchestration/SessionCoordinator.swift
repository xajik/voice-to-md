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

        var newSession = VTMDSession(modelSize: modelSize, baseDir: fileManager.vtmdRoot)
        newSession.state = .initializing
        session = newSession

        do {
            _ = try fileManager.createSessionDirectory(id: newSession.id)

            guard let baseURL = backendSettings.baseURL else { throw SessionError.invalidBaseURL }
            let service = LocalLLMService(baseURL: baseURL)
            let models = try await service.listModels()
            guard !models.isEmpty else { throw LocalLLMError.noModels }
            llmModel = backendSettings.localModel.isEmpty ? models[0] : backendSettings.localModel
            llmService = service

            whisper = WhisperService(modelPath: modelSize.localPath(in: fileManager.modelsDir))
            audioService = AudioCaptureService()
            audioService?.delegate = self

            startFileWatcher(mdPath: newSession.mdPath)
            vtmdLog("SESSION", "Ready: \(baseURL.absoluteString) model=\(llmModel) md=\(newSession.mdPath.path)")
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

    private func startFileWatcher(mdPath: URL) {
        fileWatcher = FileWatcher(url: mdPath) { [weak self] in
            Task { @MainActor in
                guard let self, let path = self.session?.mdPath else { return }
                self.markdown = self.fileManager.readMarkdown(from: path)
            }
        }
        fileWatcher?.start()
    }

    // Publish, persist, unblock buffer after each formatted result.
    private func handleAgentMarkdown(_ markdown: String) async {
        self.markdown = markdown
        if let path = session?.mdPath {
            try? fileManager.writeMarkdown(markdown, to: path)
        }
        let shouldFlush = await buffer.agentDone()
        if shouldFlush { await flushBuffer() }
    }

    private func sendBufferText(_ text: String) async {
        guard !text.isEmpty, let sess = session, let service = llmService else { return }
        isProcessing = true
        defer { isProcessing = false }
        vtmdLog("SESSION", "Flushing buffer: \(text.prefix(120))")

        let currentMarkdown = fileManager.readMarkdown(from: sess.mdPath)
        do {
            var latest = ""
            for try await partial in service.formatTranscript(
                currentMarkdown: currentMarkdown,
                newTranscript: text,
                model: llmModel
            ) {
                latest = partial
                markdown = partial // streamed into the editor as tokens arrive
            }
            vtmdLog("SESSION", "LLM response (\(latest.count) chars)")
            await handleAgentMarkdown(latest)
        } catch {
            vtmdLog("SESSION", "LLM error: \(error.localizedDescription)")
            self.error = error.localizedDescription
            _ = await buffer.agentDone()
        }
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
