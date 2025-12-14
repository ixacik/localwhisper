# LocalASR - Development Notes

## CI Commands (run after EVERY change)

```bash
# Build check - catches all compiler errors
xcodebuild | xcbeautify -q

# Lint check - catches style/pattern issues
swiftlint --quiet
```

## Project Overview

On-device speech recognition dictation app for macOS using WhisperKit.

- **Menu bar app** - No dock icon, lives in menu bar
- **Push-to-talk** - Hold ⌘+Escape to dictate
- **WhisperKit** - Uses distil-large-v3 model for fast on-device transcription
- **Text injection** - Types directly into any focused text field

## Key Files

- `LocalASR/App/LocalASRApp.swift` - Main entry point, MenuBarExtra
- `LocalASR/App/AppState.swift` - Observable app state
- `LocalASR/Hotkey/HotkeyManager.swift` - CGEvent tap for global hotkey
- `LocalASR/Audio/AudioCaptureManager.swift` - AVAudioEngine mic capture
- `LocalASR/Transcription/TranscriptionEngine.swift` - WhisperKit wrapper
- `LocalASR/Transcription/TextInjector.swift` - CGEvent keyboard simulation
- `LocalASR/Overlay/` - Floating overlay window with waveform

## Dependencies

- WhisperKit (SPM) - https://github.com/argmaxinc/WhisperKit

## Permissions Required

- Microphone (`com.apple.security.device.audio-input`)
- Accessibility (runtime via `AXIsProcessTrusted()`)
- Network for model download (`com.apple.security.network.client`)

