import Foundation

/// iOS agent-mode orchestrator, ported from the macOS `SessionCoordinator`
/// minus its whisper-cli machinery: SpeechAnalyzer streams finalized text
/// directly, so there is no PCM batching, WAV round-trip, or serialized
/// transcription chain. The LLM flush chain and `TranscriptBuffer`
/// busy/pending semantics are identical to macOS.
@MainActor
final class AgentSessionController: ObservableObject {
    @Published var session: STMDSession?
    @Published var transcript = ""
    @Published var document = ""
    /// Live volatile (not yet finalized) recognizer text, for UI only.
    @Published var volatileText = ""
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
            BackendSettings.shared.outputFormat = outputFormat.rawValue
            migrateSessionDocument()
        }
    }
    /// Latest editor selection, read at flush time in edit mode. Not @Published —
    /// no UI reads it and it changes on every caret move.
    var editorSelection: String?

    private let fileManager = STMDFileManager.shared
    private let buffer = TranscriptBuffer()
    private let llm: AgentLLMService
    private var stt: SpeechTranscriptionService?

    // LLM flushes run on a serialized chain so a long formatting call never
    // blocks incoming transcription; TranscriptBuffer's busy/pending logic
    // orders the text between the two pipelines.
    private var flushTask: Task<Void, Never>?

    init(llm: AgentLLMService = FoundationModelsAgentService()) {
        self.llm = llm
    }

    // MARK: - Lifecycle

    func startSession() async {
        guard session == nil else { return }

        stmdLog("SESSION", "Starting session")
        transcript = ""
        document = ""
        volatileText = ""
        error = nil
        mode = .format
        editorSelection = nil

        // modelSize is a whisper concept; unused on iOS (never read back).
        var newSession = STMDSession(modelSize: .base, baseDir: fileManager.stmdRoot, format: outputFormat)
        newSession.state = .initializing
        session = newSession

        do {
            _ = try fileManager.createSessionDirectory(id: newSession.id)
            try await connectSTT()
            stmdLog("SESSION", "Ready: doc=\(newSession.docPath.path)")
            await beginRecording()
        } catch {
            stmdLog("SESSION", "Error starting session: \(error.localizedDescription)")
            self.error = error.localizedDescription
            stt = nil
            // Nothing was recorded — don't leave an empty session dir in history.
            try? FileManager.default.removeItem(at: newSession.dirPath)
            session = nil
        }
    }

    /// Loads a prior session from disk so recording/editing can continue where
    /// it left off. Its files are already persisted, so replacing an active
    /// session here is non-destructive.
    func restoreSession(_ listing: SessionListing) async {
        if session != nil {
            await stopSession()
        }
        stmdLog("SESSION", "Restoring session: \(listing.id)")

        transcript = fileManager.readMarkdown(from: listing.txtPath)
        volatileText = ""
        error = nil
        mode = .format
        editorSelection = nil
        outputFormat = listing.format
        document = fileManager.readMarkdown(from: listing.docPath)

        var restored = STMDSession(restoring: listing, modelSize: .base)

        // Unlike a new session, restore succeeds even when STT is unavailable
        // (no speech models, simulator): the document is on disk and can be
        // viewed, edited, and previewed — only recording needs the recognizer.
        do {
            try await connectSTT()
        } catch {
            // Logged only; beginRecording surfaces it if recording is attempted.
            stmdLog("SESSION", "Restored without STT: \(error.localizedDescription)")
            stt = nil
        }
        restored.state = .paused
        session = restored
        stmdLog("SESSION", "Restored: doc=\(restored.docPath.path)")
    }

    private func connectSTT() async throws {
        let service = SpeechTranscriptionService()
        try await service.ensureAssets()

        service.onFinalResult = { [weak self] text in
            await self?.handleFinalTranscript(text)
        }
        service.onVolatileResult = { [weak self] text in
            await self?.setVolatileText(text)
        }
        service.onSilence = { [weak self] in
            Task { @MainActor in await self?.finalizeAndFlush() }
        }
        service.onError = { [weak self] error in
            Task { @MainActor in self?.error = error.localizedDescription }
        }
        stt = service
    }

    func startRecording() {
        guard session?.state == .paused else { return }
        Task { await beginRecording() }
    }

    private func beginRecording() async {
        guard session != nil else { return }
        guard let stt else {
            // Restored without a recognizer (see restoreSession).
            error = "Transcription is unavailable — recording is disabled for this session."
            session?.state = .paused
            return
        }
        guard await AudioCaptureService.requestPermission() else {
            stmdLog("SESSION", "Microphone permission denied")
            error = "Microphone access denied. Enable it in Settings → Privacy & Security → Microphone."
            session?.state = .paused
            return
        }
        do {
            try await stt.start()
            session?.state = .recording
            stmdLog("SESSION", "Recording started")
        } catch {
            stmdLog("SESSION", "Recording start error: \(error.localizedDescription)")
            self.error = error.localizedDescription
            session?.state = .paused
        }
    }

    func pauseRecording() {
        guard session?.state == .recording else { return }
        session?.state = .paused
        stmdLog("SESSION", "Recording paused")
        Task {
            // Finalizes trailing words (they arrive via onFinalResult) before flushing.
            await stt?.stop()
            volatileText = ""
            launchFlush()
        }
    }

    /// Manual flush: send the buffer to the LLM immediately, without waiting
    /// for the word threshold or silence.
    func flushNow() {
        guard session?.state == .recording, !isProcessing else { return }
        stmdLog("SESSION", "Manual flush requested")
        Task { await finalizeAndFlush() }
    }

    /// Short utterances (e.g. an edit instruction) sit as a volatile
    /// hypothesis and never reach the buffer on their own — force them final,
    /// then give the results stream a moment to deliver into the buffer.
    /// `finalize(through:)` returns when the analyzer finalizes, but delivery
    /// runs on the separate results task; flushing immediately could pull the
    /// buffer before the text lands.
    private func finalizeAndFlush() async {
        await stt?.finalizeNow()
        try? await Task.sleep(nanoseconds: 300_000_000)
        launchFlush()
    }

    func stopSession() async {
        stmdLog("SESSION", "Stopping session")
        await stt?.stop()
        volatileText = ""

        launchFlush(drainAll: true)
        await flushTask?.value

        await buffer.clear()
        flushTask = nil
        stt = nil
        session = nil
        stmdLog("SESSION", "Session stopped")
    }

    func resetSession() async {
        stmdLog("SESSION", "Resetting session")
        await stt?.stop()

        flushTask?.cancel()
        flushTask = nil

        transcript = ""
        document = ""
        volatileText = ""
        error = nil
        editorSelection = nil
        isProcessing = false

        await buffer.clear()

        if let session {
            try? fileManager.writeMarkdown("", to: session.txtPath)
            try? fileManager.writeMarkdown("", to: session.docPath)
        }

        session?.state = .paused
        stmdLog("SESSION", "Session reset complete")
    }

    // MARK: - Document

    /// Mid-session format switch: move the document file to the new extension.
    /// Content is not converted — the next format-mode flush regenerates the
    /// whole document in the new format.
    private func migrateSessionDocument() {
        guard var sess = session else { return }
        let oldPath = sess.docPath
        sess.format = outputFormat
        let newPath = sess.docPath
        if FileManager.default.fileExists(atPath: oldPath.path) {
            try? FileManager.default.moveItem(at: oldPath, to: newPath)
        }
        session = sess
        stmdLog("SESSION", "Output format → \(outputFormat.rawValue): \(newPath.lastPathComponent)")
    }

    /// The editor wrote `text`; persist it so the next flush reads the edit.
    func userDidEdit(_ text: String) {
        document = text
        if let path = session?.docPath {
            try? fileManager.writeMarkdown(text, to: path)
        }
    }

    // MARK: - Transcription → buffer

    /// Entry point for finalized recognizer text (internal: it is the STT
    /// seam, driven directly in unit tests).
    func handleFinalTranscript(_ text: String) async {
        stmdLog("STT", "Finalized: \(text)")
        transcript += text + " "
        volatileText = ""

        let shouldFlush = await buffer.add(text)
        if shouldFlush { launchFlush() }

        if let session {
            try? fileManager.appendTranscript(text, to: session.txtPath)
        }
    }

    private func setVolatileText(_ text: String) {
        volatileText = text
    }

    // MARK: - LLM flush chain

    private func launchFlush(drainAll: Bool = false) {
        let previous = flushTask
        flushTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let text = drainAll ? await self.buffer.flushAll() : await self.buffer.flush()
            await self.sendBufferText(text)
        }
    }

    private func flushBuffer() async {
        let text = await buffer.flush()
        await sendBufferText(text)
    }

    /// Awaits the tail of the serialized flush chain (used by tests).
    func awaitPendingFlushes() async {
        await flushTask?.value
    }

    private func sendBufferText(_ text: String) async {
        guard !text.isEmpty, let sess = session else {
            if text.isEmpty { stmdLog("SESSION", "Flush skipped: buffer empty") }
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        // Mode, format and selection are read once per flush so a mid-stream
        // change can't corrupt an in-flight request.
        let mode = self.mode
        let format = self.outputFormat
        stmdLog("SESSION", "Flushing buffer (\(mode.rawValue)/\(format.rawValue)): \(text.prefix(120))")

        let currentDocument = fileManager.readMarkdown(from: sess.docPath)
        do {
            let final: String
            switch mode {
            case .format:
                final = try await streamReplacing(llm.formatTranscript(
                    currentDocument: currentDocument,
                    newTranscript: text,
                    format: format
                ))
            case .edit:
                final = try await streamReplacing(llm.editDocument(
                    currentDocument: currentDocument,
                    instruction: text,
                    userFocus: editorSelection,
                    format: format
                ))
            case .append:
                let context = LocalLLMService.lastSentences(currentDocument, count: Self.appendContextSentences)
                var latest = ""
                for try await partial in llm.appendTranscript(
                    recentContext: context,
                    newTranscript: text,
                    format: format
                ) {
                    latest = partial
                    document = LocalLLMService.joinAppended(base: currentDocument, delta: partial)
                }
                final = LocalLLMService.joinAppended(base: currentDocument, delta: latest)
            }
            stmdLog("SESSION", "LLM response (\(final.count) chars)")
            await handleAgentDocument(final)
        } catch {
            stmdLog("SESSION", "LLM error: \(error.localizedDescription)")
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
            document = partial
        }
        return latest
    }

    // Publish, persist, unblock buffer after each formatted result.
    private func handleAgentDocument(_ text: String) async {
        document = text
        if let path = session?.docPath {
            try? fileManager.writeMarkdown(text, to: path)
        }
        let shouldFlush = await buffer.agentDone()
        if shouldFlush { await flushBuffer() }
    }
}
