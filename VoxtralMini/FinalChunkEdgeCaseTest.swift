import Foundation

// Test edge case where currentTranscriptionId is nil

// Mock classes (same as before)
class MockDatabaseManager {
    var transcriptions: [Transcription] = []
    var updateTranscriptionCalls: [(id: Int64, text: String, duration: Double?, audioFilePath: String?)] = []
    
    func updateTranscription(id: Int64, text: String, duration: Double? = nil, audioFilePath: String? = nil) -> Bool {
        updateTranscriptionCalls.append((id: id, text: text, duration: duration, audioFilePath: audioFilePath))
        
        // Update the mock transcription
        if let index = transcriptions.firstIndex(where: { $0.id == id }) {
            transcriptions[index] = Transcription(
                id: id,
                text: text,
                timestamp: transcriptions[index].timestamp,
                duration: duration,
                audioFilePath: audioFilePath,
                createdAt: transcriptions[index].createdAt
            )
        }
        return true
    }
}

struct Transcription {
    var id: Int64
    var text: String
    var timestamp: Date
    var duration: Double?
    var audioFilePath: String?
    var createdAt: Date
}

struct TranscriptionChunk {
    let text: String
    let timestamp: Date
    let isDeduped: Bool
    
    init(text: String, timestamp: Date, isDeduped: Bool = false) {
        self.text = text
        self.timestamp = timestamp
        self.isDeduped = isDeduped
    }
}

// Simplified test class (same as before)
class FinalChunkHandler {
    var databaseManager: MockDatabaseManager
    var isRecording = false
    var currentTranscriptionId: Int64?
    var transcriptionChunks: [TranscriptionChunk] = []
    
