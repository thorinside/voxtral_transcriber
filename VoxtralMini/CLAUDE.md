# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VoxtralMini is a macOS SwiftUI application that captures audio from the microphone and sends it to a local Voxtral transcription service. The app features real-time audio transcription with visual feedback, transcription history with SQLite storage, system tray integration, and configurable server settings.

## Build Commands

### Using Xcode
- Build: `⌘ + B` in Xcode
- Run: `⌘ + R` in Xcode
- Open project: `open VoxtralMini.xcodeproj`

### Using Command Line
```bash
# Build and run using the provided script
./build_and_run.sh

# Manual build using xcodebuild
xcodebuild -project VoxtralMini.xcodeproj -scheme VoxtralMini -configuration Debug build

# Run built app
open build/Debug/VoxtralMini.app
```

## Architecture Overview

### Core Components

**App.swift**: Main application entry point with `VoxtralMiniApp` struct and `AppDelegate` class. Handles window management, system tray integration, and application lifecycle. The AppDelegate manages window restoration and system tray behavior.

**ContentView.swift**: Primary UI containing recording controls, transcription display, and history management. Coordinates between AudioRecorder, VoxtralService, and DatabaseManager. Handles search functionality and transcription chunk display.

**AudioRecorder.swift**: Manages microphone capture using AVAudioEngine and AVAudioRecorder. Provides real-time audio level monitoring and chunk-based audio processing for streaming transcription. Handles microphone permissions and audio session setup.

**VoxtralService.swift**: HTTP client for communicating with the local Voxtral transcription service. Sends WAV audio data via POST requests and handles both JSON and plain text responses.

**DatabaseManager.swift**: SQLite-based persistence layer using SQLite3 C API. Stores transcription history with full-text search capabilities. Singleton pattern with reactive @Published properties.

**SystemTrayManager.swift**: Manages system tray (menu bar) functionality, including status item creation, menu management, and window show/hide behavior. Provides quick access to recording controls from the menu bar.

**SettingsView.swift**: Configuration interface for server URL and connection testing. Includes server connectivity validation.

### Data Flow

1. **Audio Capture**: AudioRecorder captures microphone input and processes it into WAV chunks
2. **Transcription**: VoxtralService sends audio data to configured server endpoint
3. **Storage**: DatabaseManager persists transcriptions with timestamp and searchable text
4. **UI Updates**: SwiftUI views reactively update based on @Published properties from service classes

### Dependencies

- **AVFoundation**: Audio recording and processing
- **SQLite3**: Local database storage (`libsqlite3.tbd` linked in project)
- **AppKit**: macOS-specific UI elements and system tray integration
- **Combine**: Reactive programming with @Published properties

### Server Integration

The app expects a local transcription service running at `http://localhost:8080/transcribe` (configurable). The service should:
- Accept POST requests with `audio/wav` content type
- Return transcriptions in JSON format `{"text": "transcription"}` or plain text
- Handle WAV audio data in request body

### Key Features

- **Real-time audio processing** with chunk-based streaming
- **Visual audio level indicators** during recording
- **Persistent transcription history** with search capabilities
- **System tray integration** for background operation
- **Configurable server endpoints** with connection testing
- **macOS microphone permission handling**