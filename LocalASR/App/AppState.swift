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
        case loadingModel
        case error(String)
    }

    var dictationState: DictationState = .idle

    var isListening: Bool {
        dictationState == .listening
    }

    var isLoadingModel: Bool {
        dictationState == .loadingModel
    }

    // MARK: - Audio Levels (frequency spectrum, 14 bands)
    var audioLevels: [Float] = Array(repeating: 0, count: 14)

    // MARK: - Model State
    var isModelLoaded = false
    var isModelCached = false
    var cachedModelInfo: CachedModelInfo?

    /// Button text for model action
    var modelActionText: String {
        if isModelLoaded {
            return "Model Loaded"
        } else if isModelCached {
            return "Load Model"
        } else {
            return "Download Model (~1.5 GB)"
        }
    }

    // MARK: - Overlay
    var showOverlay = false

    // MARK: - Status
    var statusMessage: String {
        switch dictationState {
        case .idle:
            if !allPermissionsGranted {
                return "Setup required"
            }
            return isModelLoaded ? "Ready — Hold ⌘⎋ to dictate" : "Model not loaded"
        case .listening:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .loadingModel:
            return isModelCached ? "Loading model..." : "Downloading model..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
