//
//  Logging.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import Foundation
import os

/// Unified logging for LocalASR
/// View logs in Console.app by filtering for "com.plevo.LocalASR"
/// Note: Logger is Sendable, so these can be used from any actor context
nonisolated
enum Log: Sendable {
    private nonisolated static let subsystem = "com.plevo.LocalASR"

    /// Transcription-related logs (model loading, transcription results)
    nonisolated static let transcription = Logger(subsystem: subsystem, category: "transcription")

    /// Audio capture logs (mic input, chunks, levels)
    nonisolated static let audio = Logger(subsystem: subsystem, category: "audio")

    /// Hotkey detection logs
    nonisolated static let hotkey = Logger(subsystem: subsystem, category: "hotkey")

    /// Text injection logs
    nonisolated static let injection = Logger(subsystem: subsystem, category: "injection")

    /// App lifecycle and state logs
    nonisolated static let app = Logger(subsystem: subsystem, category: "app")
}
