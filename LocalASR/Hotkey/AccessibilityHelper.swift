//
//  AccessibilityHelper.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import Foundation
import AppKit
import ApplicationServices

/// Helper for managing Accessibility permissions
/// Required for global hotkey detection and text injection
enum AccessibilityHelper {
    /// Check if accessibility permission is granted
    static func isAccessibilityEnabled() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Request accessibility permission
    /// Opens System Preferences to the Accessibility pane
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Preferences directly to Accessibility settings
    static func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Start monitoring for accessibility permission changes
    /// Useful for updating UI when user grants permission
    static func startMonitoringPermission(interval: TimeInterval = 1.0, onChange: @escaping (Bool) -> Void) -> Timer {
        var lastState = isAccessibilityEnabled()

        return Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            let currentState = isAccessibilityEnabled()
            if currentState != lastState {
                lastState = currentState
                onChange(currentState)
            }
        }
    }
}
