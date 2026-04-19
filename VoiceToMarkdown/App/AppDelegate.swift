import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var agentWindow: NSWindow?
    private var hudWindow: NSWindow?

    private let coordinator = SessionCoordinator()
    private let dictationManager = GlobalDictationManager()
    private let downloader = ModelDownloader()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? VTMDFileManager.shared.bootstrap()
        setupStatusBar()
        checkAccessibilityPermission()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceToMarkdown")
            button.action = #selector(statusBarClicked)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start Agent Mode", action: #selector(openAgentWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Model Settings", action: #selector(openModelSelector), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
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

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Voice to Markdown"
            window.center()
            window.contentView = NSHostingView(rootView: contentView)
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            agentWindow = window
        }
        agentWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openModelSelector() {
        let view = ModelSelectorView(downloader: downloader)
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Whisper Models"
        panel.center()
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func checkAccessibilityPermission() {
        if !KeystrokeInjector.requestAccessibilityIfNeeded() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.showAccessibilityAlert()
            }
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "VoiceToMarkdown needs Accessibility access to inject transcribed text. Enable it in System Settings → Privacy & Security → Accessibility."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}

struct AgentOrchestratorView: View {
    @ObservedObject var hudVM: HUDViewModel
    @ObservedObject var editorVM: MarkdownEditorViewModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MarkdownEditorView(viewModel: editorVM)
            HUDBubbleView(viewModel: hudVM)
                .padding(20)
        }
    }
}
