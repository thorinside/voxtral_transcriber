import Foundation

// Test that proves final audio chunk will be transcribed, deduped, and database updated

// Mock classes
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

// Simplified test class that mimics ContentView behavior
class FinalChunkHandler {
    var databaseManager: MockDatabaseManager
    var isRecording = false
    var currentTranscriptionId: Int64?
    var transcriptionChunks: [TranscriptionChunk] = []
    
    init(databaseManager: MockDatabaseManager) {
        self.databaseManager = databaseManager
    }
    
    // Copied from ContentView
    func deduplicateText(_ previousText: String, _ newText: String) -> String {
        let previousWords = previousText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let newWords = newText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        guard !previousWords.isEmpty && !newWords.isEmpty else {
            return newText
        }
        
        // Enhanced overlap detection for better fragment splicing
        var maxOverlap = 0
        let maxPossibleOverlap = min(previousWords.count, newWords.count)
        
        // Try to find the longest exact word sequence match (search from longest to shortest)
        for overlapLength in (1...maxPossibleOverlap).reversed() {
            let previousOverlap = Array(previousWords.suffix(overlapLength))
            let newOverlap = Array(newWords.prefix(overlapLength))
            
            if previousOverlap == newOverlap {
                maxOverlap = overlapLength
                break // Take the longest match
            }
        }
        
        // If no exact match, try fuzzy matching for partial words at boundaries
        if maxOverlap == 0 && !previousWords.isEmpty && !newWords.isEmpty {
            let lastPreviousWord = previousWords.last!.lowercased()
            let firstNewWord = newWords.first!.lowercased()
            
            // Check if the first word of new text is a continuation of the last word of previous text
            if firstNewWord.hasPrefix(lastPreviousWord) && firstNewWord.count > lastPreviousWord.count {
                // The new word is a completion of the previous partial word
                // Update the last chunk in place with the complete word
                if !transcriptionChunks.isEmpty {
                    let lastChunk = transcriptionChunks.last!
                    let previousWordsMinusLast = Array(previousWords.dropLast())
                    let updatedPreviousText = (previousWordsMinusLast + [firstNewWord]).joined(separator: " ")
                    
                    // Replace the last chunk with updated text
                    transcriptionChunks[transcriptionChunks.count - 1] = TranscriptionChunk(
                        text: updatedPreviousText,
                        timestamp: lastChunk.timestamp
                    )
                }
                
                // Return the new text without the first word (already merged)
                let remainingNewWords = Array(newWords.dropFirst())
                return remainingNewWords.joined(separator: " ")
                
            } else if lastPreviousWord.hasPrefix(firstNewWord) && lastPreviousWord.count > firstNewWord.count {
                // The previous word was a completion, just skip the duplicate first word
                maxOverlap = 1
            }
        }
        
        if maxOverlap > 0 {
            // Remove the overlapping words from the new text
            let dedupedWords = Array(newWords.dropFirst(maxOverlap))
            let result = dedupedWords.joined(separator: " ")
            return result
        }
        
        return newText
    }
    
