//
//  AppState.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import SwiftUI
import Observation

/// Central application state shared across the app
@Observable
@MainActor
final class AppState {
    // MARK: - Permissions
    var hasMicrophonePermission = false
    var hasAccessibilityPermission = false

    var allPermissionsGranted: Bool {
        hasMicrophonePermission && hasAccessibilityPermission
    }

    // MARK: - Dictation State
    enum DictationState: Equatable {
        case idle
        case listening
        case processing
        case downloading(progress: Double)
        case error(String)
    }

    var dictationState: DictationState = .idle

    var isListening: Bool {
        dictationState == .listening
    }

    // MARK: - Audio Levels
    var audioLevels: [Float] = Array(repeating: 0, count: 20)

    // MARK: - Model State
    var isModelLoaded = false
    var modelDownloadProgress: Double = 0

    // MARK: - Overlay
    var showOverlay = false

    // MARK: - Status
    var statusMessage: String {
        switch dictationState {
        case .idle:
            return allPermissionsGranted ? "Ready — Hold ⌘⎋ to dictate" : "Setup required"
        case .listening:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .downloading(let progress):
            return "Downloading model: \(Int(progress * 100))%"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