    init(databaseManager: MockDatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    func deduplicateText(_ previousText: String, _ newText: String) -> String {
        let previousWords = previousText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let newWords = newText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        guard !previousWords.isEmpty && !newWords.isEmpty else {
            return newText
        }
        
        var maxOverlap = 0
        let maxPossibleOverlap = min(previousWords.count, newWords.count)
        
        // Try to find the longest exact word sequence match
        for overlapLength in (1...maxPossibleOverlap).reversed() {
            let previousOverlap = Array(previousWords.suffix(overlapLength))
            let newOverlap = Array(newWords.prefix(overlapLength))
            
            if previousOverlap == newOverlap {
                maxOverlap = overlapLength
                break
            }
        }
        
        if maxOverlap > 0 {
            let dedupedWords = Array(newWords.dropFirst(maxOverlap))
            return dedupedWords.joined(separator: " ")
        }
        
        return newText
    }
    
    func addTranscriptionChunkToLiveView(_ chunk: TranscriptionChunk) {
        if let lastChunk = transcriptionChunks.last {
            let dedupedText = deduplicateText(lastChunk.text, chunk.text)
            if dedupedText != chunk.text {
                let dedupedChunk = TranscriptionChunk(text: dedupedText, timestamp: chunk.timestamp)
                transcriptionChunks.append(dedupedChunk)
                print("Applied deduplication: '\(chunk.text)' -> '\(dedupedText)'")
            } else {
                transcriptionChunks.append(chunk)
            }
        } else {
            transcriptionChunks.append(chunk)
        }
    }
    
    func updateExistingTranscription() {
        guard !transcriptionChunks.isEmpty else { return }
        
        if let existingId = currentTranscriptionId {
            let fullText = transcriptionChunks.map { $0.text }.joined(separator: " ")
            let duration = transcriptionChunks.last?.timestamp.timeIntervalSince(transcriptionChunks.first?.timestamp ?? Date()) ?? 0
            
            _ = databaseManager.updateTranscription(
                id: existingId,
                text: fullText,
                duration: duration,
                audioFilePath: nil
            )
            print("Updated existing transcription with ID: \(existingId) with late results")
        } else {
            // Edge case: no current transcription ID
            let mostRecentTranscription = databaseManager.transcriptions.first
            if let recentId = mostRecentTranscription?.id {
                let newChunksText = transcriptionChunks.map { $0.text }.joined(separator: " ")
                let duration = transcriptionChunks.last?.timestamp.timeIntervalSince(transcriptionChunks.first?.timestamp ?? Date()) ?? 0
                
                let existingText = mostRecentTranscription?.text ?? ""
                let combinedText = existingText.isEmpty ? newChunksText : deduplicateText(existingText, newChunksText)
                let finalText = existingText.isEmpty ? combinedText : (combinedText.isEmpty ? existingText : "\(existingText) \(combinedText)")
                
                _ = databaseManager.updateTranscription(
                    id: recentId,
                    text: finalText,
                    duration: duration,
                    audioFilePath: nil
                )
                print("Updated most recent transcription with ID: \(recentId) with late results")
                currentTranscriptionId = recentId
            }
        }
    }
    
    func handleTranscriptionResult(chunkId: String, result: String, timestamp: Date) {
        let chunk = TranscriptionChunk(text: result, timestamp: timestamp)
        addTranscriptionChunkToLiveView(chunk)
        
        if !isRecording && !transcriptionChunks.isEmpty {
            updateExistingTranscription()
        }
    }
}

// Test function for edge case
func runEdgeCaseTest() {
    print("=== Running Edge Case Test (No Current Transcription ID) ===")
    
    let mockDB = MockDatabaseManager()
    let handler = FinalChunkHandler(databaseManager: mockDB)
    
    // GIVEN: Recording has stopped but currentTranscriptionId is nil (edge case)
    let existingTranscriptionId: Int64 = 1
    let existingText = "Hello world"
    let existingTimestamp = Date()
    
    // Mock most recent transcription in database
    mockDB.transcriptions = [
        Transcription(
            id: existingTranscriptionId,
            text: existingText,
            timestamp: existingTimestamp,
            duration: 1.0,
            audioFilePath: nil,
            createdAt: existingTimestamp
        )
    ]
    
    // Set up handler state - no current transcription ID
    handler.isRecording = false
    handler.currentTranscriptionId = nil
    handler.transcriptionChunks = []
    
    print("Initial state: isRecording=\(handler.isRecording), transcriptionId=\(handler.currentTranscriptionId?.description ?? "nil")")
    print("Initial chunks: \(handler.transcriptionChunks.map { $0.text })")
    print("Initial DB text: '\(mockDB.transcriptions.first?.text ?? "")'")
    
    // WHEN: A final chunk arrives
    let finalChunkText = "world testing complete"
    let finalChunkTimestamp = existingTimestamp.addingTimeInterval(1.0)
    
    print("\nReceiving final chunk: '\(finalChunkText)'")
    handler.handleTranscriptionResult(chunkId: "chunk-456", result: finalChunkText, timestamp: finalChunkTimestamp)
    
    // THEN: Should update most recent transcription with deduplication
    print("\n=== Results ===")
    print("Database update calls: \(mockDB.updateTranscriptionCalls.count)")
    
    if mockDB.updateTranscriptionCalls.count == 1 {
        let updateCall = mockDB.updateTranscriptionCalls.first!
        print("✓ Database updated once")
        print("Updated ID: \(updateCall.id) (expected: \(existingTranscriptionId))")
        print("Updated text: '\(updateCall.text)'")
        
        // Should deduplicate "world" overlap and combine texts
        let expectedFinalText = "Hello world testing complete"
        if updateCall.text == expectedFinalText {
            print("✓ Text properly deduplicated and combined: '\(updateCall.text)'")
        } else {
            print("✗ Text deduplication/combination failed:")
            print("  Expected: '\(expectedFinalText)'")
            print("  Actual:   '\(updateCall.text)'")
        }
        
        if updateCall.id == existingTranscriptionId {
            print("✓ Correct transcription ID updated")
        } else {
            print("✗ Wrong transcription ID updated")
        }
    } else {
        print("✗ Database update calls: \(mockDB.updateTranscriptionCalls.count) (expected: 1)")
    }
    
    // Should set currentTranscriptionId for future updates
    if handler.currentTranscriptionId == existingTranscriptionId {
        print("✓ currentTranscriptionId set correctly")
    } else {
        print("✗ currentTranscriptionId not set correctly: \(handler.currentTranscriptionId?.description ?? "nil")")
    }
    
    print("\n=== Edge Case Test Complete ===")
}

// Run the edge case test
runEdgeCaseTest()