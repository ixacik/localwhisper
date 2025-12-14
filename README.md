# LocalASR

**On-device speech recognition for macOS** — A private, local dictation app powered by WhisperKit.

No cloud services. No subscriptions. Just hold ⌘+Escape and speak.

## Features

- **100% On-Device**: All speech processing happens locally using Apple Silicon Neural Engine
- **Push-to-Talk**: Hold ⌘+Escape to dictate, release to stop
- **System-Wide**: Types directly into any focused text field
- **Privacy-First**: Your audio never leaves your device
- **Fast**: Uses distil-large-v3 for near real-time transcription

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon Mac (M1/M2/M3/M4)
- ~1.5 GB disk space for the model

## Installation

1. Clone the repository
2. Open `LocalASR.xcodeproj` in Xcode
3. Build and run (⌘R)
4. Grant permissions when prompted:
   - **Microphone**: Required for speech capture
   - **Accessibility**: Required for global hotkey and text injection

## First Run

1. Click the waveform icon in the menu bar
2. Grant Microphone permission
3. Grant Accessibility permission (opens System Settings)
4. Click "Download Model" (~1.5 GB, one-time)
5. Ready! Hold ⌘+Escape to dictate

## Usage

1. Focus any text field (Notes, Safari, VS Code, Slack, etc.)
2. **Hold** ⌘+Escape
3. Speak clearly
4. **Release** ⌘+Escape
5. Text appears in the focused field

## Architecture

```
LocalASR/
├── App/
│   ├── LocalASRApp.swift       # Menu bar app entry point
│   └── AppState.swift          # Observable app state
├── Hotkey/
│   ├── HotkeyManager.swift     # CGEvent tap for global hotkey
│   └── AccessibilityHelper.swift
├── Audio/
│   └── AudioCaptureManager.swift   # AVAudioEngine capture
├── Transcription/
│   ├── TranscriptionEngine.swift   # WhisperKit wrapper
│   └── TextInjector.swift          # CGEvent keyboard simulation
├── Overlay/
│   ├── OverlayWindow.swift     # Floating NSPanel
│   ├── OverlayView.swift       # SwiftUI overlay content
│   └── WaveformView.swift      # Audio visualizer
└── Preferences/
    └── PreferencesView.swift   # Settings UI
```

## Model

Uses **distil-large-v3** from Hugging Face via WhisperKit:
- 756M parameters
- ~6x real-time on M4 Pro
- 97% of Whisper large-v3 accuracy
- English-optimized

## Privacy

- **No network required** after model download
- **No telemetry** or analytics
- **No cloud processing** — everything runs on your Mac
- Audio is processed in memory and never saved to disk

## Credits

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax
- [Whisper](https://github.com/openai/whisper) by OpenAI
- [distil-whisper](https://github.com/huggingface/distil-whisper) by Hugging Face

## License

MIT License

