import AVFoundation
import Foundation

@MainActor
final class SessionCoordinator: ObservableObject {
    @Published var session: VTMDSession?
    @Published var transcript = ""
    @Published var markdown = ""
    @Published var error: String?

    private let fileManager = VTMDFileManager.shared
    private let buffer = TranscriptBuffer()
    private let hooks = HookHandlers()
    private var hookServer: HookServer?
    private var audioService: AudioCaptureService?
    private var whisper: WhisperService?
    private var fileWatcher: FileWatcher?
    private var silenceFlushTask: Task<Void, Never>?

    let hooksPort: UInt16 = 7070

    func startSession(agentName: String, modelSize: ModelSize) async {
        guard session == nil else { return }

        var newSession = VTMDSession(
            agentName: agentName,
            modelSize: modelSize,
            baseDir: fileManager.vtmdRoot
        )
        newSession.state = .initializing
        session = newSession

        do {
            _ = try fileManager.createSessionDirectory(id: newSession.id)

            setupHookHandlers()
            hookServer = HookServer(port: hooksPort, handlers: hooks)
            try hookServer?.start()

            let provider = ProviderRegistry.shared.detect(from: fileManager.agentCommand())
            try provider.setupVoice(workDir: fileManager.vtmdRoot.path, hooksPort: Int(hooksPort))

            let tmux = TmuxSession(name: newSession.tmuxSessionName)
            var env = provider.env(hooksPort: Int(hooksPort))
            env["TSQ_HOOKS_PORT"] = "\(hooksPort)"
            try await tmux.spawn(
                command: fileManager.agentCommand(),
                workDir: fileManager.vtmdRoot.path,
                env: env
            )

            let initCmd = "/vtmd \(newSession.mdPath.path)"
            try await tmux.paste(initCmd)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try await tmux.sendKeys("C-n")

            try await waitForInit(timeout: 90)

            let modelPath = modelSize.localPath(in: fileManager.modelsDir)
            whisper = WhisperService(modelPath: modelPath)
            audioService = AudioCaptureService()
            audioService?.delegate = self

            session?.state = .ready
            startFileWatcher(mdPath: newSession.mdPath)
        } catch {
            self.error = error.localizedDescription
            session?.state = .stopped
        }
    }

    func startRecording() {
        guard session?.state == .ready || session?.state == .paused else { return }
        do {
            try audioService?.start()
            session?.state = .recording
        } catch {
            self.error = error.localizedDescription
        }
    }

    func pauseRecording() {
        guard session?.state == .recording else { return }
        audioService?.stop()
        session?.state = .paused
    }

    func stopSession() async {
        audioService?.stop()
        hookServer?.stop()
        fileWatcher?.stop()
        silenceFlushTask?.cancel()

        if let name = session?.tmuxSessionName {
            try? await TmuxSession(name: name).kill()
        }

        session?.state = .stopped
    }

    private func waitForInit(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if session?.state == .ready { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw SessionError.initTimeout
    }

    private func setupHookHandlers() {
        hooks.onInit = { [weak self] in
            Task { @MainActor in self?.session?.state = .ready }
        }
        hooks.onResponse = { [weak self] markdown in
            Task { @MainActor in
                self?.markdown = markdown
                if let path = self?.session?.mdPath {
                    try? self?.fileManager.writeMarkdown(markdown, to: path)
                }
                let shouldFlush = await self?.buffer.agentDone() ?? false
                if shouldFlush { await self?.flushBuffer() }
            }
        }
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

    private func flushBuffer() async {
        let text = await buffer.flush()
        guard !text.isEmpty, let session else { return }

        let mdPath = session.mdPath
        let currentMarkdown = fileManager.readMarkdown(from: mdPath)
        let payload = ["current_markdown": currentMarkdown, "new_transcript": text]

        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: json, encoding: .utf8) else { return }

        let tmux = TmuxSession(name: session.tmuxSessionName)
        try? await tmux.paste(jsonStr)
    }
}

extension SessionCoordinator: AudioCaptureDelegate {
    nonisolated func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer) {
        Task {
            let tmpDir = FileManager.default.temporaryDirectory
            let wavURL = tmpDir.appendingPathComponent("vtmd_chunk_\(UUID().uuidString).wav")
            guard let whisper = await self.whisper else { return }

            do {
                try AudioConverter.writePCMBuffersToWAV([buffer], to: wavURL)
                if let text = try await whisper.transcribe(wavFile: wavURL), !text.isEmpty {
                    await MainActor.run { self.transcript += text + " " }
                    let appended = await self.buffer.add(text)
                    if text == "[BLANK_AUDIO]" || appended {
                        await self.flushBuffer()
                    }
                    if let session = await self.session {
                        try? self.fileManager.appendTranscript(text, to: session.txtPath)
                    }
                }
            } catch { }
            try? FileManager.default.removeItem(at: wavURL)
        }
    }

    nonisolated func audioCaptureDidDetectSilence() {
        Task { @MainActor in
            let hasPending = await buffer.hasPending()
            if hasPending { await flushBuffer() }
        }
    }

    nonisolated func audioCaptureDidFail(_ error: Error) {
        Task { @MainActor in self.error = error.localizedDescription }
    }
}

enum SessionError: Error, LocalizedError {
    case initTimeout

    var errorDescription: String? {
        "Agent did not signal readiness within 90 seconds."
    }
}
