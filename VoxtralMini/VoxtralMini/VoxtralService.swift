import Foundation
import Combine

class VoxtralService: ObservableObject {
    @Published var statusMessage = ""
    @Published var isTranscribing = false
    
    private var cancellables = Set<AnyCancellable>()
    
    // Retry configuration
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0 // Base delay in seconds
    private let maxRetryDelay: TimeInterval = 10.0 // Maximum delay in seconds
    
    func transcribe(audioData: Data, serverURL: String) async throws -> String {
        guard !serverURL.isEmpty else {
            throw TranscriptionError.invalidURL
        }
        
        guard let url = URL(string: serverURL) else {
            throw TranscriptionError.invalidURL
        }
        
        print("Attempting to connect to: \(url)")
        print("Audio data size: \(audioData.count) bytes")
        
        DispatchQueue.main.async {
            self.isTranscribing = true
            self.statusMessage = "Sending audio to transcription service..."
        }
        
        defer {
            DispatchQueue.main.async {
                self.isTranscribing = false
                self.statusMessage = ""
            }
        }
        
        // Retry logic with exponential backoff
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                let result = try await performTranscriptionRequest(audioData: audioData, url: url)
                
                // Success! Update status and return result
                DispatchQueue.main.async {
                    self.statusMessage = "Transcription completed successfully"
                }
                return result
                
            } catch let error as TranscriptionError {
                lastError = error
                print("Transcription attempt \(attempt + 1) failed: \(error.localizedDescription)")
                
                // Don't retry client errors (4xx) as they are unlikely to succeed
                if case .clientError = error {
                    print("Client error - not retrying")
                    break
                }
                
                // If this is our last attempt, don't wait
                if attempt < maxRetries {
                    let delay = calculateRetryDelay(attempt: attempt)
                    print("Retrying in \(delay) seconds...")
                    
                    DispatchQueue.main.async {
                        self.statusMessage = "Retrying in \(Int(delay))s... (attempt \(attempt + 2)/\(self.maxRetries + 1))"
                    }
                    
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    print("Max retries exceeded")
                }
                
            } catch {
                lastError = TranscriptionError.networkError(error)
                print("Network error on attempt \(attempt + 1): \(error.localizedDescription)")
                
                // If this is our last attempt, don't wait
                if attempt < maxRetries {
                    let delay = calculateRetryDelay(attempt: attempt)
                    print("Retrying in \(delay) seconds...")
                    
                    DispatchQueue.main.async {
                        self.statusMessage = "Retrying in \(Int(delay))s... (attempt \(attempt + 2)/\(self.maxRetries + 1))"
                    }
                    
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    print("Max retries exceeded")
                }
            }
        }
        
        // All retries failed, throw the last error
        if let transcriptionError = lastError as? TranscriptionError {
            DispatchQueue.main.async {
                self.statusMessage = "Error: \(transcriptionError.localizedDescription)"
            }
            throw transcriptionError
        } else if let lastError = lastError {
            DispatchQueue.main.async {
                self.statusMessage = "Network error: \(lastError.localizedDescription)"
            }
            throw TranscriptionError.networkError(lastError)
        } else {
            throw TranscriptionError.networkError(NSError(domain: "VoxtralService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
        }
    }
    
    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        // Exponential backoff: 1s, 2s, 4s, capped at maxRetryDelay
        let delay = baseRetryDelay * pow(2.0, Double(attempt))
        return min(delay, maxRetryDelay)
    }
    
    private func performTranscriptionRequest(audioData: Data, url: URL) async throws -> String {
        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30.0 // 30 second timeout
        
        // Create form data with file field
        var body = Data()
        
        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add closing boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        print("Request headers: \(request.allHTTPHeaderFields ?? [:])")
        print("Request body size: \(body.count) bytes")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response type: \(type(of: response))")
            throw TranscriptionError.invalidResponse
        }
        
        print("HTTP Status Code: \(httpResponse.statusCode)")
        print("Response headers: \(httpResponse.allHeaderFields)")
        
        switch httpResponse.statusCode {
        case 200..<300:
            // Try to parse as JSON first
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let transcription = jsonObject["text"] as? String {
                print("JSON response received: \(transcription)")
                return transcription
            }
            // If not JSON, treat as plain text
            else if let transcription = String(data: data, encoding: .utf8) {
                print("Plain text response received: \(transcription)")
                return transcription.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                print("Could not parse response data")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Raw response: \(responseString)")
                }
                throw TranscriptionError.invalidResponseFormat
            }
            
        case 400..<500:
            print("Client error: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Error response: \(responseString)")
            }
            throw TranscriptionError.clientError(httpResponse.statusCode)
            
        case 500..<600:
            print("Server error: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Error response: \(responseString)")
            }
            throw TranscriptionError.serverError(httpResponse.statusCode)
            
        default:
            print("Unknown error: \(httpResponse.statusCode)")
            throw TranscriptionError.unknownError(httpResponse.statusCode)
        }
    }
    
    func testConnection(serverURL: String) async throws -> Bool {
        guard let url = URL(string: serverURL) else {
            return false
        }
        
        // Convert the transcribe URL to a health URL
        // e.g., http://localhost:8080/transcribe -> http://localhost:8080/health
        var healthURLString = serverURL
        if healthURLString.hasSuffix("/transcribe") {
            healthURLString = String(healthURLString.dropLast("/transcribe".count)) + "/health"
        } else if healthURLString.contains("/transcribe") {
            healthURLString = healthURLString.replacingOccurrences(of: "/transcribe", with: "/health")
        } else {
            // If no transcribe in URL, just append /health to base URL
            if let baseURL = URL(string: serverURL) {
                var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
                components?.path = "/health"
                healthURLString = components?.url?.absoluteString ?? serverURL
            }
        }
        
        guard let healthURL = URL(string: healthURLString) else {
            return false
        }
        
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10.0 // 10 second timeout for health checks
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
            
        } catch {
            return false
        }
    }
}

