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

        // The stop-hotkey (⌘⌥]) is often still physically held when we get
        // here; synthetic events inherit held modifiers and become shortcuts
        // instead of text. Wait for release, then force-clear flags anyway.
        waitForModifierRelease()

        let source = CGEventSource(stateID: .hidSystemState)
        for chunk in utf16Chunks(text, size: 16) {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            keyDown?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyUp?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyDown?.flags = []
            keyUp?.flags = []
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            // Pace events so target apps don't drop bursts
            usleep(8000)
        }
    }

    private static func waitForModifierRelease(timeout: TimeInterval = 2) {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.hidSystemState)
            if flags.intersection(modifiers).isEmpty { return }
            usleep(50_000)
        }
    }

    static func utf16Chunks(_ text: String, size: Int) -> [[UniChar]] {
        let units = Array(text.utf16)
        guard !units.isEmpty else { return [] }
        return stride(from: 0, to: units.count, by: size).map { start in
            Array(units[start..<min(start + size, units.count)])
        }
    }
}
