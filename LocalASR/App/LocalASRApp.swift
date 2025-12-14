//
//  LocalASRApp.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import SwiftUI

@main
struct LocalASRApp: App {
    @State private var appState = AppState()
    @State private var hotkeyManager: HotkeyManager?
    @State private var audioManager: AudioCaptureManager?
    @State private var transcriptionEngine: TranscriptionEngine?
    @State private var textInjector = TextInjector()
    @State private var overlayController: OverlayWindowController?

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Label("LocalASR", systemImage: appState.isListening ? "waveform.circle.fill" : "waveform")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView(appState: appState)
        }
    }

    init() {
        // Initialization happens in onAppear of MenuBarView
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @Bindable var appState: AppState
    @State private var hotkeyManager: HotkeyManager?
    @State private var audioManager: AudioCaptureManager?
    @State private var transcriptionEngine: TranscriptionEngine?
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
                        checkAccessibilityPermission()
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
                    if case .downloading(let progress) = appState.dictationState {
                        HStack {
                            ProgressView(value: progress)
                            Text("\(Int(progress * 100))%")
                        }
                    } else {
                        Button("Download Model (~1.5 GB)") {
                            Task { await downloadModel() }
                        }
                    }
                }

                Divider()
            }

            // Settings
            SettingsLink {
                Text("Preferences...")
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
        case .downloading:
            return .yellow
        case .error:
            return .red
        default:
            return .gray
        }
    }

    private func initializeApp() async {
        // Check permissions
        await checkMicrophonePermission()
        checkAccessibilityPermission()

        // Initialize managers
        audioManager = AudioCaptureManager()
        transcriptionEngine = TranscriptionEngine()
        overlayController = OverlayWindowController(appState: appState)

        // Set up hotkey manager with callbacks
        hotkeyManager = HotkeyManager(
            onKeyDown: { [self] in
                Task { @MainActor in
                    await startDictation()
                }
            },
            onKeyUp: { [self] in
                Task { @MainActor in
                    await stopDictation()
                }
            }
        )

        // Start hotkey monitoring if we have permission
        if appState.hasAccessibilityPermission {
            hotkeyManager?.start()
        }

        // Check if model is already downloaded
        if let engine = transcriptionEngine {
            appState.isModelLoaded = await engine.isModelAvailable()
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

    private func downloadModel() async {
        guard let engine = transcriptionEngine else { return }

        appState.dictationState = .downloading(progress: 0)

        do {
            try await engine.loadModel { progress in
                Task { @MainActor in
                    appState.dictationState = .downloading(progress: progress)
                    appState.modelDownloadProgress = progress
                }
            }
            appState.isModelLoaded = true
            appState.dictationState = .idle
        } catch {
            appState.dictationState = .error(error.localizedDescription)
        }
    }

    private func startDictation() async {
        guard appState.allPermissionsGranted,
              appState.isModelLoaded,
              let audioManager = audioManager,
              let engine = transcriptionEngine else {
            // If model not loaded, try to load it
            if !appState.isModelLoaded {
                await downloadModel()
            }
            return
        }

        appState.dictationState = .listening
        appState.showOverlay = true
        overlayController?.show()

        // Start audio capture with level monitoring
        do {
            try audioManager.startCapture { levels in
                Task { @MainActor in
                    appState.audioLevels = levels
                }
            }
        } catch {
            appState.dictationState = .error(error.localizedDescription)
            return
        }

        // Start streaming transcription
        audioManager.onAudioChunk = { audioData in
            Task {
                do {
                    let text = try await engine.transcribe(audioData: audioData)
                    if !text.isEmpty {
                        await MainActor.run {
                            textInjector.typeText(text)
                        }
                    }
                } catch {
                    await MainActor.run {
                        appState.dictationState = .error(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func stopDictation() async {
        guard let audioManager = audioManager,
              let engine = transcriptionEngine else { return }

        appState.dictationState = .processing

        // Stop audio capture and get final audio
        let finalAudio = audioManager.stopCapture()

        // Transcribe final chunk
        if let audioData = finalAudio, !audioData.isEmpty {
            do {
                let text = try await engine.transcribe(audioData: audioData)
                if !text.isEmpty {
                    textInjector.typeText(text)
                }
            } catch {
                appState.dictationState = .error(error.localizedDescription)
            }
        }

        appState.dictationState = .idle
        appState.showOverlay = false
        appState.audioLevels = Array(repeating: 0, count: 20)
        overlayController?.hide()
    }
}
