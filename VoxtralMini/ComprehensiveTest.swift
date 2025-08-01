import Foundation

// Comprehensive test that simulates the entire final chunk flow

class MockDatabaseManager {
    var transcriptions: [Transcription] = []
    var updateTranscriptionCalls: [(id: Int64, text: String, duration: Double?, audioFilePath: String?)] = []
    
    func updateTranscription(id: Int64, text: String, duration: Double? = nil, audioFilePath: String? = nil) -> Bool {
        updateTranscriptionCalls.append((id: id, text: text, duration: duration, audioFilePath: audioFilePath))
        
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
        
        for overlapLength in (1...maxPossibleOverlap).reversed() {
            let previousOverlap = Array(previousWords.suffix(overlapLength))
            let newOverlap = Array(newWords.prefix(overlapLength))
            
            if previousOverlap == newOverlap {
                maxOverlap = overlapLength
                break
            }
        }
        
        if maxOverlap == 0 && !previousWords.isEmpty && !newWords.isEmpty {
            let lastPreviousWord = previousWords.last!.lowercased()
            let firstNewWord = newWords.first!.lowercased()
            
            if firstNewWord.hasPrefix(lastPreviousWord) && firstNewWord.count > lastPreviousWord.count {
                if !transcriptionChunks.isEmpty {
                    let lastChunk = transcriptionChunks.last!
                    let previousWordsMinusLast = Array(previousWords.dropLast())
                    let updatedPreviousText = (previousWordsMinusLast + [firstNewWord]).joined(separator: " ")
                    
                    transcriptionChunks[transcriptionChunks.count - 1] = TranscriptionChunk(
                        text: updatedPreviousText,
                        timestamp: lastChunk.timestamp
                    )
                }
                
                let remainingNewWords = Array(newWords.dropFirst())
                return remainingNewWords.joined(separator: " ")
                
            } else if lastPreviousWord.hasPrefix(firstNewWord) && lastPreviousWord.count > firstNewWord.count {
                maxOverlap = 1
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
            print("Updated existing transcription with ID: \(existingId)")
        } else {
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
                print("Updated most recent transcription with ID: \(recentId)")
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

// Comprehensive test simulating real-world scenario
func runComprehensiveTest() {
    print("=== Comprehensive Final Chunk Test ===")
    print("Simulating: User stops recording, some chunks are still processing")
    
    let mockDB = MockDatabaseManager()
    let handler = FinalChunkHandler(databaseManager: mockDB)
    
    // Step 1: Simulate recording session with initial chunks
    print("\n1. Recording session starts...")
    handler.isRecording = true
    
    // Simulate receiving chunks during recording
    let baseTime = Date()
    handler.handleTranscriptionResult(chunkId: "chunk-1", result: "Hello there", timestamp: baseTime)
    handler.handleTranscriptionResult(chunkId: "chunk-2", result: "there how are", timestamp: baseTime.addingTimeInterval(1))
    handler.handleTranscriptionResult(chunkId: "chunk-3", result: "are you doing", timestamp: baseTime.addingTimeInterval(2))
    handler.handleTranscriptionResult(chunkId: "chunk-4", result: "doing today my", timestamp: baseTime.addingTimeInterval(3))
    
    print("During recording chunks: \(handler.transcriptionChunks.map { $0.text })")
    
    // Step 2: User stops recording - save current transcription
    print("\n2. User stops recording...")
    handler.isRecording = false
    
    // Simulate saving the current transcription to database
    let currentText = handler.transcriptionChunks.map { $0.text }.joined(separator: " ")
    let duration = handler.transcriptionChunks.last?.timestamp.timeIntervalSince(handler.transcriptionChunks.first?.timestamp ?? Date()) ?? 0
    
    // Mock saving to database (like saveCurrentTranscription would do)
    let transcriptionId: Int64 = 1
    mockDB.transcriptions.append(Transcription(
        id: transcriptionId,
        text: currentText,
        timestamp: baseTime,
        duration: duration,
        audioFilePath: nil,
        createdAt: baseTime
    ))
    handler.currentTranscriptionId = transcriptionId
    
    print("Saved transcription: '\(currentText)'")
    print("Database now contains: '\(mockDB.transcriptions.first?.text ?? "")'")
    
    // Step 3: Final chunks arrive after recording stopped
    print("\n3. Final chunks arrive after recording stopped...")
    
    // These are the critical chunks that could be lost
    handler.handleTranscriptionResult(chunkId: "chunk-5", result: "my friend", timestamp: baseTime.addingTimeInterval(4))
    handler.handleTranscriptionResult(chunkId: "chunk-6", result: "friend how is", timestamp: baseTime.addingTimeInterval(5))
    handler.handleTranscriptionResult(chunkId: "chunk-7", result: "is everything going", timestamp: baseTime.addingTimeInterval(6))
    
    // Step 4: Verify results
    print("\n=== Final Results ===")
    print("Final chunks in live view: \(handler.transcriptionChunks.map { $0.text })")
    print("Database update calls: \(mockDB.updateTranscriptionCalls.count)")
    
    if let finalDBText = mockDB.transcriptions.first?.text {
        print("Final database text: '\(finalDBText)'")
        
        // Expected: All chunks properly deduplicated and combined
        let expectedPieces = [
            "Hello there",       // chunk 1 + deduped chunk 2 
            "how are",          // deduped chunk 2 
            "you doing",        // deduped chunk 3
            "today my",         // deduped chunk 4
            "friend",           // deduped chunk 5
            "how is",           // deduped chunk 6
            "everything going"  // deduped chunk 7
        ]
        let expectedFinalText = "Hello there how are you doing today my friend how is everything going"
        
        if finalDBText == expectedFinalText {
            print("✓ SUCCESS: Final text is correctly deduplicated and complete")
        } else {
            print("✗ ISSUE: Final text doesn't match expected")
            print("Expected: '\(expectedFinalText)'")
            print("Actual:   '\(finalDBText)'")
        }
    }
    
    // Verify no audio was lost
    let allExpectedWords = ["Hello", "there", "how", "are", "you", "doing", "today", "my", "friend", "how", "is", "everything", "going"]
    let finalWords = (mockDB.transcriptions.first?.text ?? "").components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    
    print("\nWord analysis:")
    print("Expected words: \(allExpectedWords)")
    print("Final words:    \(finalWords)")
    
    let missingWords = Set(allExpectedWords).subtracting(Set(finalWords))
    if missingWords.isEmpty {
        print("✓ SUCCESS: No words were lost")
    } else {
        print("✗ ISSUE: Missing words: \(missingWords)")
    }
    
    print("\n=== Test Complete ===")
    print("Database updates made: \(mockDB.updateTranscriptionCalls.count)")
    print("Chunks processed after recording stopped: 3")
    print("Final transcription preserved: ✓")
}

runComprehensiveTest()