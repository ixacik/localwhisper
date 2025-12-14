//
//  TextInjector.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import Foundation
import AppKit
import CoreGraphics
import Carbon.HIToolbox

/// Injects text into the currently focused text field using keyboard simulation
@MainActor
final class TextInjector {
    private let typingDelay: TimeInterval = 0.001  // Small delay between characters

    init() {}

    /// Type text into the currently focused text field
    /// Uses CGEvent to simulate keyboard input
    func typeText(_ text: String) {
        guard !text.isEmpty else { return }

        let source = CGEventSource(stateID: .hidSystemState)

        // Type each character
        for char in text {
            typeCharacter(char, source: source)
        }
    }

    /// Type a single character using CGEvent
    private func typeCharacter(_ char: Character, source: CGEventSource?) {
        let string = String(char)

        // Create key down event
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
            return
        }

        // Create key up event
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }

        // Set the unicode string for both events
        var unicodeChars = Array(string.utf16)
        keyDown.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)
        keyUp.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: &unicodeChars)

        // Post the events
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Type text with special key support (e.g., newlines, tabs)
    func typeTextWithSpecialKeys(_ text: String) {
        guard !text.isEmpty else { return }

        let source = CGEventSource(stateID: .hidSystemState)

        for char in text {
            switch char {
            case "\n":
                pressKey(keyCode: VirtualKey.returnKey, source: source)
            case "\t":
                pressKey(keyCode: VirtualKey.tab, source: source)
            case "\r":
                // Ignore carriage returns
                continue
            default:
                typeCharacter(char, source: source)
            }
        }
    }

    /// Press a specific key by keycode
    private func pressKey(keyCode: Int, source: CGEventSource?) {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else {
            return
        }

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Paste text from clipboard (faster for long text)
    func pasteText(_ text: String) {
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Set new text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)

        let keyCode = CGKeyCode(VirtualKey.keyV)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        // Restore previous clipboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let previous = previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }
}

// MARK: - Virtual Key Codes

private enum VirtualKey {
    static let returnKey: Int = 0x24
    static let tab: Int = 0x30
    static let space: Int = 0x31
    static let delete: Int = 0x33
    static let escape: Int = 0x35
    static let command: Int = 0x37
    static let shift: Int = 0x38
    static let option: Int = 0x3A
    static let control: Int = 0x3B
    static let keyV: Int = 0x09
}
