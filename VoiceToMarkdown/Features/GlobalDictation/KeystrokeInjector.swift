import ApplicationServices
import CoreGraphics
import Foundation

final class KeystrokeInjector {
    static func requestAccessibilityIfNeeded() -> Bool {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func typeText(_ text: String) {
        guard hasAccessibilityPermission else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            guard let codeUnit = UInt16(exactly: scalar.value) else { continue }
            let charArray: [UniChar] = [codeUnit]
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: charArray)
            keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: charArray)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
