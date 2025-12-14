//
//  PreferencesView.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import SwiftUI

struct PreferencesView: View {
    @Bindable var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView(appState: appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)

            PermissionsPreferencesView(appState: appState)
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
                .tag(1)

            AboutPreferencesView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(2)
        }
        .frame(width: 450, height: 300)
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

            Section {
                HStack {
                    Text("Model")
                    Spacer()
                    if appState.isModelLoaded {
                        Label("distil-large-v3", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Not loaded")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Transcription")
            }
        }
        .formStyle(.grouped)
        .padding()
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
    PreferencesView(appState: AppState())
}
