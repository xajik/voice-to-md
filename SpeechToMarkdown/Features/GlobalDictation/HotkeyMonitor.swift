import Carbon
import Foundation

final class HotkeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onTrigger: (() -> Void)?

    private static var activeMonitor: HotkeyMonitor?

    private static let hotKeySignature = OSType(
        (UInt32(Character("V").asciiValue!) << 24) |
        (UInt32(Character("T").asciiValue!) << 16) |
        (UInt32(Character("M").asciiValue!) << 8) |
        UInt32(Character("D").asciiValue!)
    )

    func register(keyCode: UInt32, modifiers: UInt32, onTrigger: @escaping () -> Void) throws {
        self.onTrigger = onTrigger
        Self.activeMonitor = self

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                monitor.onTrigger?()
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else { throw HotkeyError.handlerInstallFailed(status) }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        let regStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard regStatus == noErr else { throw HotkeyError.registrationFailed(regStatus) }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
            eventHandlerRef = nil
        }
        Self.activeMonitor = nil
    }

    deinit { unregister() }
}

enum HotkeyError: Error, LocalizedError {
    case registrationFailed(OSStatus)
    case handlerInstallFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let code): return "Hotkey registration failed: \(code)"
        case .handlerInstallFailed(let code): return "Event handler install failed: \(code)"
        }
    }
}
