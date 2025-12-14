//
//  PreferencesView.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import SwiftUI
import SwiftData

struct PreferencesView: View {
    @Bindable var appState: AppState
    @Binding var transcriptionEngine: TranscriptionEngine?
    @Query private var sessions: [DictationSession]
    @State private var selectedTab = 0

    private var totalSeconds: Double {
        sessions.reduce(0) { $0 + $1.audioDurationSeconds }
    }

    private var totalWords: Int {
        sessions.reduce(0) { $0 + $1.wordCount }
    }

    private var averageWPM: Double {
        guard totalSeconds > 0 else { return 0 }
        return (Double(totalWords) / totalSeconds) * 60
    }

    private var formattedDuration: String {
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Stats header
            StatsHeaderView(
                averageWPM: averageWPM,
                formattedDuration: formattedDuration,
                hasData: !sessions.isEmpty
            )

            Divider()

            TabView(selection: $selectedTab) {
                GeneralPreferencesView(appState: appState)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
                    .tag(0)

                ModelPreferencesView(appState: appState, transcriptionEngine: $transcriptionEngine)
                    .tabItem {
                        Label("Model", systemImage: "cpu")
                    }
                    .tag(1)

                PermissionsPreferencesView(appState: appState)
                    .tabItem {
                        Label("Permissions", systemImage: "lock.shield")
                    }
                    .tag(2)

                AboutPreferencesView()
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
                    .tag(3)
            }
        }
        .frame(width: 480, height: 400)
    }
}

// MARK: - Stats Header

struct StatsHeaderView: View {
    let averageWPM: Double
    let formattedDuration: String
    let hasData: Bool

    var body: some View {
        VStack(spacing: 4) {
            if hasData {
                Text("\(Int(averageWPM)) WPM")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Text("Based on \(formattedDuration) of dictation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No Data Yet")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("Start dictating to track your WPM")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
    }
}

// MARK: - General Preferences

struct GeneralPreferencesView: View {
    @Bindable var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("playSound") private var playSound = true

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Toggle("Play sound when dictation starts/stops", isOn: $playSound)
            } header: {
                Text("Startup")
            }

            Section {
                HStack {
                    Text("Push-to-Talk Hotkey")
                    Spacer()
                    Text("⌘ Escape")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.quaternary)
                        )
                }
            } header: {
                Text("Hotkey")
            } footer: {
                Text("Hold the hotkey to start dictation, release to stop.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Model Preferences

struct ModelPreferencesView: View {
    @Bindable var appState: AppState
    @Binding var transcriptionEngine: TranscriptionEngine?
    @State private var isDeleting = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section {
                // Model status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Status")
                            .fontWeight(.medium)
                        Text(statusDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    statusBadge
                }

                // Model info (if cached)
                if let info = appState.cachedModelInfo {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Model")
                                .fontWeight(.medium)
                            Text(info.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(info.formattedSize)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("WhisperKit Model")
            }

            Section {
                if appState.isModelCached || appState.isModelLoaded {
                    // Delete model button
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Delete Model")
                                .fontWeight(.medium)
                            Text("Remove cached model to free up disk space")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if isDeleting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Delete", role: .destructive) {
                                showDeleteConfirmation = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                } else {
                    // Download model button
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Download Model")
                                .fontWeight(.medium)
                            Text("Download the WhisperKit model (~1.5 GB)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if appState.isLoadingModel {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Download") {
                                Task { await downloadModel() }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Models are stored in ~/Library/Application Support/WhisperKit/")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog(
            "Delete Model?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteModel() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove the cached model from disk. You'll need to download it again to use LocalASR.")
        }
    }

    private var statusDescription: String {
        if appState.isModelLoaded {
            return "Model is loaded and ready"
        } else if appState.isModelCached {
            return "Model is cached but not loaded"
        } else {
            return "Model not downloaded"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if appState.isModelLoaded {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        } else if appState.isModelCached {
            Label("Cached", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
                .font(.caption)
        } else {
            Label("Not Downloaded", systemImage: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func downloadModel() async {
        guard let engine = transcriptionEngine else { return }

        appState.dictationState = .loadingModel

        do {
            try await engine.loadModel()
            appState.isModelLoaded = true
            appState.isModelCached = true
            appState.cachedModelInfo = await engine.getCachedModelInfo()
            appState.dictationState = .idle
        } catch {
            appState.dictationState = .error(error.localizedDescription)
        }
    }

    private func deleteModel() async {
        guard let engine = transcriptionEngine else { return }

        isDeleting = true

        do {
            try await engine.deleteModelCache()
            appState.isModelLoaded = false
            appState.isModelCached = false
            appState.cachedModelInfo = nil
            appState.dictationState = .idle
        } catch {
            appState.dictationState = .error(error.localizedDescription)
        }

        isDeleting = false
    }
}

// MARK: - Permissions Preferences

struct PermissionsPreferencesView: View {
    @Bindable var appState: AppState
    @State private var permissionTimer: Timer?

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Microphone",
                    description: "Required to capture speech for transcription",
                    isGranted: appState.hasMicrophonePermission,
                    action: {
                        Task {
                            appState.hasMicrophonePermission = await AudioCaptureManager.requestPermission()
                        }
                    }
                )

                PermissionRow(
                    title: "Accessibility",
                    description: "Required for global hotkey and text injection",
                    isGranted: appState.hasAccessibilityPermission,
                    action: {
                        AccessibilityHelper.requestPermission()
                        AccessibilityHelper.openAccessibilityPreferences()
                    }
                )
            } header: {
                Text("Required Permissions")
            } footer: {
                Text("LocalASR needs these permissions to function. All processing happens on-device.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            startPermissionMonitoring()
        }
        .onDisappear {
            permissionTimer?.invalidate()
        }
    }

    private func startPermissionMonitoring() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                appState.hasAccessibilityPermission = AccessibilityHelper.isAccessibilityEnabled()
                appState.hasMicrophonePermission = await AudioCaptureManager.checkPermission()
            }
        }
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - About Preferences

struct AboutPreferencesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            VStack(spacing: 4) {
                Text("LocalASR")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Version 1.0")
                    .foregroundStyle(.secondary)
            }

            Text("On-device speech recognition powered by WhisperKit")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            VStack(spacing: 8) {
                Link("WhisperKit by Argmax", destination: URL(string: "https://github.com/argmaxinc/WhisperKit")!)
                Link("Whisper by OpenAI", destination: URL(string: "https://github.com/openai/whisper")!)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    @Previewable @State var engine: TranscriptionEngine? = TranscriptionEngine()
    PreferencesView(appState: AppState(), transcriptionEngine: $engine)
        .modelContainer(for: DictationSession.self, inMemory: true)
}
