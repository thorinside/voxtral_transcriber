#!/usr/bin/env swift

import Foundation
import SQLite3

// Mock classes for testing
enum MockAudioChunkStatus: String, CaseIterable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
}

struct MockAudioChunk {
    let id: String
    let filePath: String
    let timestamp: Date
    let status: MockAudioChunkStatus
    let retryCount: Int
    let lastRetryAt: Date?
    let transcriptionResult: String?
    let errorMessage: String?
    let createdAt: Date
    let sizeBytes: Int
    let durationSeconds: Double?
    
    init(id: String, filePath: String, timestamp: Date, sizeBytes: Int, durationSeconds: Double? = nil) {
        self.id = id
        self.filePath = filePath
        self.timestamp = timestamp
        self.status = .pending
        self.retryCount = 0
        self.lastRetryAt = nil
        self.transcriptionResult = nil
        self.errorMessage = nil
        self.createdAt = Date()
        self.sizeBytes = sizeBytes
        self.durationSeconds = durationSeconds
    }
    
    init(id: String, filePath: String, timestamp: Date, status: MockAudioChunkStatus, retryCount: Int, lastRetryAt: Date?, transcriptionResult: String?, errorMessage: String?, createdAt: Date, sizeBytes: Int, durationSeconds: Double?) {
        self.id = id
        self.filePath = filePath
        self.timestamp = timestamp
        self.status = status
        self.retryCount = retryCount
        self.lastRetryAt = lastRetryAt
        self.transcriptionResult = transcriptionResult
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.sizeBytes = sizeBytes
        self.durationSeconds = durationSeconds
    }
}

class MockDatabaseManager {
    private var db: OpaquePointer?
    private let dbPath: String
    
    init() {
        // Create temporary database for testing
        let tempDir = NSTemporaryDirectory()
        let uniqueId = UUID().uuidString + "_" + String(Int.random(in: 1000...9999))
        dbPath = tempDir + "test_voxtral_\(uniqueId).db"
        
        // Remove any existing database with this path (shouldn't happen but just in case)
        try? FileManager.default.removeItem(atPath: dbPath)
        
        setupDatabase()
    }
    
    deinit {
        sqlite3_close(db)
        // Clean up test database
        try? FileManager.default.removeItem(atPath: dbPath)
    }
    