    func addTranscriptionChunkToLiveView(_ chunk: TranscriptionChunk) {
        // Apply deduplication with the previous chunk
        if let lastChunk = transcriptionChunks.last {
            let dedupedText = deduplicateText(lastChunk.text, chunk.text)
            if dedupedText != chunk.text {
                // Create a deduped version of the new chunk
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
        // This method handles updating the database when late transcription results arrive
        guard !transcriptionChunks.isEmpty else { return }
        
        // If we have a current transcription ID, update it
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
            // If we don't have a current ID, try to find the most recent transcription to update
            // This handles the case where the transcription was already saved and cleared
            let mostRecentTranscription = databaseManager.transcriptions.first
            if let recentId = mostRecentTranscription?.id {
                let newChunksText = transcriptionChunks.map { $0.text }.joined(separator: " ")
                let duration = transcriptionChunks.last?.timestamp.timeIntervalSince(transcriptionChunks.first?.timestamp ?? Date()) ?? 0
                
                // Apply deduplication between existing text and new chunks
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
        // Add the transcription result to the live view
        // This includes chunks that finish processing after recording stops
        let chunk = TranscriptionChunk(text: result, timestamp: timestamp)
        addTranscriptionChunkToLiveView(chunk)
        
        // If we're not currently recording but have chunks, update the existing transcription
        // This handles the case where final chunks complete after recording stops
        if !isRecording && !transcriptionChunks.isEmpty {
            // Update the existing transcription with the new chunks
            updateExistingTranscription()
        }
    }
}

// Test function
func runFinalChunkTest() {
    print("=== Running Final Chunk Transcription Test ===")
    
    let mockDB = MockDatabaseManager()
    let handler = FinalChunkHandler(databaseManager: mockDB)
    
    // GIVEN: A recording session has ended and we have an initial transcription saved
    let initialTranscriptionId: Int64 = 1
    let initialText = "Hello world this is a test"
    let initialTimestamp = Date()
    
    // Mock initial transcription saved to database
    mockDB.transcriptions = [
        Transcription(
            id: initialTranscriptionId,
            text: initialText,
            timestamp: initialTimestamp,
            duration: 2.5,
            audioFilePath: nil,
            createdAt: initialTimestamp
        )
    ]
    
    // Set up handler state to simulate recording has stopped
    handler.isRecording = false
    handler.currentTranscriptionId = initialTranscriptionId
    handler.transcriptionChunks = [
        TranscriptionChunk(text: "Hello world this is a test", timestamp: initialTimestamp)
    ]
    
    print("Initial state: isRecording=\(handler.isRecording), transcriptionId=\(handler.currentTranscriptionId ?? 0)")
    print("Initial chunks: \(handler.transcriptionChunks.map { $0.text })")
    print("Initial DB text: '\(mockDB.transcriptions.first?.text ?? "")'")
    
    // WHEN: A final audio chunk completes transcription after recording stopped
    let finalChunkText = "test recording complete"
    let finalChunkTimestamp = initialTimestamp.addingTimeInterval(2.5)
    
    print("\nReceiving final chunk: '\(finalChunkText)'")
    handler.handleTranscriptionResult(chunkId: "chunk-123", result: finalChunkText, timestamp: finalChunkTimestamp)
    
    // THEN: Verify the transcription was deduplicated and database was updated
    print("\n=== Results ===")
    print("Database update calls: \(mockDB.updateTranscriptionCalls.count)")
    
    if mockDB.updateTranscriptionCalls.count == 1 {
        let updateCall = mockDB.updateTranscriptionCalls.first!
        print("✓ Database updated once")
        print("Updated ID: \(updateCall.id) (expected: \(initialTranscriptionId))")
        print("Updated text: '\(updateCall.text)'")
        
        // The final text should be deduplicated (removing overlap between "test" and "test recording complete")
        let expectedFinalText = "Hello world this is a test recording complete"
        if updateCall.text == expectedFinalText {
            print("✓ Text properly deduplicated: '\(updateCall.text)'")
        } else {
            print("✗ Text deduplication failed:")
            print("  Expected: '\(expectedFinalText)'")
            print("  Actual:   '\(updateCall.text)'")
        }
        
        if updateCall.id == initialTranscriptionId {
            print("✓ Correct transcription ID updated")
        } else {
            print("✗ Wrong transcription ID updated")
        }
    } else {
        print("✗ Database update calls: \(mockDB.updateTranscriptionCalls.count) (expected: 1)")
    }
    
    print("Final chunks count: \(handler.transcriptionChunks.count) (expected: 2)")
    if handler.transcriptionChunks.count == 2 {
        print("✓ Chunks added correctly")
        print("Final chunk text: '\(handler.transcriptionChunks.last?.text ?? "")'")
        let expectedFinalChunk = "recording complete"
        if handler.transcriptionChunks.last?.text == expectedFinalChunk {
            print("✓ Final chunk properly deduplicated")
        } else {
            print("✗ Final chunk deduplication failed:")
            print("  Expected: '\(expectedFinalChunk)'")
            print("  Actual:   '\(handler.transcriptionChunks.last?.text ?? "")'")
        }
    } else {
        print("✗ Wrong number of chunks")
    }
    
    print("\n=== Test Complete ===")
}

// Run the test
runFinalChunkTest()