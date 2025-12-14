//
//  TranscriptionEngine.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import Foundation
import WhisperKit
import os

/// Information about a cached model
struct CachedModelInfo: Sendable {
    let name: String
    let sizeBytes: Int64
    let path: URL

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

/// Wrapper around WhisperKit for speech-to-text transcription
actor TranscriptionEngine {
    private var whisperKit: WhisperKit?
    private var isLoading = false
    private var loadedModelName: String?

    // Model configuration
    // Using distil-large-v3 for best speed/accuracy balance
    // Falls back to smaller models if not available
    private let preferredModels = [
        "distil-large-v3",
        "large-v3-turbo",
        "large-v3",
        "base.en"
    ]

    /// Whether the model is loaded into memory and ready for transcription
    var isReady: Bool {
        whisperKit != nil
    }

    /// Name of the currently loaded model
    var currentModelName: String? {
        loadedModelName
    }

    init() {
        Log.transcription.info("TranscriptionEngine initialized")
    }

    // MARK: - Model Cache Management

    /// WhisperKit stores models in ~/Library/Application Support/WhisperKit/
    /// We use a consistent downloadBase to ensure deterministic cache location
    private static let modelStorageDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WhisperKit")
    }()

    /// Get the directory where a specific model variant is stored
    private func getModelDirectory(for variant: String) -> URL {
        Self.modelStorageDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(variant)
    }

    /// Check if any WhisperKit model is cached on disk
    func isModelCached() async -> Bool {
        let fileManager = FileManager.default
        let modelsDir = Self.modelStorageDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")

        guard fileManager.fileExists(atPath: modelsDir.path) else {
            Log.transcription.debug("Models directory does not exist: \(modelsDir.path)")
            return false
        }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: modelsDir.path)

            // Check if any of our preferred models exist
            if let foundModel = preferredModels.first(where: { preferred in
                contents.contains { $0.contains(preferred) }
            }) {
                Log.transcription.debug("Found cached model matching: \(foundModel)")
                return true
            }

            // Check if any model directory exists at all
            let hasAnyModel = contents.contains { item in
                var isDir: ObjCBool = false
                let path = modelsDir.appendingPathComponent(item).path
                return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            }
            return hasAnyModel
        } catch {
            Log.transcription.error("Error checking cache: \(error.localizedDescription)")
            return false
        }
    }

    /// Get information about cached models
    func getCachedModelInfo() async -> CachedModelInfo? {
        let fileManager = FileManager.default
        let modelsDir = Self.modelStorageDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")

        guard fileManager.fileExists(atPath: modelsDir.path) else { return nil }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: modelsDir.path)

            // Find best available model (prefer our preferred order)
            var bestModel: String?
            for preferred in preferredModels {
                if let match = contents.first(where: { $0.contains(preferred) }) {
                    bestModel = match
                    break
                }
            }

            // Fallback to first directory found
            if bestModel == nil {
                bestModel = contents.first { item in
                    var isDir: ObjCBool = false
                    let path = modelsDir.appendingPathComponent(item).path
                    return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
                }
            }

            guard let modelName = bestModel else { return nil }

            let modelDir = modelsDir.appendingPathComponent(modelName)
            let size = try calculateDirectorySize(at: modelDir)

            // Clean up model name for display (remove openai_ prefix if present)
            let displayName = modelName
                .replacingOccurrences(of: "openai_whisper-", with: "")
                .replacingOccurrences(of: "openai_", with: "")

            return CachedModelInfo(
                name: displayName,
                sizeBytes: size,
                path: modelDir
            )
        } catch {
            Log.transcription.error("Error getting cache info: \(error.localizedDescription)")
        }

        return nil
    }

    /// Delete cached model files to free up disk space
    func deleteModelCache() async throws {
        let fileManager = FileManager.default
        let whisperKitDir = Self.modelStorageDirectory

        guard fileManager.fileExists(atPath: whisperKitDir.path) else {
            throw TranscriptionError.cacheNotFound
        }

        // Delete the entire WhisperKit directory
        try fileManager.removeItem(at: whisperKitDir)
        Log.transcription.info("Deleted model cache at: \(whisperKitDir.path)")

        // Clear in-memory model
        whisperKit = nil
        loadedModelName = nil
    }

    private func calculateDirectorySize(at url: URL) throws -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            totalSize += Int64(resourceValues.fileSize ?? 0)
        }

        return totalSize
    }

    // MARK: - Model Loading

    /// Load the WhisperKit model (downloads if not cached, otherwise loads from disk)
    func loadModel() async throws {
        guard !isLoading else {
            Log.transcription.warning("loadModel called while already loading")
            return
        }
        isLoading = true
        Log.transcription.info("loadModel started")

        defer { isLoading = false }

        // Determine which model to use
        var modelToUse: String?

        do {
            Log.transcription.info("Fetching available models...")
            let availableModels = try await WhisperKit.fetchAvailableModels()
            Log.transcription.info("Available models: \(availableModels)")

            // Find first preferred model that's available
            for preferred in preferredModels where availableModels.contains(where: { $0.contains(preferred) }) {
                modelToUse = preferred
                break
            }

            // Fallback to first available
            if modelToUse == nil, let first = availableModels.first {
                modelToUse = first
            }
        } catch {
            Log.transcription.error("Error fetching models: \(error.localizedDescription)")
            modelToUse = "base.en"
        }

        guard let model = modelToUse else {
            Log.transcription.error("No model available")
            throw TranscriptionError.noModelAvailable
        }

        let isCached = await isModelCached()
        if isCached {
            Log.transcription.info("Loading cached model: \(model)")
        } else {
            Log.transcription.info("Downloading model: \(model) — this may take a few minutes...")
        }

        // Use explicit downloadBase to ensure consistent cache location
        let config = WhisperKitConfig(
            model: model,
            downloadBase: Self.modelStorageDirectory,
            verbose: true,
            prewarm: true,
            load: true
        )

        whisperKit = try await WhisperKit(config)
        loadedModelName = model

        Log.transcription.info("Model loaded successfully: \(model)")
    }

    // MARK: - Transcription

    /// Transcribe audio data (WAV format) to text
    func transcribe(audioData: Data) async throws -> String {
        Log.transcription.info("transcribe() called with \(audioData.count) bytes")

        guard let whisperKit = whisperKit else {
            Log.transcription.error("transcribe() failed: model not loaded")
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

        Log.transcription.info("Transcribing...")
        let results = try await whisperKit.transcribe(audioPath: tempURL.path)

        guard let result = results.first else {
            Log.transcription.warning("No transcription results returned")
            return ""
        }

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.transcription.info("Transcription: '\(text)'")

        return text
    }

    /// Reset state for new dictation session
    func resetState() {
        // No state to reset in non-streaming mode
    }
}

// MARK: - Errors

enum TranscriptionError: Error, LocalizedError {
    case modelNotLoaded
    case noModelAvailable
    case transcriptionFailed(String)
    case cacheNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded"
        case .noModelAvailable:
            return "No suitable Whisper model available"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .cacheNotFound:
            return "Model cache directory not found"
        }
    }
}
