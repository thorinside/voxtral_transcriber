import Foundation
import SQLite3
import Combine

// MARK: - Audio Chunk Management Classes

enum AudioChunkStatus: String, CaseIterable {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
}

struct AudioChunk {
    let id: String
    let filePath: String
    let timestamp: Date
    let status: AudioChunkStatus
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
}

class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
    private let dbPath: String
    
    // Provide access to database connection for AudioChunkStore
    func getDatabase() -> OpaquePointer? {
        return db
    }
    
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
        
        // Create audio_chunks table for persistent chunk storage
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
        
        if sqlite3_exec(db, createChunksTableQuery, nil, nil, nil) != SQLITE_OK {
            print("Error creating audio_chunks table: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        // Create index for faster queries by date
        let createIndexQuery = """
        CREATE INDEX IF NOT EXISTS idx_transcriptions_timestamp 
        ON transcriptions(timestamp);
        """
        
        if sqlite3_exec(db, createIndexQuery, nil, nil, nil) != SQLITE_OK {
            print("Error creating index: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        // Create indexes for audio_chunks table
        let createChunkIndexes = """
        CREATE INDEX IF NOT EXISTS idx_audio_chunks_status ON audio_chunks(status);
        CREATE INDEX IF NOT EXISTS idx_audio_chunks_timestamp ON audio_chunks(timestamp);
        CREATE INDEX IF NOT EXISTS idx_audio_chunks_retry ON audio_chunks(status, last_retry_at);
        """
        
        if sqlite3_exec(db, createChunkIndexes, nil, nil, nil) != SQLITE_OK {
            print("Error creating audio_chunks indexes: \(String(cString: sqlite3_errmsg(db)))")
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
    
    func updateTranscription(id: Int64, text: String, duration: Double? = nil, audioFilePath: String? = nil) -> Bool {
        let updateQuery = """
        UPDATE transcriptions SET text = ?, duration = ?, audio_file_path = ?
        WHERE id = ?;
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) != SQLITE_OK {
            print("Error preparing update statement: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        
        // Bind parameters
        sqlite3_bind_text(statement, 1, (text as NSString).utf8String, -1, nil)
        
        if let duration = duration {
            sqlite3_bind_double(statement, 2, duration)
        } else {
            sqlite3_bind_null(statement, 2)
        }
        
        if let audioFilePath = audioFilePath {
            sqlite3_bind_text(statement, 3, (audioFilePath as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        
        sqlite3_bind_int64(statement, 4, id)
        
        let success = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        
        if success {
            // Reload transcriptions from database
            loadTranscriptions()
        }
        
        return success
    }
    
    func loadTranscriptions() {
        let query = """
        SELECT id, text, timestamp, duration, audio_file_path, created_at
        FROM transcriptions
        ORDER BY created_at DESC;
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
        ORDER BY created_at DESC;
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

// MARK: - AudioChunkStore Implementation

class AudioChunkStore: ObservableObject {
    static let shared = AudioChunkStore()
    
    @Published var pendingChunks: [AudioChunk] = []
    @Published var processingChunks: [AudioChunk] = []
    @Published var failedChunks: [AudioChunk] = []
    
    private var db: OpaquePointer? {
        return DatabaseManager.shared.getDatabase()
    }
    
    private let audioChunksDirectory: URL
    
    private init() {
        // Create audio chunks directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        audioChunksDirectory = documentsPath.appendingPathComponent("audio_chunks")
        
        createAudioChunksDirectory()
        loadChunks()
    }
    
    private func createAudioChunksDirectory() {
        do {
            try FileManager.default.createDirectory(at: audioChunksDirectory, 
                                                  withIntermediateDirectories: true, 
                                                  attributes: nil)
        } catch {
            print("Error creating audio chunks directory: \(error)")
        }
    }
    
    // MARK: - Public Interface
    
    func storeAudioChunk(audioData: Data, timestamp: Date, estimatedDuration: Double? = nil) -> String {
        let chunkId = UUID().uuidString
        let fileName = "\(chunkId).wav"
        let filePath = audioChunksDirectory.appendingPathComponent(fileName)
        
        do {
            // Write audio data to file
            try audioData.write(to: filePath)
            
            // Save metadata to database
            let chunk = AudioChunk(
                id: chunkId,
                filePath: filePath.path,
                timestamp: timestamp,
                sizeBytes: audioData.count,
                durationSeconds: estimatedDuration
            )
            
            if saveChunkToDatabase(chunk) {
                print("Stored audio chunk: \(chunkId), size: \(audioData.count) bytes")
                DispatchQueue.main.async {
                    self.pendingChunks.append(chunk)
                }
                return chunkId
            } else {
                // Clean up file if database save failed
                try? FileManager.default.removeItem(at: filePath)
                print("Failed to save chunk metadata to database")
                return ""
            }
        } catch {
            print("Error storing audio chunk: \(error)")
            return ""
        }
    }
    
    func updateChunkStatus(_ chunkId: String, status: AudioChunkStatus, 
                          transcriptionResult: String? = nil, errorMessage: String? = nil) {
        let updateQuery = """
        UPDATE audio_chunks SET 
            status = ?, 
            transcription_result = ?, 
            error_message = ?,
            retry_count = CASE WHEN ? = 'failed' THEN retry_count + 1 ELSE retry_count END,
            last_retry_at = CASE WHEN ? = 'failed' THEN ? ELSE last_retry_at END
        WHERE id = ?;
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateQuery, -1, &statement, nil) != SQLITE_OK {
            print("Error preparing update statement: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        
        sqlite3_bind_text(statement, 1, status.rawValue, -1, nil)
        
        if let result = transcriptionResult {
            sqlite3_bind_text(statement, 2, result, -1, nil)
        } else {
            sqlite3_bind_null(statement, 2)
        }
        
        if let error = errorMessage {
            sqlite3_bind_text(statement, 3, error, -1, nil)
        } else {
            sqlite3_bind_null(statement, 3)
        }
        
        sqlite3_bind_text(statement, 4, status.rawValue, -1, nil)
        sqlite3_bind_text(statement, 5, status.rawValue, -1, nil)
        sqlite3_bind_double(statement, 6, Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 7, chunkId, -1, nil)
        
        if sqlite3_step(statement) != SQLITE_DONE {
            print("Error updating chunk status: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            print("Updated chunk \(chunkId) status to \(status.rawValue)")
        }
        
        sqlite3_finalize(statement)
        
        // Reload chunks to update UI
        DispatchQueue.main.async {
            self.loadChunks()
        }
    }
    
    func getPendingChunks() -> [AudioChunk] {
        return loadChunksWithStatus(.pending)
    }
    
    func getFailedChunks() -> [AudioChunk] {
        return loadChunksWithStatus(.failed)
    }
    
    func deleteChunk(_ chunkId: String) {
        // First get the chunk to find the file path
        if let chunk = getChunk(chunkId) {
            // Delete the audio file
            let fileURL = URL(fileURLWithPath: chunk.filePath)
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Delete from database
        let deleteQuery = "DELETE FROM audio_chunks WHERE id = ?;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, deleteQuery, -1, &statement, nil) != SQLITE_OK {
            print("Error preparing delete statement: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        
        sqlite3_bind_text(statement, 1, chunkId, -1, nil)
        
        if sqlite3_step(statement) != SQLITE_DONE {
            print("Error deleting chunk: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            print("Deleted chunk: \(chunkId)")
        }
        
        sqlite3_finalize(statement)
        
        // Reload chunks to update UI
        DispatchQueue.main.async {
            self.loadChunks()
        }
    }
    
    func cleanupCompletedChunks(olderThan timeInterval: TimeInterval = 24 * 60 * 60) {
        let cutoffTime = Date().addingTimeInterval(-timeInterval)
        
        // Get completed chunks older than cutoff
        let query = """
        SELECT id, file_path FROM audio_chunks 
        WHERE status = 'completed' AND created_at < ?;
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
            print("Error preparing cleanup query: \(String(cString: sqlite3_errmsg(db)))")
            return
        }
        
        sqlite3_bind_double(statement, 1, cutoffTime.timeIntervalSince1970)
        
        var chunksToDelete: [(String, String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(statement, 0))
            let filePath = String(cString: sqlite3_column_text(statement, 1))
            chunksToDelete.append((id, filePath))
        }
        
        sqlite3_finalize(statement)
        
        // Delete the chunks
        for (chunkId, filePath) in chunksToDelete {
            // Delete file
            let fileURL = URL(fileURLWithPath: filePath)
            try? FileManager.default.removeItem(at: fileURL)
            
            // Delete from database
            deleteChunk(chunkId)
        }
        
        if !chunksToDelete.isEmpty {
            print("Cleaned up \(chunksToDelete.count) completed audio chunks")
        }
    }
    
    // MARK: - Private Methods
    
    private func saveChunkToDatabase(_ chunk: AudioChunk) -> Bool {
        let insertQuery = """
        INSERT INTO audio_chunks (id, file_path, timestamp, status, retry_count, 
                                 transcription_result, error_message, created_at, 
                                 size_bytes, duration_seconds)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertQuery, -1, &statement, nil) != SQLITE_OK {
            print("Error preparing insert statement: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        
        sqlite3_bind_text(statement, 1, chunk.id, -1, nil)
        sqlite3_bind_text(statement, 2, chunk.filePath, -1, nil)
        sqlite3_bind_double(statement, 3, chunk.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(statement, 4, chunk.status.rawValue, -1, nil)
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
    
    private func loadChunks() {
        pendingChunks = loadChunksWithStatus(.pending)
        processingChunks = loadChunksWithStatus(.processing)
        failedChunks = loadChunksWithStatus(.failed)
    }
    
    private func loadChunksWithStatus(_ status: AudioChunkStatus) -> [AudioChunk] {
        let query = """
        SELECT id, file_path, timestamp, status, retry_count, last_retry_at,
               transcription_result, error_message, created_at, size_bytes, duration_seconds
        FROM audio_chunks WHERE status = ? ORDER BY timestamp ASC;
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
            print("Error preparing select statement: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        
        sqlite3_bind_text(statement, 1, status.rawValue, -1, nil)
        
        var chunks: [AudioChunk] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let chunk = parseChunkFromStatement(statement) {
                chunks.append(chunk)
            }
        }
        
        sqlite3_finalize(statement)
        return chunks
    }
    
    private func getChunk(_ chunkId: String) -> AudioChunk? {
        let query = """
        SELECT id, file_path, timestamp, status, retry_count, last_retry_at,
               transcription_result, error_message, created_at, size_bytes, duration_seconds
        FROM audio_chunks WHERE id = ?;
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) != SQLITE_OK {
            print("Error preparing select statement: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        
        sqlite3_bind_text(statement, 1, chunkId, -1, nil)
        
        var chunk: AudioChunk? = nil
        if sqlite3_step(statement) == SQLITE_ROW {
            chunk = parseChunkFromStatement(statement)
        }
        
        sqlite3_finalize(statement)
        return chunk
    }
    
    private func parseChunkFromStatement(_ statement: OpaquePointer?) -> AudioChunk? {
        guard let stmt = statement else { return nil }
        
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let filePath = String(cString: sqlite3_column_text(stmt, 1))
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        let statusString = String(cString: sqlite3_column_text(stmt, 3))
        let retryCount = Int(sqlite3_column_int(stmt, 4))
        
        let lastRetryAt: Date? = {
            if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
                return Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            }
            return nil
        }()
        
        let transcriptionResult: String? = {
            if sqlite3_column_type(stmt, 6) != SQLITE_NULL {
                return String(cString: sqlite3_column_text(stmt, 6))
            }
            return nil
        }()
        
        let errorMessage: String? = {
            if sqlite3_column_type(stmt, 7) != SQLITE_NULL {
                return String(cString: sqlite3_column_text(stmt, 7))
            }
            return nil
        }()
        
        let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8))
        let sizeBytes = Int(sqlite3_column_int(stmt, 9))
        
        let durationSeconds: Double? = {
            if sqlite3_column_type(stmt, 10) != SQLITE_NULL {
                return sqlite3_column_double(stmt, 10)
            }
            return nil
        }()
        
        guard let status = AudioChunkStatus(rawValue: statusString) else {
            print("Unknown status: \(statusString)")
            return nil
        }
        
        return AudioChunk(
            id: id,
            filePath: filePath,
            timestamp: timestamp,
            sizeBytes: sizeBytes,
            durationSeconds: durationSeconds
        )
    }
}
