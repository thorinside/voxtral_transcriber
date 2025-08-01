import Foundation
import SQLite3
import Combine

class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
    private let dbPath: String
    
    @Published var transcriptions: [Transcription] = []
    
    private init() {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let dbURL = URL(fileURLWithPath: documentsPath).appendingPathComponent("voxtral_mini.db")
        dbPath = dbURL.path
        
        setupDatabase()
        loadTranscriptions()
    }
    
    private func setupDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Error opening database")
            return
        }
        
        // Create transcriptions table if it doesn't exist
        let createTableQuery = """
        CREATE TABLE IF NOT EXISTS transcriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            timestamp DATETIME NOT NULL,
            duration REAL,
            audio_file_path TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """
        
        if sqlite3_exec(db, createTableQuery, nil, nil, nil) != SQLITE_OK {
            print("Error creating table: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        // Create index for faster queries by date
        let createIndexQuery = """
        CREATE INDEX IF NOT EXISTS idx_transcriptions_timestamp 
        ON transcriptions(timestamp);
        """
        
        if sqlite3_exec(db, createIndexQuery, nil, nil, nil) != SQLITE_OK {
            print("Error creating index: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    func saveTranscription(text: String, duration: Double? = nil, audioFilePath: String? = nil) -> Int64? {
        let timestamp = Date()
        let insertQuery = """
        INSERT INTO transcriptions (text, timestamp, duration, audio_file_path)
        VALUES (?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) != SQLITE_OK {
            print("Error preparing insert statement: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        
        // Bind parameters
        sqlite3_bind_text(statement, 1, (text as NSString).utf8String, -1, nil)
        sqlite3_bind_double(statement, 2, timestamp.timeIntervalSince1970)
        
        if let duration = duration {
            sqlite3_bind_double(statement, 3, duration)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        
        if let audioFilePath = audioFilePath {
            sqlite3_bind_text(statement, 4, (audioFilePath as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        
        if sqlite3_step(statement) != SQLITE_DONE {
            print("Error executing insert statement: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_finalize(statement)
            return nil
        }
        
        let rowId = sqlite3_last_insert_rowid(db)
        sqlite3_finalize(statement)
        
        // Reload transcriptions from database
        loadTranscriptions()
        
        return rowId
    }
    
    func loadTranscriptions() {
        let query = """
        SELECT id, text, timestamp, duration, audio_file_path, created_at
        FROM transcriptions
        ORDER BY timestamp DESC;
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
            print("Error preparing select statement: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        
        var newTranscriptions: [Transcription] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let text = String(cString: sqlite3_column_text(statement, 1))
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            
            let duration = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3)
            let audioFilePath = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 4))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            
            let transcription = Transcription(
                id: id,
                text: text,
                timestamp: timestamp,
                duration: duration,
                audioFilePath: audioFilePath,
                createdAt: createdAt
            )
            
            newTranscriptions.append(transcription)
        }
        
        sqlite3_finalize(statement)
        
        DispatchQueue.main.async {
            self.transcriptions = newTranscriptions
        }
    }
    
    func getTranscriptionsByDate() -> [String: [Transcription]] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        
        var groupedTranscriptions: [String: [Transcription]] = [:]
        
        for transcription in transcriptions {
            let dateKey = dateFormatter.string(from: transcription.timestamp)
            
            if groupedTranscriptions[dateKey] == nil {
                groupedTranscriptions[dateKey] = []
            }
            
            groupedTranscriptions[dateKey]?.append(transcription)
        }
        
        // Sort each day's transcriptions by time
        for (date, transcriptions) in groupedTranscriptions {
            groupedTranscriptions[date] = transcriptions.sorted { $0.timestamp > $1.timestamp }
        }
        
        return groupedTranscriptions
    }
    
    func deleteTranscription(id: Int64) -> Bool {
        let deleteQuery = "DELETE FROM transcriptions WHERE id = ?;"
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil) != SQLITE_OK {
            print("Error preparing delete statement: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        
        sqlite3_bind_int64(statement, 1, id)
        
        let success = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        
        if success {
            loadTranscriptions()
        }
        
        return success
    }
    
    func searchTranscriptions(query: String) -> [Transcription] {
        let searchQuery = """
        SELECT id, text, timestamp, duration, audio_file_path, created_at
        FROM transcriptions
        WHERE text LIKE ?
        ORDER BY timestamp DESC;
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, searchQuery, -1, &statement, nil) != SQLITE_OK {
            print("Error preparing search statement: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        
        let searchTerm = "%\(query)%"
        sqlite3_bind_text(statement, 1, (searchTerm as NSString).utf8String, -1, nil)
        
        var results: [Transcription] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let text = String(cString: sqlite3_column_text(statement, 1))
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            
            let duration = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3)
            let audioFilePath = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 4))
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
            
            let transcription = Transcription(
                id: id,
                text: text,
                timestamp: timestamp,
                duration: duration,
                audioFilePath: audioFilePath,
                createdAt: createdAt
            )
            
            results.append(transcription)
        }
        
        sqlite3_finalize(statement)
        return results
    }
    
    deinit {
        sqlite3_close(db)
    }
}

struct Transcription: Identifiable, Codable {
    var id: Int64
    var text: String
    var timestamp: Date
    var duration: Double?
    var audioFilePath: String?
    var createdAt: Date
}
