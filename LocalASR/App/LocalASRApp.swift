//
//  LocalASRApp.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import SwiftUI
import SwiftData
import AppKit
import os

@main
struct LocalASRApp: App {
    @State private var appState = AppState()
    @State private var hotkeyManager: HotkeyManager?
    @State private var audioManager: AudioCaptureManager?
    @State private var transcriptionEngine: TranscriptionEngine?
    @State private var textInjector = TextInjector()
    @State private var overlayController: OverlayWindowController?

    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: DictationSession.self)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            // Pass modelContext explicitly - MenuBarExtra doesn't properly propagate environment
            MenuBarView(
                appState: appState,
                transcriptionEngine: $transcriptionEngine,
                modelContext: modelContainer.mainContext
            )
        } label: {
            Label("LocalASR", systemImage: appState.isListening ? "waveform.circle.fill" : "waveform")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView(
                appState: appState,
                transcriptionEngine: $transcriptionEngine
            )
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @Bindable var appState: AppState
    @Binding var transcriptionEngine: TranscriptionEngine?
    let modelContext: ModelContext
    @Environment(\.openSettings) private var openSettings
    @State private var hotkeyManager: HotkeyManager?
    @State private var audioManager: AudioCaptureManager?
    @State private var textInjector = TextInjector()
    @State private var overlayController: OverlayWindowController?
    @State private var hasInitialized = false

    var body: some View {
        Group {
            // Status section
            Section {
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(appState.statusMessage)
                }
            }

            Divider()

            // Permissions section
            if !appState.allPermissionsGranted {
                Section("Setup Required") {
                    Button {
                        Task { await requestMicrophonePermission() }
                    } label: {
                        HStack {
                            Image(systemName: appState.hasMicrophonePermission ? "checkmark.circle.fill" : "circle")
                            Text("Microphone Access")
                        }
                    }
                    .disabled(appState.hasMicrophonePermission)

                    Button {
                        AccessibilityHelper.requestPermission()
                        AccessibilityHelper.openAccessibilityPreferences()
                    } label: {
                        HStack {
                            Image(systemName: appState.hasAccessibilityPermission ? "checkmark.circle.fill" : "circle")
                            Text("Accessibility Access")
                        }
                    }
                    .disabled(appState.hasAccessibilityPermission)
                }

                Divider()
            }

            // Model section
            if !appState.isModelLoaded {
                Section {
                    if appState.isLoadingModel {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(appState.isModelCached ? "Loading model..." : "Downloading model...")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button(appState.modelActionText) {
                            Task { await loadModel() }
                        }
                    }
                }

                Divider()
            }

            // Settings
            Button("Preferences...") {
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit LocalASR") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .task {
            guard !hasInitialized else { return }
            hasInitialized = true
            await initializeApp()
        }
    }

    private var statusColor: Color {
        switch appState.dictationState {
        case .idle where appState.allPermissionsGranted && appState.isModelLoaded:
            return .green
        case .listening:
            return .orange
        case .processing:
            return .blue
        case .loadingModel:
            return .yellow
        case .error:
            return .red
        default:
            return .gray
        }
    }

    private func initializeApp() async {
        Log.app.info("Initializing app...")

        // Check permissions
        await checkMicrophonePermission()
        checkAccessibilityPermission()

        // Initialize managers
        audioManager = AudioCaptureManager()
        let engine = TranscriptionEngine()
        transcriptionEngine = engine
        overlayController = OverlayWindowController(appState: appState)

        // Set up hotkey manager with callbacks
        // HotkeyManager is now @MainActor, so callbacks run directly on main
        hotkeyManager = HotkeyManager(
            onKeyDown: { [self] in
                Task {
                    await startDictation()
                }
            },
            onKeyUp: { [self] in
                Task {
                    await stopDictation()
                }
            }
        )

        // Start hotkey monitoring if we have permission
        if appState.hasAccessibilityPermission {
            hotkeyManager?.start()
        }

        // Check if model is cached and auto-load if so
        await checkModelStatus(engine: engine)
    }

    private func checkModelStatus(engine: TranscriptionEngine) async {
        // Check if model is cached on disk
        appState.isModelCached = await engine.isModelCached()
        appState.cachedModelInfo = await engine.getCachedModelInfo()

        Log.app.info("Model cached: \(appState.isModelCached)")

        // Auto-load if cached (much faster than downloading)
        if appState.isModelCached {
            Log.app.info("Auto-loading cached model...")
            await loadModel()
        }
    }

    private func checkMicrophonePermission() async {
        appState.hasMicrophonePermission = await AudioCaptureManager.checkPermission()
    }

    private func requestMicrophonePermission() async {
        appState.hasMicrophonePermission = await AudioCaptureManager.requestPermission()
    }

    private func checkAccessibilityPermission() {
        appState.hasAccessibilityPermission = AccessibilityHelper.isAccessibilityEnabled()
        if appState.hasAccessibilityPermission {
            hotkeyManager?.start()
        }
    }

    private func loadModel() async {
        guard let engine = transcriptionEngine else {
            Log.app.error("loadModel: transcriptionEngine is nil")
            return
        }

        Log.transcription.info("Loading model...")
        appState.dictationState = .loadingModel

        do {
            try await engine.loadModel()
            appState.isModelLoaded = true
            appState.isModelCached = true
            appState.cachedModelInfo = await engine.getCachedModelInfo()
            appState.dictationState = .idle
            Log.transcription.info("Model loaded successfully")
        } catch {
            Log.transcription.error("Model loading failed: \(error.localizedDescription)")
            appState.dictationState = .error(error.localizedDescription)
        }
    }

    private func startDictation() async {
        Log.app.info("startDictation() called")

        guard appState.allPermissionsGranted,
              appState.isModelLoaded,
              let audioManager = audioManager else {
            Log.app.warning("startDictation guard failed")
            if !appState.isModelLoaded {
                await loadModel()
            }
            return
        }

        // Reset transcription state
        await transcriptionEngine?.resetState()

        appState.dictationState = .listening
        appState.showOverlay = true
        overlayController?.show()

        // Start audio capture
        do {
            try audioManager.startCapture { levels in
                Task { @MainActor in
                    appState.audioLevels = levels
                }
            }
            Log.audio.info("Recording started")
        } catch {
            Log.audio.error("Audio capture failed: \(error.localizedDescription)")
            appState.dictationState = .error(error.localizedDescription)
        }
    }

    private func stopDictation() async {
        Log.app.info("stopDictation() called")

        guard let audioManager = audioManager,
              let engine = transcriptionEngine else {
            Log.app.warning("stopDictation guard failed")
            return
        }

        // Transition to processing state (overlay stays visible with spinner)
        appState.dictationState = .processing

        // Stop recording
        let recordedAudio = audioManager.stopCapture()
        Log.audio.info("Recording stopped: \(recordedAudio?.count ?? 0) bytes")

        // Transcribe
        if let audioData = recordedAudio, !audioData.isEmpty {
            do {
                let text = try await engine.transcribe(audioData: audioData)
                if !text.isEmpty {
                    Log.injection.info("Injecting: '\(text)'")
                    await textInjector.injectText(text)
                }

                // Record dictation session for WPM tracking
                // Audio is 16kHz, 16-bit (2 bytes per sample) = 32000 bytes per second
                // WAV header is 44 bytes
                let audioBytes = audioData.count - 44
                let audioDurationSeconds = Double(audioBytes) / 32000.0
                let wordCount = text.split(whereSeparator: \.isWhitespace).count

                let session = DictationSession(
                    audioDurationSeconds: audioDurationSeconds,
                    wordCount: wordCount
                )
                modelContext.insert(session)

                do {
                    try modelContext.save()
                    let duration = String(format: "%.1f", audioDurationSeconds)
                    Log.app.info("Recorded session: \(wordCount) words in \(duration)s")
                } catch {
                    Log.app.error("Failed to save session: \(error.localizedDescription)")
                }
            } catch {
                Log.transcription.error("Transcription error: \(error.localizedDescription)")
                appState.dictationState = .error(error.localizedDescription)
                overlayController?.hide()
                appState.showOverlay = false
                return
            }
        }

        // Hide overlay after processing completes
        overlayController?.hide()
        appState.showOverlay = false
        appState.dictationState = .idle
        appState.audioLevels = Array(repeating: 0, count: 14)
    }
}
