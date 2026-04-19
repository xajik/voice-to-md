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
    private var stateBeforeProcessing: SessionState = .ready

    let hooksPort: UInt16 = 7374

    func startSession(agentName: String, modelSize: ModelSize) async {
        guard session == nil else { return }

        vtmdLog("SESSION", "Starting session: agent=\(agentName) model=\(modelSize.rawValue)")

        var newSession = VTMDSession(
            agentName: agentName,
            modelSize: modelSize,
            baseDir: fileManager.vtmdRoot
        )
        newSession.state = .initializing
        session = newSession

        do {
            _ = try fileManager.createSessionDirectory(id: newSession.id)

            // Spec step 2: create notes directory at <workDir>/.tsq/notes/<date>/<time>.md
            let notesPath = try fileManager.createNotesDirectory(workDir: fileManager.vtmdRoot.path)
            newSession.notesPath = notesPath
            session = newSession

            setupHookHandlers()
            hookServer = HookServer(port: hooksPort, handlers: hooks)
            try hookServer?.start()
            vtmdLog("SESSION", "Hook server started on port \(hooksPort)")

            let provider = ProviderRegistry.shared.detect(from: fileManager.agentCommand())
            try provider.setupVoice(workDir: fileManager.vtmdRoot.path, hooksPort: Int(hooksPort))
            vtmdLog("SESSION", "Provider configured: \(type(of: provider))")

            let tmux = TmuxSession(name: newSession.tmuxSessionName)
            var env = provider.env(hooksPort: Int(hooksPort))
            env["TSQ_HOOKS_PORT"] = "\(hooksPort)"
            try await tmux.spawn(
                command: fileManager.agentCommand(),
                workDir: fileManager.vtmdRoot.path,
                env: env
            )
            vtmdLog("SESSION", "Agent process spawned in tmux session \(newSession.tmuxSessionName)")

            // Spec step 3: init prompt passes notes_path so agent knows where to write
            let initCmd = "/vtmd \(notesPath.path)"
            try await tmux.paste(initCmd)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try await tmux.sendKeys("C-n")

            try await waitForInit(timeout: 90)
            vtmdLog("SESSION", "Agent initialized")

            let modelPath = modelSize.localPath(in: fileManager.modelsDir)
            whisper = WhisperService(modelPath: modelPath)
            audioService = AudioCaptureService()
            audioService?.delegate = self

            session?.state = .ready
            startFileWatcher(mdPath: newSession.mdPath)
            vtmdLog("SESSION", "Session ready: md=\(newSession.mdPath.path) notes=\(notesPath.path)")
        } catch {
            vtmdLog("SESSION", "Error starting session: \(error.localizedDescription)")
            self.error = error.localizedDescription
            session?.state = .stopped
        }
    }

    func startRecording() {
        guard session?.state == .ready || session?.state == .paused else { return }
        do {
            try audioService?.start()
            session?.state = .recording
            vtmdLog("SESSION", "Recording started")
        } catch {
            vtmdLog("SESSION", "Recording start error: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    func pauseRecording() {
        guard session?.state == .recording else { return }
        audioService?.stop()
        session?.state = .paused
        vtmdLog("SESSION", "Recording paused")
        // Spec step 20: flush any buffered input on pause
        Task { await self.flushBuffer() }
    }

    func stopSession() async {
        vtmdLog("SESSION", "Stopping session")
        audioService?.stop()

        // Spec step 22: force flush remaining text before shutdown
        await flushAllBuffer()

        hookServer?.stop()
        fileWatcher?.stop()
        silenceFlushTask?.cancel()

        if let name = session?.tmuxSessionName {
            try? await TmuxSession(name: name).kill()
        }

        session?.state = .stopped
        vtmdLog("SESSION", "Session stopped")
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
            Task { @MainActor in
                vtmdLog("HOOK", "Agent init received")
                self?.session?.state = .ready
            }
        }
        hooks.onResponse = { [weak self] markdown in
            Task { @MainActor in
                vtmdLog("HOOK", "Agent response received (\(markdown.count) chars)")
                self?.markdown = markdown
                // Spec step 16: write processed markdown to session .md file
                if let path = self?.session?.mdPath {
                    try? self?.fileManager.writeMarkdown(markdown, to: path)
                }
                // Reset processing state
                if self?.session?.state == .processing {
                    self?.session?.state = self?.stateBeforeProcessing ?? .ready
                }
                // Spec step 18: mark agent done, promote pending, flush if needed
                let shouldFlush = await self?.buffer.agentDone() ?? false
                if shouldFlush { await self?.flushBuffer() }
            }
        }
        // Spec step 26: fallback if agent hasn't posted via /response
        hooks.onNotification = { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                let busy = await self.buffer.agentBusy
                guard busy else { return }

                var content: String?
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let path = json["transcript_path"] as? String {
                    content = try? String(contentsOfFile: path, encoding: .utf8)
                } else if let notesPath = self.session?.notesPath {
                    content = try? String(contentsOf: notesPath, encoding: .utf8)
                }

                guard let markdown = content, !markdown.isEmpty else { return }
                vtmdLog("HOOK", "Notification fallback: using transcript (\(markdown.count) chars)")
                self.hooks.onResponse?(markdown)
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

    // Spec step 12: flush accumulated buffer, mark agentBusy, set processing state
    private func sendBufferText(_ text: String) async {
        guard !text.isEmpty, let sess = session else { return }
        stateBeforeProcessing = sess.state
        session?.state = .processing
        vtmdLog("SESSION", "Flushing buffer: \(text.prefix(120))")

        let currentMarkdown = fileManager.readMarkdown(from: sess.mdPath)
        let payload = ["current_markdown": currentMarkdown, "new_transcript": text]

        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: json, encoding: .utf8) else { return }

        let tmux = TmuxSession(name: sess.tmuxSessionName)
        try? await tmux.paste(jsonStr)
    }

    private func flushBuffer() async {
        let text = await buffer.flush()
        await sendBufferText(text)
    }

    // Spec step 22: drains both accumulated and pending regardless of word count
    private func flushAllBuffer() async {
        let text = await buffer.flushAll()
        await sendBufferText(text)
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
                    vtmdLog("WHISPER", "Transcribed: \(text)")
                    await MainActor.run { self.transcript += text + " " }

                    // Spec step 9: BLANK_AUDIO triggers flushAll immediately
                    if text == "[BLANK_AUDIO]" {
                        await self.flushAllBuffer()
                    } else {
                        let appended = await self.buffer.add(text)
                        if appended { await self.flushBuffer() }
                    }

                    // Spec step 10: append raw transcript to .txt file
                    if let session = await self.session {
                        await MainActor.run { try? self.fileManager.appendTranscript(text, to: session.txtPath) }
                    }
                }
            } catch {
                vtmdLog("WHISPER", "Transcription error: \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: wavURL)
        }
    }

    // Spec step 19: 5s silence triggers flush
    nonisolated func audioCaptureDidDetectSilence() {
        Task { @MainActor in
            await flushBuffer()
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
