# Voxtral Mini - Transcription Service for macOS

A simple macOS application that captures audio from your microphone and sends it to a Voxtral transcription service running locally.

## Features

- **Real-time Audio Transcription**: Captures audio from your macOS microphone and sends it to a local Voxtral transcription service
- **Visual Audio Level Indicators**: Shows real-time microphone activity and recording status
- **Transcription History**: SQLite-based storage with full-text search capabilities
- **System Tray Integration**: Operates from the menu bar with quick access to recording controls
- **Configurable Server Settings**: Easy server URL configuration with connection testing
- **Chunk-based Audio Processing**: Streams audio in chunks for continuous transcription
- **Privacy-focused**: All processing happens locally on your machine

## Requirements

- macOS 10.15 or later
- Xcode 12.0 or later
- Local Voxtral service running (via lmstudio)

## Setup Instructions

### 1. Open the Project

1. Navigate to the project directory:
   ```bash
   cd VoxtralMini
   ```

2. Open the project in Xcode:
   ```bash
   open VoxtralMini.xcodeproj
   ```

### 2. Configure Signing

1. In Xcode, select the "VoxtralMini" target
2. Go to the "Signing & Capabilities" tab
3. Choose your Team/Apple ID for code signing
4. The app should automatically use "Automatic" signing

### 3. Grant Microphone Permission

The app includes the necessary entitlements for microphone access. On first run, macOS will prompt you to grant microphone permission.

### 4. Configure Server URL

By default, the app expects your Voxtral service to be running at:
```
http://localhost:8080/transcribe
```

You can change this in the app's interface if your service is running on a different port or URL.

## Building and Running

### Using Xcode:

1. Build the project: `⌘ + B`
2. Run the app: `⌘ + R`

### Using Command Line:

```bash
# Build and run using the provided script
./build_and_run.sh

# Manual build using xcodebuild
xcodebuild -project VoxtralMini.xcodeproj -scheme VoxtralMini -configuration Debug build

# Run the built app
open build/Debug/VoxtralMini.app
```

## Server Setup

Your local Voxtral service should:

1. Accept POST requests with WAV audio data
2. Return transcriptions in either:
   - JSON format: `{"text": "transcription here"}`
   - Plain text format

Example server endpoint structure:
```
POST /transcribe
Content-Type: audio/wav
Accept: application/json or text/plain

[Binary WAV audio data]
```

## Usage

1. **Launch the App**: Start VoxtralMini from your Applications folder or directly from Xcode
2. **Grant Permission**: Allow microphone access when prompted
3. **Configure Server**: Verify or update the server URL in Settings if needed
4. **System Tray Operation**: The app can operate from the menu bar for background transcription
5. **Start Recording**: Click the "Start Recording" button or use the system tray controls
6. **Speak**: The microphone indicator will show real-time audio levels during recording
7. **Stop Recording**: Click "Stop Recording" when finished
8. **View Transcription**: The transcribed text will appear in the main view and be saved to history
9. **Search History**: Use the search functionality to find previous transcriptions

## Troubleshooting

### Microphone Permission Denied

If you accidentally denied microphone permission:
1. Go to `System Preferences > Security & Privacy > Privacy`
2. Select `Microphone` from the left sidebar
3. Find `VoxtralMini` and enable the checkbox

### Server Connection Issues

If the app can't connect to your Voxtral service:
1. Verify your Voxtral service is running
2. Check the server URL in the app
3. Ensure the server accepts POST requests with WAV audio data
4. Check firewall settings

### Audio Processing Issues

If transcription quality is poor:
1. Ensure you're speaking clearly and at a moderate volume
2. Check your microphone input levels in System Preferences
3. Move closer to the microphone if needed
4. Reduce background noise

## Code Structure

- `App.swift`: Main application entry point with `VoxtralMiniApp` struct and `AppDelegate` class
- `ContentView.swift`: Primary UI with recording controls, transcription display, and history management
- `AudioRecorder.swift`: Handles microphone capture using AVAudioEngine with real-time audio level monitoring
- `VoxtralService.swift`: HTTP client for communicating with the local Voxtral transcription service
- `DatabaseManager.swift`: SQLite-based persistence layer with full-text search capabilities
- `SystemTrayManager.swift`: Manages system tray (menu bar) functionality and window management
- `SettingsView.swift`: Configuration interface for server URL and connection testing

## Privacy

This application is designed with privacy in mind:
- All audio processing happens locally on your machine
- Audio data is only sent to your local Voxtral service
- No data is sent to external servers or cloud services
- No telemetry or analytics are collected

## License

This project is open source and available under the MIT License.
