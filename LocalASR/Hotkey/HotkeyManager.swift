//
//  HotkeyManager.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import AppKit
import Carbon.HIToolbox
import HotKey
import os

/// Manages global hotkey detection for push-to-talk functionality
/// Uses HotKey library (Carbon RegisterEventHotKey) for reliable cross-app detection
@MainActor
final class HotkeyManager {
    private var hotKey: HotKey?

    /// Fallback: poll modifier keys to detect stuck state
    private var modifierPollTimer: Timer?

    /// Safety timeout to prevent infinite listening
    private var safetyTimeoutTask: Task<Void, Never>?

    /// Maximum recording duration before auto-stopping (safety)
    private let maxRecordingDuration: TimeInterval = 60

    /// Polling interval for modifier key state
    private let modifierPollInterval: TimeInterval = 0.1

    private let onKeyDown: @MainActor () -> Void
    private let onKeyUp: @MainActor () -> Void

    private(set) var isActive = false

    init(onKeyDown: @escaping @MainActor () -> Void, onKeyUp: @escaping @MainActor () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
    }

    // MARK: - Public API

    /// Start monitoring for the hotkey (⌘+Escape)
    func start() {
        guard hotKey == nil else { return }

        // Register ⌘+Escape using Carbon APIs (via HotKey library)
        // This works reliably even in Secure Input mode (terminals, password fields)
        let hotKey = HotKey(key: .escape, modifiers: [.command])

        hotKey.keyDownHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleKeyDown()
            }
        }

        hotKey.keyUpHandler = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleKeyUp()
            }
        }

        self.hotKey = hotKey
        Log.hotkey.info("Hotkey manager started - listening for ⌘⎋")
    }

    /// Stop monitoring for the hotkey
    func stop() {
        stopSafetyMechanisms()
        hotKey = nil
        isActive = false
        Log.hotkey.info("Hotkey manager stopped")
    }

    /// Force reset the active state (escape hatch for stuck detection)
    func forceReset() {
        guard isActive else { return }
        Log.hotkey.warning("Force resetting hotkey state")
        handleKeyUp()
    }

    // MARK: - Event Handling

    private func handleKeyDown() {
        guard !isActive else { return }

        isActive = true
        Log.hotkey.debug("⌘⎋ pressed")

        // Start safety mechanisms
        startModifierPolling()
        startSafetyTimeout()

        onKeyDown()
    }

    private func handleKeyUp() {
        guard isActive else { return }

        isActive = false
        Log.hotkey.debug("⌘⎋ released")

        // Stop safety mechanisms
        stopSafetyMechanisms()

        onKeyUp()
    }

    // MARK: - Safety Mechanisms

    /// Start polling modifier keys to detect if Cmd was released without us receiving the event
    private func startModifierPolling() {
        modifierPollTimer?.invalidate()

        modifierPollTimer = Timer.scheduledTimer(
            withTimeInterval: modifierPollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkModifierState()
            }
        }
    }

    /// Check if Command key is still pressed using CGEventSource
    /// This works independently of event taps and Secure Input mode
    private func checkModifierState() {
        guard isActive else {
            modifierPollTimer?.invalidate()
            modifierPollTimer = nil
            return
        }

        // Query the current modifier flags directly from the system
        let currentFlags = CGEventSource.flagsState(.hidSystemState)
        let isCmdPressed = currentFlags.contains(.maskCommand)

        if !isCmdPressed {
            Log.hotkey.warning("Detected Cmd release via polling (event was missed)")
            handleKeyUp()
        }
    }

    /// Start a safety timeout to prevent infinite recording
    private func startSafetyTimeout() {
        safetyTimeoutTask?.cancel()

        safetyTimeoutTask = Task { [weak self, maxRecordingDuration] in
            try? await Task.sleep(for: .seconds(maxRecordingDuration))

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self, self.isActive else { return }
                Log.hotkey.warning("Safety timeout triggered after \(maxRecordingDuration)s")
                self.handleKeyUp()
            }
        }
    }

    /// Stop all safety mechanisms
    private func stopSafetyMechanisms() {
        modifierPollTimer?.invalidate()
        modifierPollTimer = nil
        safetyTimeoutTask?.cancel()
        safetyTimeoutTask = nil
    }
}
