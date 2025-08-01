import Foundation
import Combine

class VoxtralService: ObservableObject {
    @Published var statusMessage = ""
    @Published var isTranscribing = false
    
    private var cancellables = Set<AnyCancellable>()
    
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
        
        // Create multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
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
        
        do {
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
                    DispatchQueue.main.async {
                        self.statusMessage = "Transcription completed successfully"
                    }
                    return transcription
                }
                // If not JSON, treat as plain text
                else if let transcription = String(data: data, encoding: .utf8) {
                    print("Plain text response received: \(transcription)")
                    DispatchQueue.main.async {
                        self.statusMessage = "Transcription completed successfully"
                    }
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
            
        } catch let error as TranscriptionError {
            print("Transcription service error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.statusMessage = "Error: \(error.localizedDescription)"
            }
            throw error
            
        } catch {
            print("Network error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.statusMessage = "Network error: \(error.localizedDescription)"
            }
            throw TranscriptionError.networkError(error)
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
