//
//  WaveformView.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import SwiftUI

/// Animated waveform visualization for audio levels
struct WaveformView: View {
    let levels: [Float]

    // Visual configuration
    private let barCount = 20
    private let barSpacing: CGFloat = 3
    private let barWidth: CGFloat = 4
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 40
    private let cornerRadius: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(barGradient)
                        .frame(width: barWidth, height: barHeight(for: index, maxHeight: geometry.size.height))
                        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: levels)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func barHeight(for index: Int, maxHeight: CGFloat) -> CGFloat {
        let level = levels.indices.contains(index) ? CGFloat(levels[index]) : 0
        let height = minHeight + (level * (maxHeight - minHeight))
        return max(minHeight, min(maxHeight, height))
    }

    private var barGradient: LinearGradient {
        LinearGradient(
            colors: [.cyan, .blue],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

/// Alternative waveform style with mirrored bars
struct MirroredWaveformView: View {
    let levels: [Float]

    private let barCount = 20
    private let barSpacing: CGFloat = 2
    private let barWidth: CGFloat = 3
    private let maxHeight: CGFloat = 20

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                VStack(spacing: 1) {
                    // Top bar (mirrored)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.cyan.opacity(0.8))
                        .frame(width: barWidth, height: barHeight(for: index))
                        .animation(.spring(response: 0.12, dampingFraction: 0.5), value: levels)

                    // Bottom bar
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.cyan)
                        .frame(width: barWidth, height: barHeight(for: index))
                        .animation(.spring(response: 0.12, dampingFraction: 0.5), value: levels)
                }
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = levels.indices.contains(index) ? CGFloat(levels[index]) : 0
        return max(2, level * maxHeight)
    }
}

#Preview("Standard Waveform") {
    WaveformView(levels: (0..<20).map { _ in Float.random(in: 0...1) })
        .frame(width: 160, height: 40)
        .padding()
        .background(.black)
}

#Preview("Mirrored Waveform") {
    MirroredWaveformView(levels: (0..<20).map { _ in Float.random(in: 0...1) })
        .frame(width: 160, height: 40)
        .padding()
        .background(.black)
}