enum TranscriptionError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidResponseFormat
    case clientError(Int)
    case serverError(Int)
    case unknownError(Int)
    case networkError(Error)
    case audioProcessingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL provided"
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidResponseFormat:
            return "Server returned invalid response format"
        case .clientError(let code):
            return "Client error: \(code)"
        case .serverError(let code):
            return "Server error: \(code)"
        case .unknownError(let code):
            return "Unknown error: \(code)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .audioProcessingFailed:
            return "Failed to process audio data"
        }
    }
}

// MARK: - TranscriptionQueue Implementation

class TranscriptionQueue: ObservableObject {
    static let shared = TranscriptionQueue()
    
    @Published var isProcessing = false
    @Published var queueCount = 0
    @Published var currentChunkId: String?
    
    private let audioChunkStore = AudioChunkStore.shared
    private let voxtralService = VoxtralService()
    private var processingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // Configuration
    private let processingInterval: TimeInterval = 2.0 // Check for pending chunks every 2 seconds
    private let maxRetryCount = 5
    private let retryIntervals: [TimeInterval] = [5, 15, 60, 300, 900] // 5s, 15s, 1m, 5m, 15m
    
    private init() {
        startProcessing()
        
        // Monitor pending chunks count
        audioChunkStore.$pendingChunks
            .combineLatest(audioChunkStore.$failedChunks)
            .map { pending, failed in
                pending.count + failed.filter { $0.retryCount < self.maxRetryCount }.count
            }
            .assign(to: \.queueCount, on: self)
            .store(in: &cancellables)
    }
    
    deinit {
        stopProcessing()
    }
    
    // MARK: - Public Interface
    
    func startProcessing() {
        guard processingTimer == nil else { return }
        
        print("Starting transcription queue processing")
        processingTimer = Timer.scheduledTimer(withTimeInterval: processingInterval, repeats: true) { _ in
            Task {
                await self.processNextChunk()
            }
        }
        
        // Process immediately on start
        Task {
            await processNextChunk()
        }
    }
    
    func stopProcessing() {
        processingTimer?.invalidate()
        processingTimer = nil
        print("Stopped transcription queue processing")
    }
    
    func enqueueChunk(audioData: Data, timestamp: Date, serverURL: String, estimatedDuration: Double? = nil) {
        let chunkId = audioChunkStore.storeAudioChunk(
            audioData: audioData,
            timestamp: timestamp,
            estimatedDuration: estimatedDuration
        )
        
        if !chunkId.isEmpty {
            print("Enqueued audio chunk for transcription: \(chunkId)")
            
            // Store server URL for this chunk
            UserDefaults.standard.set(serverURL, forKey: "serverURL_\(chunkId)")
            
            // Trigger immediate processing if not currently processing
            if !isProcessing {
                Task {
                    await processNextChunk()
                }
            }
        }
    }
    
    func retryFailedChunks() {
        Task {
            await processFailedChunks()
        }
    }
    
    func clearFailedChunks() {
        let failedChunks = audioChunkStore.getFailedChunks()
        for chunk in failedChunks {
            if chunk.retryCount >= maxRetryCount {
                audioChunkStore.deleteChunk(chunk.id)
                // Clean up server URL
                UserDefaults.standard.removeObject(forKey: "serverURL_\(chunk.id)")
            }
        }
    }
    
    // MARK: - Private Processing Methods
    
