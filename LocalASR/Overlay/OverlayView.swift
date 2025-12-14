//
//  OverlayView.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import SwiftUI

/// Main overlay view showing waveform and status
struct OverlayView: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 16) {
            // Microphone icon
            Image(systemName: microphoneIcon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 32)
                .symbolEffect(.pulse, isActive: appState.isListening)

            // Waveform visualizer
            WaveformView(levels: appState.audioLevels)
                .frame(height: 40)

            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.5), radius: 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
    }

    private var microphoneIcon: String {
        switch appState.dictationState {
        case .listening:
            return "mic.fill"
        case .processing:
            return "ellipsis.circle.fill"
        default:
            return "mic"
        }
    }

    private var iconColor: Color {
        switch appState.dictationState {
        case .listening:
            return .red
        case .processing:
            return .blue
        case .error:
            return .orange
        default:
            return .primary
        }
    }

    private var statusColor: Color {
        switch appState.dictationState {
        case .listening:
            return .red
        case .processing:
            return .blue
        case .error:
            return .orange
        default:
            return .green
        }
    }
}

#Preview {
    let state = AppState()
    state.dictationState = .listening
    state.audioLevels = (0..<20).map { _ in Float.random(in: 0...1) }

    return OverlayView(appState: state)
        .frame(width: 280, height: 72)
        .background(.black.opacity(0.5))
}
