import Foundation

// Test that final transcription appears in both Live view AND saved history

class MockDatabaseManager {
    var transcriptions: [Transcription] = []
    var updateTranscriptionCalls: [(id: Int64, text: String, duration: Double?, audioFilePath: String?)] = []
    var saveTranscriptionCalls: [(text: String, duration: Double?, audioFilePath: String?)] = []
    
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
    
    func saveTranscription(text: String, duration: Double? = nil, audioFilePath: String? = nil) -> Int64? {
        saveTranscriptionCalls.append((text: text, duration: duration, audioFilePath: audioFilePath))
        let newId = Int64(transcriptions.count + 1)
        let transcription = Transcription(
            id: newId,
            text: text,
            timestamp: Date(),
            duration: duration,
            audioFilePath: audioFilePath,
            createdAt: Date()
        )
        transcriptions.append(transcription)
        // Sort to keep newest first (like real implementation)
        transcriptions.sort { $0.createdAt > $1.createdAt }
        return newId
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

class TranscriptionHandler {
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
    
    func saveCurrentTranscription() {
        guard !transcriptionChunks.isEmpty else { return }
        
        let fullText = transcriptionChunks.map { $0.text }.joined(separator: " ")
        let duration = transcriptionChunks.last?.timestamp.timeIntervalSince(transcriptionChunks.first?.timestamp ?? Date()) ?? 0
        
        if let existingId = currentTranscriptionId {
            _ = databaseManager.updateTranscription(
                id: existingId,
                text: fullText,
                duration: duration,
                audioFilePath: nil
            )
            print("Updated transcription with ID: \(existingId)")
        } else {
            if let newId = databaseManager.saveTranscription(
                text: fullText,
                duration: duration,
                audioFilePath: nil
            ) {
                currentTranscriptionId = newId
                print("Created new transcription with ID: \(newId)")
            }
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
    
    func stopRecording() {
        isRecording = false
        saveCurrentTranscription()
    }
    
    func startRecording() {
        isRecording = true
        transcriptionChunks.removeAll()
        currentTranscriptionId = nil
    }
}

// Test the specific scenario
func runLiveTranscriptionToHistoryTest() -> Bool {
    print("=== Live Transcription to History Test ===")
    print("Testing: User finishes recording -> final transcription in Live view -> clicks most recent history item")
    
    let mockDB = MockDatabaseManager()
    let handler = TranscriptionHandler(databaseManager: mockDB)
    
    // Step 1: Start recording and receive chunks
    print("\n1. Start recording and receive chunks...")
    handler.startRecording()
    
    let baseTime = Date()
    handler.handleTranscriptionResult(chunkId: "chunk-1", result: "Hello world", timestamp: baseTime)
    handler.handleTranscriptionResult(chunkId: "chunk-2", result: "world this is", timestamp: baseTime.addingTimeInterval(1))
    handler.handleTranscriptionResult(chunkId: "chunk-3", result: "is a complete", timestamp: baseTime.addingTimeInterval(2))
    
    print("Live view chunks during recording: \(handler.transcriptionChunks.map { $0.text })")
    
    // Step 2: User stops recording
    print("\n2. User stops recording...")
    handler.stopRecording()
    
    print("Database entries after stopping: \(mockDB.transcriptions.count)")
    print("Most recent transcription: '\(mockDB.transcriptions.first?.text ?? "")'")
    
    // Step 3: Final chunk arrives after recording stopped (this is the critical case)
    print("\n3. Final chunk arrives after recording stopped...")
    handler.handleTranscriptionResult(chunkId: "chunk-4", result: "complete sentence here", timestamp: baseTime.addingTimeInterval(3))
    
    print("Live view after final chunk: \(handler.transcriptionChunks.map { $0.text })")
    
    // Step 4: Simulate user clicking on most recent transcription in history
    print("\n4. User clicks on most recent transcription in history...")
    let mostRecentTranscription = mockDB.transcriptions.first
    
    // This is what the user would see when they click on the history item
    let historyItemText = mostRecentTranscription?.text ?? ""
    let liveViewText = handler.transcriptionChunks.map { $0.text }.joined(separator: " ")
    
    print("=== Results ===")
    print("Live transcription view: '\(liveViewText)'")
    print("Most recent history item: '\(historyItemText)'")
    
    // The test: These should match exactly
    if historyItemText == liveViewText {
        print("✓ SUCCESS: Live view matches history item perfectly")
        print("✓ User sees the same complete transcription in both places")
    } else {
        print("✗ FAILURE: Live view and history don't match")
        print("  This means the user would see incomplete transcription in history")
        
        // Analyze what's missing
        let liveWords = Set(liveViewText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        let historyWords = Set(historyItemText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
        
        let missingFromHistory = liveWords.subtracting(historyWords)
        let extraInHistory = historyWords.subtracting(liveWords)
        
        if !missingFromHistory.isEmpty {
            print("  Words missing from history: \(missingFromHistory)")
        }
        if !extraInHistory.isEmpty {
            print("  Extra words in history: \(extraInHistory)")
        }
    }
    
    // Additional checks
    print("\n=== Additional Verification ===")
    print("Database update calls: \(mockDB.updateTranscriptionCalls.count)")
    print("Database save calls: \(mockDB.saveTranscriptionCalls.count)")
    print("Total transcription entries: \(mockDB.transcriptions.count)")
    
    // Verify the expected words are all present
    let expectedWords = ["Hello", "world", "this", "is", "a", "complete", "sentence", "here"]
    let actualWords = historyItemText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    
    let allWordsPresent = Set(expectedWords).isSubset(of: Set(actualWords))
    if allWordsPresent {
        print("✓ All expected words present in final transcription")
    } else {
        let missingWords = Set(expectedWords).subtracting(Set(actualWords))
        print("✗ Missing words: \(missingWords)")
    }
    
    print("\n=== Test Complete ===")
    
    return historyItemText == liveViewText && allWordsPresent
}

// Run the test
let testPassed = runLiveTranscriptionToHistoryTest()
print("\nOVERALL TEST RESULT: \(testPassed ? "PASSED" : "FAILED")")