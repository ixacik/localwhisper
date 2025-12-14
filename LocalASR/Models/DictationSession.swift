//
//  DictationSession.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import Foundation
import SwiftData

/// Represents a single dictation session for WPM tracking
@Model
final class DictationSession {
    var date: Date
    var audioDurationSeconds: Double
    var wordCount: Int

    /// Calculated words per minute for this session
    var wordsPerMinute: Double {
        guard audioDurationSeconds > 0 else { return 0 }
        return (Double(wordCount) / audioDurationSeconds) * 60
    }

    init(date: Date = .now, audioDurationSeconds: Double, wordCount: Int) {
        self.date = date
        self.audioDurationSeconds = audioDurationSeconds
        self.wordCount = wordCount
    }
}
