import Foundation
import AVFoundation
import Combine
import AVFAudio

class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var permissionDenied = false
    @Published var audioData: Data?
    @Published var audioLevel: Float = 0.0
    @Published var audioChunk: Data? // New property for real-time chunks
    @Published var chunkTimestamp: Date? // Timestamp for when the chunk was recorded
    @Published var chunkId: String? // ID of the persisted chunk
    
    private var serverURL = "http://dev.local:9090/transcribe"
    
    func setServerURL(_ url: String) {
        serverURL = url
    }
    
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var chunkTimer: Timer? // New timer for sending chunks
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioBuffer: [Float] = []
    private var chunkBuffer: [Float] = [] // New buffer for chunks
    private var lastChunkSent: [Float] = [] // Keep track of the last chunk for overlap
    private var recordingStartTime: Date?
    private var lastChunkTime: Date?
    private let transcriptionQueue = TranscriptionQueue.shared
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        // On macOS, we don't need AVAudioSession setup - that's iOS-specific
        // Instead, we'll check microphone permission status and request if needed
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            print("Microphone permission already authorized")
            permissionDenied = false
        case .denied, .restricted:
            print("Microphone permission denied or restricted")
            permissionDenied = true
        case .notDetermined:
            print("Microphone permission not determined - will request when needed")
            permissionDenied = false
        @unknown default:
            fatalError("Unknown authorization status")
        }
    }
    
    func requestPermission() {
        print("Requesting microphone permission...")
        // On macOS, we need to use AVCaptureDevice for microphone permissions
        Task {
            let permission = await AVCaptureDevice.requestAccess(for: .audio)
            DispatchQueue.main.async {
                self.permissionDenied = !permission
                if permission {
                    print("Microphone permission granted")
                } else {
                    print("Microphone permission denied")
                }
            }
        }
    }
    
    func checkPermissionStatus() -> Bool {
        // Check current permission status for microphone
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    func startRecording() {
        guard !permissionDenied else {
            print("Cannot start recording: permission denied")
            return
        }
        
        // Clear buffers and reset timing
        audioBuffer.removeAll()
        chunkBuffer.removeAll()
        lastChunkSent.removeAll()
        recordingStartTime = Date()
        lastChunkTime = recordingStartTime
        
        // Stop any existing engine
        audioEngine?.stop()
        audioEngine = nil
        
        // Check if we have permission by trying to access the input node
        audioEngine = AVAudioEngine()
        
        // Add a small delay to ensure the engine is properly initialized
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setupAudioInput()
        }
    }
    
    private func setupAudioInput() {
        guard let engine = audioEngine else {
            print("Audio engine is nil")
            return
        }
        
        inputNode = engine.inputNode
        
        // Try to get the input format - this will fail if we don't have permission
        guard let format = inputNode?.outputFormat(forBus: 0) else {
            print("Failed to get audio input format - permission may be denied")
            DispatchQueue.main.async {
                self.permissionDenied = true
            }
            return
        }
        
        print("Audio format: \(format)")
        
        // Set up the audio tap with a smaller buffer size for better performance
        inputNode?.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try engine.start()
            print("Audio engine started successfully")
            DispatchQueue.main.async {
                self.isRecording = true
                self.startLevelTimer()
                self.startChunkTimer() // Start the chunk timer
            }
        } catch {
            print("Failed to start audio engine: \(error)")
            if error.localizedDescription.contains("permission") || error.localizedDescription.contains("-10877") {
                print("Permission error (-10877) detected, attempting to recover...")
                handlePermissionError()
            } else {
                DispatchQueue.main.async {
                    self.permissionDenied = true
                }
            }
        }
    }
    
    private func handlePermissionError() {
        // Stop the current engine
        audioEngine?.stop()
        audioEngine = nil
        
        // Request permission again
        requestPermission()
        
        // Retry after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if !self.permissionDenied {
                print("Retrying audio engine setup...")
                self.startRecording()
            }
        }
    }
    
    func stopRecording() {
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.stopLevelTimer()
            self.stopChunkTimer() // Stop the chunk timer
            self.audioLevel = 0.0
        }
        
        // Send any remaining chunk data before stopping
        if !chunkBuffer.isEmpty {
            sendFinalAudioChunk()
        }
        
        // Convert buffer to audio data and send
        if !audioBuffer.isEmpty {
            audioData = convertFloatBufferToWAV(audioBuffer)
            audioBuffer.removeAll()
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        
        // Calculate audio level for visualization
        var sum: Float = 0.0
        for channel in 0..<channelCount {
            let data = channelData[channel]
            for i in 0..<frameCount {
                sum += abs(data[i])
                audioBuffer.append(data[i])
                chunkBuffer.append(data[i])
            }
        }
        
        let averageLevel = sum / Float(frameCount * channelCount)
        DispatchQueue.main.async {
            self.audioLevel = min(averageLevel * 10, 1.0) // Scale for visualization
        }
    }
    
    private func convertFloatBufferToWAV(_ buffer: [Float]) -> Data {
        // Convert Float audio buffer to WAV format
        let sampleRate: Double = 44100.0
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = channels * UInt16(bitsPerSample / 8)
        
        var wavData = Data()
        
        // WAV Header
        wavData.append("RIFF".data(using: .ascii)!)
        let fileSize: UInt32 = 36 + UInt32(buffer.count * 2)
        wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // Subchunk1Size
        wavData.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // AudioFormat (PCM)
        wavData.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        let dataSize: UInt32 = UInt32(buffer.count * 2)
        wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        
        // Audio data (convert Float to Int16)
        for sample in buffer {
            let intSample = Int16(max(-1, min(1, sample)) * Float(Int16.max))
            wavData.append(withUnsafeBytes(of: intSample.littleEndian) { Data($0) })
        }
        
        return wavData
    }
    
    private func startLevelTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Timer for periodic updates if needed
        }
    }
    
    private func stopLevelTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func startChunkTimer() {
        // Send audio chunks every 10 seconds
        chunkTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.sendAudioChunk()
        }
    }
    
    private func stopChunkTimer() {
        chunkTimer?.invalidate()
        chunkTimer = nil
    }
    
    private func sendAudioChunk() {
        guard !chunkBuffer.isEmpty else { return }
        
        print("Sending audio chunk with \(chunkBuffer.count) samples")
        
        // Calculate timestamp for this chunk (when recording of this chunk started)
        let chunkTimestamp = lastChunkTime ?? Date()
        
        // Create overlapping chunk by including the end of the previous chunk
        var overlappingChunk = chunkBuffer
        
        // Add overlap from previous chunk (about 1 second of audio)
        let overlapSamples = Int(44100 * 1.0) // 1 second at 44.1kHz
        if !lastChunkSent.isEmpty && lastChunkSent.count > overlapSamples {
            let overlap = Array(lastChunkSent.suffix(overlapSamples))
            overlappingChunk.insert(contentsOf: overlap, at: 0)
            print("Added \(overlap.count) overlap samples, total chunk size: \(overlappingChunk.count)")
        }
        
        // Convert chunk buffer to WAV data
        let wavData = convertFloatBufferToWAV(overlappingChunk)
        
        // Store current chunk as last chunk for next overlap
        lastChunkSent = chunkBuffer
        
        // Update last chunk time for next chunk
        lastChunkTime = Date()
        
        // Calculate estimated duration in seconds
        let estimatedDuration = Double(overlappingChunk.count) / 44100.0
        
        // Enqueue chunk for persistent storage and transcription
        transcriptionQueue.enqueueChunk(
            audioData: wavData,
            timestamp: chunkTimestamp,
            serverURL: serverURL,
            estimatedDuration: estimatedDuration
        )
        
        // Note: We only use the persistent transcription queue now
        // The old audioChunk publishing is removed to avoid dual transcription
        
        // Clear the chunk buffer
        chunkBuffer.removeAll()
    }
    
    private func sendFinalAudioChunk() {
        guard !chunkBuffer.isEmpty else { return }
        
        print("Sending final audio chunk with \(chunkBuffer.count) samples")
        
        // Calculate timestamp for the final chunk (when recording of this chunk started)
        let finalChunkTimestamp = lastChunkTime ?? Date()
        
        // For the final chunk, we don't need overlap processing as this is the end
        // Convert chunk buffer to WAV data
        let wavData = convertFloatBufferToWAV(chunkBuffer)
        
        // Calculate estimated duration in seconds
        let estimatedDuration = Double(chunkBuffer.count) / 44100.0
        
        // Enqueue final chunk for persistent storage and transcription
        transcriptionQueue.enqueueChunk(
            audioData: wavData,
            timestamp: finalChunkTimestamp,
            serverURL: serverURL,
            estimatedDuration: estimatedDuration
        )
        
        // Publish the final chunk with proper timestamp (for backward compatibility)
        DispatchQueue.main.async {
            self.audioChunk = wavData
            self.chunkTimestamp = finalChunkTimestamp
        }
        
        // Clear the chunk buffer
        chunkBuffer.removeAll()
    }
}
