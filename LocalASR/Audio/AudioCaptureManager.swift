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

    func clear() {
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }
}

/// Manages audio capture from the microphone with frequency spectrum analysis
/// Records audio until stopped, then returns the complete recording as WAV data
@MainActor
final class AudioCaptureManager {
    private let engine = AVAudioEngine()
    private var isCapturing = false

    // Thread-safe audio buffer
    private let audioBuffer = AudioBuffer()

    // Callback for frequency spectrum visualization
    var onFrequencyLevels: (([Float]) -> Void)?

    // FFT setup
    private let fftSize = 1024
    private var fftSetup: vDSP_DFT_Setup?
    private let frequencyBandCount = 14  // Number of frequency bands to display

    // Target format for Whisper: 16kHz mono
    private let targetSampleRate: Double = 16000

    init() {
        // Create FFT setup
        fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            .FORWARD
        )
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    // MARK: - Permission Handling

    nonisolated static func checkPermission() async -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    nonisolated static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Capture Control

    /// Start recording audio from the microphone
    /// - Parameter onLevels: Callback for real-time frequency spectrum (for visualization)
    func startCapture(onLevels: @escaping ([Float]) -> Void) throws {
        guard !isCapturing else { return }

        onFrequencyLevels = onLevels
        audioBuffer.clear()

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
        let fftSize = self.fftSize
        let bandCount = self.frequencyBandCount

        // Capture setup for FFT
        let setup = self.fftSetup

        // Install tap on input node
        inputNode.installTap(
            onBus: 0,
            bufferSize: UInt32(fftSize),
            format: inputFormat
        ) { [weak self] pcmBuffer, _ in
            guard let self = self else { return }

            // Convert to target format
            let sampleRate = self.targetSampleRate
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

            // Accumulate audio samples for recording
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
            buffer.append(samples)

            // Compute frequency spectrum for visualization
            let spectrum = self.computeFrequencySpectrum(
                samples: samples,
                fftSetup: setup,
                fftSize: fftSize,
                bandCount: bandCount
            )

            // Update UI on main thread
            Task { @MainActor [weak self] in
                self?.onFrequencyLevels?(spectrum)
            }
        }

        engine.prepare()
        try engine.start()
        isCapturing = true

        Log.audio.info("Recording started")
    }

    /// Stop recording and return the complete audio as WAV data
    /// - Returns: WAV-formatted audio data, or nil if no audio was recorded
    func stopCapture() -> Data? {
        guard isCapturing else { return nil }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false

        let samples = audioBuffer.getAndClear()
        let duration = Double(samples.count) / targetSampleRate

        Log.audio.info("Recording stopped: \(samples.count) samples (\(String(format: "%.1f", duration))s)")

        return convertToWavData(samples: samples)
    }

    // MARK: - Frequency Spectrum Analysis

    /// Compute frequency spectrum using FFT
    /// Returns normalized power levels for each frequency band
    private nonisolated func computeFrequencySpectrum(
        samples: [Float],
        fftSetup: vDSP_DFT_Setup?,
        fftSize: Int,
        bandCount: Int
    ) -> [Float] {
        guard let setup = fftSetup, samples.count >= fftSize else {
            return Array(repeating: 0, count: bandCount)
        }

        // Take the last fftSize samples
        let fftSamples = Array(samples.suffix(fftSize))

        // Apply Hann window to reduce spectral leakage
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var windowedSamples = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(fftSamples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))

        // Prepare for FFT (split complex format)
        var realInput = [Float](repeating: 0, count: fftSize)
        var imagInput = [Float](repeating: 0, count: fftSize)
        var realOutput = [Float](repeating: 0, count: fftSize)
        var imagOutput = [Float](repeating: 0, count: fftSize)

        realInput = windowedSamples

        // Perform FFT
        vDSP_DFT_Execute(setup, &realInput, &imagInput, &realOutput, &imagOutput)

        // Compute magnitudes (only need first half due to symmetry)
        let halfSize = fftSize / 2
        var magnitudes = [Float](repeating: 0, count: halfSize)

        for idx in 0..<halfSize {
            let real = realOutput[idx]
            let imag = imagOutput[idx]
            magnitudes[idx] = sqrtf(real * real + imag * imag)
        }

        // Convert to dB and normalize
        var logMagnitudes = [Float](repeating: 0, count: halfSize)
        var one: Float = 1
        vDSP_vdbcon(magnitudes, 1, &one, &logMagnitudes, 1, vDSP_Length(halfSize), 0)

        // Group into frequency bands (logarithmic spacing for perceptual accuracy)
        var bands = [Float](repeating: 0, count: bandCount)

        for band in 0..<bandCount {
            // Logarithmic band edges
            let lowBin = Int(pow(Float(halfSize), Float(band) / Float(bandCount)))
            let highBin = Int(pow(Float(halfSize), Float(band + 1) / Float(bandCount)))
            let clampedLow = max(1, lowBin)
            let clampedHigh = min(halfSize - 1, max(clampedLow + 1, highBin))

            // Average power in this band
            var sum: Float = 0
            for bin in clampedLow..<clampedHigh {
                sum += logMagnitudes[bin]
            }
            bands[band] = sum / Float(clampedHigh - clampedLow)
        }

        // Normalize to 0-1 range
        // Typical dB range for speech: -60 to 0 dB
        let minDb: Float = -60
        let maxDb: Float = 0

        for idx in 0..<bandCount {
            let normalized = (bands[idx] - minDb) / (maxDb - minDb)
            bands[idx] = max(0, min(1, normalized))
        }

        return bands
    }

    // MARK: - WAV Conversion

    private nonisolated func convertToWavData(samples: [Float]) -> Data? {
        guard !samples.isEmpty else { return nil }

        var data = Data()

        // WAV header parameters
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
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
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