    private func setupDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening test database")
            return
        }
        
        // Create schema version table
        let createVersionTableQuery = """
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
        );
        """
        
        sqlite3_exec(db, createVersionTableQuery, nil, nil, nil)
        
        // Create audio_chunks table
        let createChunksTableQuery = """
        CREATE TABLE IF NOT EXISTS audio_chunks (
            id TEXT PRIMARY KEY,
            file_path TEXT NOT NULL,
            timestamp DATETIME NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            retry_count INTEGER DEFAULT 0,
            last_retry_at DATETIME,
            transcription_result TEXT,
            error_message TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            size_bytes INTEGER NOT NULL,
            duration_seconds REAL
        );
        """
        
        sqlite3_exec(db, createChunksTableQuery, nil, nil, nil)
    }
    
    func insertCorruptedData() -> Bool {
        // First, check if there are any existing records
        let existingCount = countRecords()
        print("   Existing records before insert: \(existingCount)")
        
        // Insert some records with empty status to simulate corruption
        let insertQuery = """
        INSERT INTO audio_chunks (id, file_path, timestamp, status, retry_count, created_at, size_bytes)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        
        let corruptedData = [
            ("\(UUID().uuidString)", "/tmp/chunk1.wav", "", 0),
            ("\(UUID().uuidString)", "/tmp/chunk2.wav", "", 0),
            ("\(UUID().uuidString)", "/tmp/chunk3.wav", "invalid_status", 0),
            ("\(UUID().uuidString)", "/tmp/chunk4.wav", "pending", 0), // Valid record
        ]
        
        print("   Attempting to insert \(corruptedData.count) test records...")
        
        for (i, (id, path, status, retry)) in corruptedData.enumerated() {
            // Check if this ID already exists first
            let checkQuery = "SELECT COUNT(*) FROM audio_chunks WHERE id = ?;"
            var checkStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, checkQuery, -1, &checkStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(checkStmt, 1, (id as NSString).utf8String, -1, nil)
                if sqlite3_step(checkStmt) == SQLITE_ROW {
                    let count = sqlite3_column_int(checkStmt, 0)
                    if count > 0 {
                        print("   ID \(id) already exists! Count: \(count)")
                    }
                }
                sqlite3_finalize(checkStmt)
            }
            
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) != SQLITE_OK {
                let error = String(cString: sqlite3_errmsg(db))
                print("   SQL prepare error: \(error)")
                return false
            }
            
            sqlite3_bind_text(statement, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (path as NSString).utf8String, -1, nil)
            sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
            sqlite3_bind_text(statement, 4, (status as NSString).utf8String, -1, nil)
            sqlite3_bind_int(statement, 5, Int32(retry))
            sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)
            sqlite3_bind_int(statement, 7, 1024)
            
            if sqlite3_step(statement) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                print("   SQL execution error for \(id) (record \(i+1)): \(error)")
                sqlite3_finalize(statement)
                return false
            }
            sqlite3_finalize(statement)
            print("   Successfully inserted record \(i+1): \(id)")
        }
        
        return true
    }
    
    func countRecords() -> Int {
        let query = "SELECT COUNT(*) FROM audio_chunks;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
            return -1
        }
        
        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }
        
        sqlite3_finalize(statement)
        return count
    }
    
    func countValidRecords() -> Int {
        let query = """
        SELECT COUNT(*) FROM audio_chunks 
        WHERE status IN ('pending', 'processing', 'completed', 'failed') 
        AND status != '';
        """
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
            return -1
        }
        
        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }
        
        sqlite3_finalize(statement)
        return count
    }
    
    func cleanupCorruptedChunkData() -> Int {
        let deleteQuery = """
        DELETE FROM audio_chunks 
        WHERE status = '' OR status IS NULL OR 
              status NOT IN ('pending', 'processing', 'completed', 'failed');
        """
        
        if sqlite3_exec(db, deleteQuery, nil, nil, nil) == SQLITE_OK {
            return Int(sqlite3_changes(db))
        }
        return -1
    }
    
    func testDuplicateInsertion() -> Bool {
        let chunk = MockAudioChunk(
            id: "test-duplicate",
            filePath: "/tmp/test.wav",
            timestamp: Date(),
            sizeBytes: 2048
        )
        
        // First insertion should succeed
        let firstResult = saveChunkToDatabase(chunk)
        if !firstResult {
            return false
        }
        
        // Second insertion of same ID should be handled gracefully
        let secondResult = saveChunkToDatabase(chunk)
        
        // Should return true (handled gracefully) but not create duplicate
        return secondResult && countRecords() > 0
    }
    
    func saveChunkToDatabase(_ chunk: MockAudioChunk) -> Bool {
        // Check if chunk already exists
        let checkQuery = "SELECT COUNT(*) FROM audio_chunks WHERE id = ?;"
        var checkStatement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, checkQuery, -1, &checkStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(checkStatement, 1, (chunk.id as NSString).utf8String, -1, nil)
            
            if sqlite3_step(checkStatement) == SQLITE_ROW {
                let count = sqlite3_column_int(checkStatement, 0)
                if count > 0 {
                    sqlite3_finalize(checkStatement)
                    return true // Already exists, consider successful
                }
            }
            sqlite3_finalize(checkStatement)
        }
        
        let insertQuery = """
        INSERT INTO audio_chunks (id, file_path, timestamp, status, retry_count, 
                                 transcription_result, error_message, created_at, 
                                 size_bytes, duration_seconds)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) != SQLITE_OK {
            return false
        }
        
        sqlite3_bind_text(statement, 1, (chunk.id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(statement, 2, (chunk.filePath as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 3, chunk.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(statement, 4, (chunk.status.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_int(statement, 5, Int32(chunk.retryCount))
        sqlite3_bind_null(statement, 6) // transcription_result
        sqlite3_bind_null(statement, 7) // error_message
        sqlite3_bind_double(statement, 8, chunk.createdAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 9, Int32(chunk.sizeBytes))
        
        if let duration = chunk.durationSeconds {
            sqlite3_bind_double(statement, 10, duration)
        } else {
            sqlite3_bind_null(statement, 10)
        }
        
        let result = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        
        return result
    }
}

// Test runner
func runDatabaseIntegrityTests() {
    print("=== Database Integrity Tests ===")
    print()
    
    var testsPassed = 0
    var totalTests = 0
    
    // Test 1: Corrupted data cleanup
    totalTests += 1
    print("1. Testing corrupted data cleanup...")
    let db1 = MockDatabaseManager()
    
    // Insert corrupted data
    if !db1.insertCorruptedData() {
        print("❌ Failed to insert test data")
        return
    }
    
    let initialCount = db1.countRecords()
    let validCountBefore = db1.countValidRecords()
    print("   Initial records: \(initialCount)")
    print("   Valid records before cleanup: \(validCountBefore)")
    
    // Clean up corrupted data
    let deletedCount = db1.cleanupCorruptedChunkData()
    let finalCount = db1.countRecords()
    let validCountAfter = db1.countValidRecords()
    
    print("   Deleted corrupted records: \(deletedCount)")
    print("   Final records: \(finalCount)")
    print("   Valid records after cleanup: \(validCountAfter)")
    
    if deletedCount == 3 && finalCount == 1 && validCountAfter == 1 {
        print("✅ Test 1 PASSED: Corrupted data cleanup works correctly")
        testsPassed += 1
    } else {
        print("❌ Test 1 FAILED: Expected to delete 3 corrupted records, keep 1 valid")
    }
    print()
    
    // Test 2: Duplicate insertion handling
    totalTests += 1
    print("2. Testing duplicate insertion handling...")
    let db2 = MockDatabaseManager()
    
    if db2.testDuplicateInsertion() {
        print("✅ Test 2 PASSED: Duplicate insertions handled gracefully")
        testsPassed += 1
    } else {
        print("❌ Test 2 FAILED: Duplicate insertion handling failed")
    }
    print()
    
    // Test 3: Valid chunk insertion
    totalTests += 1
    print("3. Testing valid chunk insertion...")
    let db3 = MockDatabaseManager()
    
    let testChunk = MockAudioChunk(
        id: "valid-chunk-123",
        filePath: "/tmp/valid.wav",
        timestamp: Date(),
        sizeBytes: 4096,
        durationSeconds: 2.5
    )
    
    let insertResult = db3.saveChunkToDatabase(testChunk)
    let recordCount = db3.countRecords()
    let validCount = db3.countValidRecords()
    
    if insertResult && recordCount == 1 && validCount == 1 {
        print("✅ Test 3 PASSED: Valid chunk insertion works correctly")
        testsPassed += 1
    } else {
        print("❌ Test 3 FAILED: Valid chunk insertion failed")
        print("   Insert result: \(insertResult)")
        print("   Record count: \(recordCount)")
        print("   Valid count: \(validCount)")
    }
    print()
    
    // Summary
    print("=== Test Results ===")
    print("Tests passed: \(testsPassed)/\(totalTests)")
    if testsPassed == totalTests {
        print("🎉 All database integrity tests PASSED!")
    } else {
        print("⚠️  Some tests FAILED. Database issues may persist.")
    }
}

// Run the tests
runDatabaseIntegrityTests()