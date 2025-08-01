#!/usr/bin/env swift

import Foundation
import SQLite3

// Simple database test to isolate the issue
func testDatabaseOperations() {
    print("=== Simple Database Test ===")
    
    // Create a temporary database
    let tempPath = NSTemporaryDirectory() + "simple_test_\(UUID().uuidString).db"
    var db: OpaquePointer?
    
    // Open database
    if sqlite3_open(tempPath, &db) != SQLITE_OK {
        print("❌ Failed to open database")
        return
    }
    
    defer {
        sqlite3_close(db)
        try? FileManager.default.removeItem(atPath: tempPath)
    }
    
    // Create table
    let createTable = """
    CREATE TABLE test_chunks (
        id TEXT PRIMARY KEY,
        status TEXT NOT NULL
    );
    """
    
    if sqlite3_exec(db, createTable, nil, nil, nil) != SQLITE_OK {
        print("❌ Failed to create table")
        return
    }
    
    print("✅ Database and table created successfully")
    
    // Test inserting records
    let insertQuery = "INSERT INTO test_chunks (id, status) VALUES (?, ?);"
    
    // Generate unique IDs for each test record
    let testData = [
        ("test-1-\(UUID().uuidString)", ""),
        ("test-2-\(UUID().uuidString)", "pending"),
        ("test-3-\(UUID().uuidString)", "invalid"),
    ]
    
    print("Test data to insert:")
    for (i, (id, status)) in testData.enumerated() {
        print("  Record \(i+1): ID='\(id)', Status='\(status)'")
    }
    
    for (i, (id, status)) in testData.enumerated() {
        // Check if ID already exists first
        let checkQuery = "SELECT id FROM test_chunks WHERE id = ?;"
        var checkStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, checkQuery, -1, &checkStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(checkStmt, 1, (id as NSString).utf8String, -1, nil)
            if sqlite3_step(checkStmt) == SQLITE_ROW {
                let existingId = String(cString: sqlite3_column_text(checkStmt, 0))
                print("  ⚠️ ID '\(id)' already exists as '\(existingId)'")
            }
            sqlite3_finalize(checkStmt)
        }
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertQuery, -1, &stmt, nil) != SQLITE_OK {
            print("❌ Failed to prepare statement for record \(i+1)")
            continue
        }
        
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (status as NSString).utf8String, -1, nil)
        
        if sqlite3_step(stmt) == SQLITE_DONE {
            print("✅ Inserted record \(i+1): \(id) with status '\(status)'")
        } else {
            let error = String(cString: sqlite3_errmsg(db))
            print("❌ Failed to insert record \(i+1) (\(id)): \(error)")
        }
        
        sqlite3_finalize(stmt)
    }
    
    // Count records
    let countQuery = "SELECT COUNT(*) FROM test_chunks;"
    var countStmt: OpaquePointer?
    
    if sqlite3_prepare_v2(db, countQuery, -1, &countStmt, nil) == SQLITE_OK {
        if sqlite3_step(countStmt) == SQLITE_ROW {
            let count = sqlite3_column_int(countStmt, 0)
            print("📊 Total records in database: \(count)")
        }
        sqlite3_finalize(countStmt)
    }
    
    // Test cleanup
    let cleanupQuery = "DELETE FROM test_chunks WHERE status = '' OR status = 'invalid';"
    if sqlite3_exec(db, cleanupQuery, nil, nil, nil) == SQLITE_OK {
        let deleted = sqlite3_changes(db)
        print("🧹 Cleaned up \(deleted) corrupted records")
    }
    
    // Final count
    if sqlite3_prepare_v2(db, countQuery, -1, &countStmt, nil) == SQLITE_OK {
        if sqlite3_step(countStmt) == SQLITE_ROW {
            let count = sqlite3_column_int(countStmt, 0)
            print("📊 Records after cleanup: \(count)")
        }
        sqlite3_finalize(countStmt)
    }
    
    print("✅ Simple database test completed successfully")
}

testDatabaseOperations()