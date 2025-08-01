import Foundation

// Test complex deduplication scenarios

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
    
    // Handle partial word completion edge case
    if maxOverlap == 0 && !previousWords.isEmpty && !newWords.isEmpty {
        let lastPreviousWord = previousWords.last!.lowercased()
        let firstNewWord = newWords.first!.lowercased()
        
        if firstNewWord.hasPrefix(lastPreviousWord) && firstNewWord.count > lastPreviousWord.count {
            // The new word is a completion of the previous partial word
            let remainingNewWords = Array(newWords.dropFirst())
            return remainingNewWords.joined(separator: " ")
        } else if lastPreviousWord.hasPrefix(firstNewWord) && lastPreviousWord.count > firstNewWord.count {
            // The previous word was a completion, just skip the duplicate first word
            maxOverlap = 1
        }
    }
    
    if maxOverlap > 0 {
        let dedupedWords = Array(newWords.dropFirst(maxOverlap))
        return dedupedWords.joined(separator: " ")
    }
    
    return newText
}

func runDeduplicationTests() {
    print("=== Running Deduplication Tests ===")
    
    let testCases = [
        // (previousText, newText, expectedResult, description)
        ("Hello world this is a test", "test recording complete", "recording complete", "Single word overlap"),
        ("Hello world this is", "is a test recording", "a test recording", "Single word at end"),
        ("Hello world", "world testing complete", "testing complete", "Single word overlap"),
        ("The quick brown", "brown fox jumps", "fox jumps", "Single word overlap"),
        ("I am going to the", "to the store today", "store today", "Multi-word overlap"),
        ("This is a long sentence with many", "many words in it", "words in it", "Single word at end"),
        ("Hello world thi", "this is complete", "s is complete", "Partial word completion (should work differently in real implementation)"),
        ("", "new text", "new text", "Empty previous text"),
        ("existing text", "", "", "Empty new text"),
        ("same text", "completely different", "completely different", "No overlap"),
        ("word", "word", "", "Complete overlap"),
        ("a b c d e", "c d e f g", "f g", "Multi-word overlap"),
    ]
    
    var passedTests = 0
    var totalTests = testCases.count
    
    for (i, testCase) in testCases.enumerated() {
        let (previousText, newText, expectedResult, description) = testCase
        let actualResult = deduplicateText(previousText, newText)
        
        print("\nTest \(i + 1): \(description)")
        print("Previous: '\(previousText)'")
        print("New:      '\(newText)'")
        print("Expected: '\(expectedResult)'")
        print("Actual:   '\(actualResult)'")
        
        if actualResult == expectedResult {
            print("✓ PASS")
            passedTests += 1
        } else {
            print("✗ FAIL")
        }
    }
    
    print("\n=== Deduplication Test Summary ===")
    print("Passed: \(passedTests)/\(totalTests)")
    
    if passedTests == totalTests {
        print("✓ All deduplication tests passed!")
    } else {
        print("✗ Some deduplication tests failed")
    }
}

runDeduplicationTests()