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
import os

/// Injects text into the currently focused text field via clipboard paste.
///
/// This is the most reliable cross-app solution on macOS, used by Alfred, Raycast,
/// Espanso, and Keyboard Maestro. Works in ~99% of apps including terminals and browsers.
@MainActor
final class TextInjector {

    init() {
        Log.injection.info("TextInjector initialized")
    }

    // MARK: - Public API

    /// Inject text into the focused field via clipboard paste (⌘V)
    func injectText(_ text: String) async {
        guard !text.isEmpty else {
            Log.injection.warning("injectText called with empty string")
            return
        }

        Log.injection.info("Injecting \(text.count) characters")

        // Get the frontmost application's PID
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            Log.injection.error("Could not get frontmost application")
            return
        }
        let pid = frontmostApp.processIdentifier
        Log.injection.debug("Target: \(frontmostApp.localizedName ?? "unknown") (pid: \(pid))")

        let pasteboard = NSPasteboard.general

        // Save current clipboard contents
        let previousContents = pasteboard.string(forType: .string)

        // Set our text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        try? await Task.sleep(for: .milliseconds(10))

        // Create ⌘V key events
        let vKeyCode = CGKeyCode(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
            Log.injection.error("Failed to create paste key events")
            restoreClipboard(previous: previousContents)
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        // Post directly to the frontmost application's process
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)

        Log.injection.info("Pasted via ⌘V to pid \(pid)")

        // Wait for paste to complete before restoring clipboard
        try? await Task.sleep(for: .milliseconds(100))

        // Restore previous clipboard contents
        restoreClipboard(previous: previousContents)
    }

    // MARK: - Private

    private func restoreClipboard(previous: String?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let previous {
            pasteboard.setString(previous, forType: .string)
        }
    }
}
