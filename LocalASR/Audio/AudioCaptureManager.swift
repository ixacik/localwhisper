//
//  AudioCaptureManager.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import AVFoundation
import Accelerate

/// Thread-safe audio buffer for accumulating samples
final class AudioBuffer: @unchecked Sendable {
    private var samples: [Float] = []
    private let lock = NSLock()

    func append(_ newSamples: [Float]) {
        lock.lock()
        samples.append(contentsOf: newSamples)
        lock.unlock()
    }

    func getAndClear() -> [Float] {
        lock.lock()
        let result = samples
        samples.removeAll()
        lock.unlock()
        return result
    }

    func getAndKeepOverlap(overlapCount: Int) -> [Float] {
        lock.lock()
        let result = samples
        if samples.count > overlapCount {
            samples = Array(samples.suffix(overlapCount))
        }
        lock.unlock()
        return result
    }

    func clear() {
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }
}

/// Manages audio capture from the microphone with level monitoring
/// Provides audio data chunks for transcription
@MainActor
final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var isCapturing = false

    // Thread-safe audio buffer
    private let audioBuffer = AudioBuffer()

    // Chunk settings for streaming transcription
    private let chunkDuration: TimeInterval = 2.0  // Send chunks every 2 seconds
    private var lastChunkTime: Date?

    // Callbacks
    var onAudioLevels: (([Float]) -> Void)?
    var onAudioChunk: ((Data) -> Void)?

    // Level history for visualization
    private var levelHistory: [Float] = Array(repeating: 0, count: 20)

    // Target format for Whisper: 16kHz mono
    private let targetSampleRate: Double = 16000

    init() {}

    // MARK: - Permission Handling

    static func checkPermission() async -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Capture Control

    func startCapture(onLevels: @escaping ([Float]) -> Void) throws {
        guard !isCapturing else { return }

        onAudioLevels = onLevels

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create converter to target format (16kHz mono)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.formatConversionFailed
        }

        let buffer = self.audioBuffer
        let sampleRate = self.targetSampleRate
        let chunkDuration = self.chunkDuration

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] pcmBuffer, _ in
            // Convert to target format
            let frameCount = AVAudioFrameCount(
                Double(pcmBuffer.frameLength) * sampleRate / inputFormat.sampleRate
            )

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return pcmBuffer
            }

            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

            if error != nil { return }

            guard let channelData = convertedBuffer.floatChannelData?[0] else { return }
            let frameLength = Int(convertedBuffer.frameLength)

            // Calculate RMS level for visualization
            var rmsValue: Float = 0
            vDSP_rmsqv(channelData, 1, &rmsValue, vDSP_Length(frameLength))
            let scaledLevel = min(rmsValue * 10, 1.0)

            // Accumulate audio samples
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
            buffer.append(samples)

            // Update UI on main thread
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Update level history
                self.levelHistory.removeFirst()
                self.levelHistory.append(scaledLevel)
                self.onAudioLevels?(self.levelHistory)

                // Check if we should send a chunk
                if let lastTime = self.lastChunkTime,
                   Date().timeIntervalSince(lastTime) >= chunkDuration {
                    self.sendAudioChunk()
                }
            }
        }

        engine.prepare()
        try engine.start()

        isCapturing = true
        lastChunkTime = Date()
        audioBuffer.clear()

        print("Audio capture started")
    }

    func stopCapture() -> Data? {
        guard isCapturing else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false

        // Return any remaining audio
        let finalAudio = audioBuffer.getAndClear()

        print("Audio capture stopped, \(finalAudio.count) samples remaining")

        return convertToWavData(samples: finalAudio)
    }

    // MARK: - Audio Processing

    private func sendAudioChunk() {
        let overlapSamples = Int(targetSampleRate * 0.5)
        let chunkSamples = audioBuffer.getAndKeepOverlap(overlapCount: overlapSamples)

        lastChunkTime = Date()

        if let wavData = convertToWavData(samples: chunkSamples) {
            onAudioChunk?(wavData)
        }
    }

    // MARK: - WAV Conversion

    private nonisolated func convertToWavData(samples: [Float]) -> Data? {
        guard !samples.isEmpty else { return nil }

        // Create WAV file in memory
        var data = Data()

        // WAV header
        let sampleRate = UInt32(16000)
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)  // 16-bit samples
        let fileSize = 36 + dataSize

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // PCM format
        data.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Convert float samples to 16-bit PCM
        for sample in samples {
            let clampedSample = max(-1.0, min(1.0, sample))
            let intSample = Int16(clampedSample * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: intSample.littleEndian) { Array($0) })
        }

        return data
    }
}

// MARK: - Errors

enum AudioCaptureError: Error, LocalizedError {
    case formatConversionFailed
    case engineStartFailed

    var errorDescription: String? {
        switch self {
        case .formatConversionFailed:
            return "Failed to create audio format converter"
        case .engineStartFailed:
            return "Failed to start audio engine"
        }
    }
}