    @MainActor
    private func processNextChunk() async {
        guard !isProcessing else { return }
        
        // Get next chunk to process (pending first, then failed that are ready for retry)
        guard let chunk = getNextChunkToProcess() else { return }
        
        isProcessing = true
        currentChunkId = chunk.id
        
        print("Processing chunk: \(chunk.id)")
        
        // Mark as processing
        audioChunkStore.updateChunkStatus(chunk.id, status: .processing)
        
        do {
            // Get server URL for this chunk
            let serverURL = UserDefaults.standard.string(forKey: "serverURL_\(chunk.id)") ?? "http://localhost:8080/transcribe"
            
            // Load audio data from file
            let audioData = try Data(contentsOf: URL(fileURLWithPath: chunk.filePath))
            
            // Attempt transcription
            let result = try await voxtralService.transcribe(audioData: audioData, serverURL: serverURL)
            
            // Success - mark as completed
            audioChunkStore.updateChunkStatus(chunk.id, status: .completed, transcriptionResult: result)
            
            // Clean up server URL
            UserDefaults.standard.removeObject(forKey: "serverURL_\(chunk.id)")
            
            print("Successfully transcribed chunk: \(chunk.id)")
            
            // Notify listeners about successful transcription
            NotificationCenter.default.post(
                name: .chunkTranscribed,
                object: nil,
                userInfo: [
                    "chunkId": chunk.id,
                    "result": result,
                    "timestamp": chunk.timestamp
                ]
            )
            
        } catch {
            print("Failed to transcribe chunk \(chunk.id): \(error)")
            
            // Mark as failed with error message
            audioChunkStore.updateChunkStatus(
                chunk.id, 
                status: .failed, 
                errorMessage: error.localizedDescription
            )
        }
        
        isProcessing = false
        currentChunkId = nil
    }
    
    private func processFailedChunks() async {
        let failedChunks = audioChunkStore.getFailedChunks()
        
        for chunk in failedChunks {
            if shouldRetryChunk(chunk) {
                await processChunk(chunk)
            }
        }
    }
    
    private func processChunk(_ chunk: AudioChunk) async {
        print("Retrying chunk: \(chunk.id) (attempt \(chunk.retryCount + 1))")
        
        // Mark as processing
        audioChunkStore.updateChunkStatus(chunk.id, status: .processing)
        
        do {
            // Get server URL for this chunk
            let serverURL = UserDefaults.standard.string(forKey: "serverURL_\(chunk.id)") ?? "http://localhost:8080/transcribe"
            
            // Load audio data from file
            let audioData = try Data(contentsOf: URL(fileURLWithPath: chunk.filePath))
            
            // Attempt transcription
            let result = try await voxtralService.transcribe(audioData: audioData, serverURL: serverURL)
            
            // Success - mark as completed
            audioChunkStore.updateChunkStatus(chunk.id, status: .completed, transcriptionResult: result)
            
            // Clean up server URL
            UserDefaults.standard.removeObject(forKey: "serverURL_\(chunk.id)")
            
            print("Successfully retried chunk: \(chunk.id)")
            
            // Notify listeners about successful transcription
            NotificationCenter.default.post(
                name: .chunkTranscribed,
                object: nil,
                userInfo: [
                    "chunkId": chunk.id,
                    "result": result,
                    "timestamp": chunk.timestamp
                ]
            )
            
        } catch {
            print("Failed to retry chunk \(chunk.id): \(error)")
            
            // Mark as failed with updated retry count
            audioChunkStore.updateChunkStatus(
                chunk.id, 
                status: .failed, 
                errorMessage: error.localizedDescription
            )
        }
    }
    
    private func getNextChunkToProcess() -> AudioChunk? {
        // First, check for pending chunks
        let pendingChunks = audioChunkStore.getPendingChunks()
        if let nextPending = pendingChunks.first {
            return nextPending
        }
        
        // Then check for failed chunks that are ready for retry
        let failedChunks = audioChunkStore.getFailedChunks()
        for chunk in failedChunks {
            if shouldRetryChunk(chunk) {
                return chunk
            }
        }
        
        return nil
    }
    
    private func shouldRetryChunk(_ chunk: AudioChunk) -> Bool {
        // Don't retry if we've exceeded max retry count
        guard chunk.retryCount < maxRetryCount else { return false }
        
        // Calculate when the chunk should be retried
        guard let lastRetryAt = chunk.lastRetryAt else { return true }
        
        let retryIndex = min(chunk.retryCount, retryIntervals.count - 1)
        let retryInterval = retryIntervals[retryIndex]
        let nextRetryTime = lastRetryAt.addingTimeInterval(retryInterval)
        
        return Date() >= nextRetryTime
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let chunkTranscribed = Notification.Name("chunkTranscribed")
}
