//
//  OverlayView.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import SwiftUI

/// Ultra-minimal overlay that morphs between listening (dots) and processing (linear loader)
/// Uses fixed dimensions to prevent size changes during state transitions
struct OverlayView: View {
    @Bindable var appState: AppState

    private let dotCount = 5
    private let contentWidth: CGFloat = 50
    private let contentHeight: CGFloat = 6

    private var isProcessing: Bool {
        appState.dictationState == .processing
    }

    var body: some View {
            ZStack {
                // Listening state: 5 audio-reactive dots
                if !isProcessing {
                    listeningContent
                        .transition(.opacity)
                }
                
                // Processing state: linear loader
                if isProcessing {
                    processingContent
                        .transition(.opacity)
                }
            }
            .frame(width: contentWidth, height: contentHeight)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thinMaterial)
            }
            .animation(.easeInOut(duration: 0.2), value: isProcessing)
    }

    // MARK: - Listening Content (5 dots)

    private var listeningContent: some View {
        HStack(spacing: 5) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(dotOpacity(for: index)))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Processing Content (linear loader)

    private var processingContent: some View {
        ProgressView()
            .progressViewStyle(.linear)
            .controlSize(.mini)
            .tint(.white)
    }

    // MARK: - Helpers

    private func dotOpacity(for index: Int) -> Double {
        let level: Float
        if appState.audioLevels.indices.contains(index) {
            level = appState.audioLevels[index]
        } else {
            level = 0
        }
        // Map level to opacity: 0.2 (silent) to 1.0 (loud)
        return 0.2 + Double(level) * 0.8
    }
}

// MARK: - Previews

#Preview("Listening") {
    let state = AppState()
    state.dictationState = .listening
    state.audioLevels = [0.2, 0.5, 0.8, 0.6, 0.3]

    return OverlayView(appState: state)
        .padding(40)
        .background(.gray)
}

#Preview("Processing") {
    let state = AppState()
    state.dictationState = .processing

    return OverlayView(appState: state)
        .padding(40)
        .background(.gray)
}
