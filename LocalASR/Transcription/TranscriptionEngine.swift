//
//  TranscriptionEngine.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import Foundation
import WhisperKit

/// Wrapper around WhisperKit for speech-to-text transcription
actor TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private var isLoading = false

    // Model configuration
    // Using distil-large-v3 for best speed/accuracy balance
    // Falls back to large-v3-turbo if distil not available
    private let preferredModels = [
        "distil-large-v3",
        "large-v3-turbo",
        "large-v3",
        "base.en"  // Fallback for testing
    ]

    // Track last transcription to avoid duplicates
    private var lastTranscription = ""

    init() {}

    // MARK: - Model Management

    /// Check if model is already downloaded and ready
    func isModelAvailable() async -> Bool {
        do {
            let availableModels = try await WhisperKit.fetchAvailableModels()
            return !availableModels.isEmpty
        } catch {
            return false
        }
    }

    /// Load the WhisperKit model with progress tracking
    func loadModel(onProgress: @escaping (Double) -> Void) async throws {
        guard !isLoading else { return }
        isLoading = true

        defer { isLoading = false }

        // Try to find best available model
        var modelToUse: String?

        do {
            let availableModels = try await WhisperKit.fetchAvailableModels()

            // Find first preferred model that's available
            for preferred in preferredModels where availableModels.contains(where: { $0.contains(preferred) }) {
                modelToUse = preferred
                break
            }

            // If no preferred model found, use first available
            if modelToUse == nil, let first = availableModels.first {
                modelToUse = first
            }
        } catch {
            print("Error fetching models: \(error)")
            // Default to base.en for reliability
            modelToUse = "base.en"
        }

        guard let model = modelToUse else {
            throw TranscriptionError.noModelAvailable
        }

        print("Loading WhisperKit model: \(model)")

        // Initialize WhisperKit with the selected model
        // Note: WhisperKit handles downloading automatically
        let config = WhisperKitConfig(
            model: model,
            verbose: true,
            prewarm: true,
            load: true
        )

        whisperKit = try await WhisperKit(config)

        // Signal completion
        onProgress(1.0)

        print("WhisperKit model loaded successfully")
    }

    // MARK: - Transcription

    /// Transcribe audio data (WAV format) to text
    func transcribe(audioData: Data) async throws -> String {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        // Write audio data to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        try audioData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Transcribe
        let results = try await whisperKit.transcribe(audioPath: tempURL.path)

        guard let result = results.first else {
            return ""
        }

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Avoid duplicates from overlapping chunks
        let newText = removeDuplicatePrefix(new: text, previous: lastTranscription)
        lastTranscription = text

        return newText
    }

    /// Transcribe from audio file URL
    func transcribe(audioURL: URL) async throws -> String {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let results = try await whisperKit.transcribe(audioPath: audioURL.path)

        guard let result = results.first else {
            return ""
        }

        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reset the last transcription tracking (call when starting new dictation)
    func resetState() {
        lastTranscription = ""
    }

    // MARK: - Helpers

    /// Remove duplicate prefix from overlapping audio chunks
    private func removeDuplicatePrefix(new: String, previous: String) -> String {
        guard !previous.isEmpty, !new.isEmpty else { return new }

        // Find common suffix of previous that matches prefix of new
        let words = previous.split(separator: " ")
        let newWords = new.split(separator: " ")

        // Check last few words of previous for match with start of new
        for windowSize in (1...min(5, words.count)).reversed() {
            let suffix = words.suffix(windowSize)
            let prefix = newWords.prefix(windowSize)

            if Array(suffix) == Array(prefix) {
                // Found overlap, return only the new part
                let remainingWords = newWords.dropFirst(windowSize)
                if remainingWords.isEmpty {
                    return ""
                }
                return " " + remainingWords.joined(separator: " ")
            }
        }

        // No overlap found, add space before new text
        return " " + new
    }
}

// MARK: - Errors

enum TranscriptionError: Error, LocalizedError {
    case modelNotLoaded
    case noModelAvailable
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded"
        case .noModelAvailable:
            return "No suitable Whisper model available"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
