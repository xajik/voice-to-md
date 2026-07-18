import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var agentWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var dictationPanel: NSPanel?
    private var cancellables = Set<AnyCancellable>()
    private var dictationMenuItem: NSMenuItem?
    private var dictationActive = false
    private var hudVM: HUDViewModel?
    private var historyPopover: NSPopover?

    private let coordinator = SessionCoordinator()
    private let dictationManager = GlobalDictationManager()
    private let downloader = ModelDownloader()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? STMDFileManager.shared.bootstrap()
        stmdLog("APP", "Application launched")
        setupStatusBar()
        setupDictationPanel()
        checkAccessibilityPermission()
        startGlobalDictation()
        applyLaunchAtLogin(BackendSettings.shared.launchAtLogin)

        BackendSettings.shared.$launchAtLogin
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                Task { @MainActor in self?.applyLaunchAtLogin(enabled) }
            }
            .store(in: &cancellables)

        // Re-load the whisper model when the Settings selection changes.
        // @Published emits on willSet, so hop to the next runloop turn to
        // read the committed value.
        BackendSettings.shared.$whisperModel
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.restartDictationIfActive() }
            }
            .store(in: &cancellables)

        // A finished download may be the model the user just selected — reload,
        // or start dictation if it never came up for lack of a model.
        downloader.$progress
            .compactMap { $0 }
            .filter { $0.isComplete && $0.error == nil }
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.dictationActive {
                        self.restartDictationIfActive()
                    } else {
                        self.startGlobalDictation()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            stmdLog("APP", "Launch at login \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
    }

    private func restartDictationIfActive() {
        guard dictationActive else { return }
        dictationManager.stop()
        dictationActive = false
        startGlobalDictation()
    }

    private func setupDictationPanel() {
        // Non-activating so focus stays in the target app — keystroke
        // injection must land wherever the user was typing.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 66),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: DictationHUDView(manager: dictationManager))
        dictationPanel = panel

        dictationManager.$phase
            .sink { [weak self] phase in
                if phase == .idle {
                    self?.dictationPanel?.orderOut(nil)
                } else {
                    self?.showDictationPanel()
                }
            }
            .store(in: &cancellables)
    }

    private func showDictationPanel() {
        guard let panel = dictationPanel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.minY + frame.height * 0.7
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = Self.statusBarIcon()
            button.action = #selector(statusBarClicked)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start Agent Mode", action: #selector(openAgentWindow), keyEquivalent: ""))
        let dictationItem = NSMenuItem(title: "Global Dictation (⌘⌥])", action: #selector(toggleDictation), keyEquivalent: "")
        menu.addItem(dictationItem)
        dictationMenuItem = dictationItem
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openModelSelector), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    /// Speech bubble with a character (voice → text) plus a sparkles badge (AI),
    /// composed as a template image so it tints with the menu bar.
    private static func statusBarIcon() -> NSImage? {
        let baseConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let base = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "SpeechToMarkdown")?
            .withSymbolConfiguration(baseConfig) else {
            return NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "SpeechToMarkdown")
        }
        guard let badge = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)) else {
            return base
        }
        let icon = NSImage(size: NSSize(width: 21, height: 17), flipped: false) { _ in
            base.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
            badge.draw(in: NSRect(x: 13, y: 9, width: 8, height: 8))
            return true
        }
        icon.isTemplate = true
        return icon
    }

    @objc private func statusBarClicked() {
        statusItem?.menu?.popUp(
            positioning: nil,
            at: NSEvent.mouseLocation,
            in: nil
        )
    }

    @objc private func openAgentWindow() {
        if agentWindow == nil {
            let hudVM = HUDViewModel(coordinator: coordinator)
            let editorVM = MarkdownEditorViewModel(coordinator: coordinator)
            let contentView = AgentOrchestratorView(hudVM: hudVM, editorVM: editorVM)
            self.hudVM = hudVM

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Speech to Markdown"
            window.center()
            window.contentView = NSHostingView(rootView: contentView)
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.toolbar = makeAgentToolbar()
            window.isReleasedWhenClosed = false
            // No stop button in the HUD — closing the window ends the session
            window.delegate = self
            agentWindow = window
        }
        agentWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeAgentToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "AgentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    @objc private func newSessionTapped(_ sender: NSButton) {
        hudVM?.newSession()
    }

    @objc private func toggleHistoryPopover(_ sender: NSButton) {
        if let popover = historyPopover, popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let hudVM else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.contentViewController = NSHostingController(
            rootView: SessionHistoryView(viewModel: hudVM) { [weak popover] in
                popover?.performClose(nil)
            }
        )
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        historyPopover = popover
    }

    @objc private func openModelSelector() {
        if settingsWindow == nil {
            let view = ModelSelectorView(downloader: downloader)
            let panel = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Settings"
            panel.center()
            panel.contentView = NSHostingView(rootView: view)
            // AppKit releases windows on close by default; combined with ARC
            // that double-releases and crashes in the close animation.
            panel.isReleasedWhenClosed = false
            settingsWindow = panel
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func checkAccessibilityPermission() {
        _ = KeystrokeInjector.requestAccessibilityIfNeeded()
    }

    private func startGlobalDictation() {
        let fm = STMDFileManager.shared
        guard let size = BackendSettings.shared.resolvedWhisperModel(in: fm) else {
            stmdLog("APP", "Global dictation not started: no whisper model downloaded")
            dictationMenuItem?.state = .off
            return
        }
        do {
            try dictationManager.start(modelPath: size.localPath(in: fm.modelsDir))
            dictationActive = true
            dictationMenuItem?.state = .on
        } catch {
            stmdLog("APP", "Global dictation failed to start: \(error.localizedDescription)")
        }
    }

    @objc private func toggleDictation() {
        if dictationActive {
            dictationManager.stop()
            dictationActive = false
            dictationMenuItem?.state = .off
        } else {
            startGlobalDictation()
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === agentWindow else { return }
        Task { await coordinator.stopSession() }
    }
}

extension AppDelegate: NSToolbarDelegate {
    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .newSession:
            let icon = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "New Session")
            let button = NSButton(image: icon ?? NSImage(), target: self, action: #selector(newSessionTapped(_:)))
            button.bezelStyle = .texturedRounded
            button.isBordered = false
            button.toolTip = "New session"

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = button
            item.label = "New"
            return item
        case .sessionHistory:
            let icon = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Recent Sessions")
            let button = NSButton(image: icon ?? NSImage(), target: self, action: #selector(toggleHistoryPopover(_:)))
            button.bezelStyle = .texturedRounded
            button.isBordered = false
            button.toolTip = "Recent sessions"

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = button
            item.label = "History"
            return item
        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .newSession, .sessionHistory]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.newSession, .sessionHistory, .flexibleSpace]
    }
}

private extension NSToolbarItem.Identifier {
    static let newSession = NSToolbarItem.Identifier("newSession")
    static let sessionHistory = NSToolbarItem.Identifier("sessionHistory")
}

struct AgentOrchestratorView: View {
    @ObservedObject var hudVM: HUDViewModel
    @ObservedObject var editorVM: MarkdownEditorViewModel
    @State private var showRawInput = false

    private let rawPaneHeight: CGFloat = 120

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                MarkdownEditorView(viewModel: editorVM)
                Divider()
                rawInputBar
                if showRawInput {
                    RawTranscriptView(viewModel: hudVM)
                        .frame(height: rawPaneHeight)
                }
            }
            HUDBubbleView(viewModel: hudVM)
                .padding(.trailing, 64)
                .padding(.bottom, 64)
        }
    }

    private var rawInputBar: some View {
        HStack(spacing: 6) {
            Image(systemName: showRawInput ? "chevron.down" : "chevron.up")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Raw input")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if !hudVM.transcript.isEmpty {
                Text("\(TranscriptBuffer.wordCount(in: hudVM.transcript)) words")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { showRawInput.toggle() }
        }
    }
}
