import SwiftUI
import AVFoundation
import AppKit

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var voxtralService = VoxtralService()
    @StateObject private var databaseManager = DatabaseManager.shared
    @State private var isRecording = false
    @State private var transcriptionChunks: [TranscriptionChunk] = []
    @State private var serverURL = "http://dev.local:9090/transcribe"
    @State private var selectedDate: String?
    @State private var selectedTranscription: Transcription?
    @State private var searchQuery = ""
    @EnvironmentObject var systemTrayManager: SystemTrayManager
    
    private var groupedTranscriptions: [String: [Transcription]] {
        if searchQuery.isEmpty {
            return databaseManager.getTranscriptionsByDate()
        } else {
            let searchResults = databaseManager.searchTranscriptions(query: searchQuery)
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .none
            
            var grouped: [String: [Transcription]] = [:]
            for transcription in searchResults {
                let dateKey = dateFormatter.string(from: transcription.timestamp)
                if grouped[dateKey] == nil {
                    grouped[dateKey] = []
                }
                grouped[dateKey]?.append(transcription)
            }
            return grouped
        }
    }
    
    var body: some View {
        NavigationView {
            // Sidebar
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Voxtral Mini")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search transcriptions...", text: $searchQuery)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding()
                
                Divider()
                
                // Transcription List
                List {
                    ForEach(groupedTranscriptions.keys.sorted(by: { $0 > $1 }), id: \.self) { date in
                        Section(header: Text(date).font(.subheadline).fontWeight(.semibold)) {
                            ForEach(groupedTranscriptions[date] ?? []) { transcription in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(formatTime(transcription.timestamp))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        if let duration = transcription.duration {
                                            Text(formatDuration(duration))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Text(transcription.text)
                                        .font(.body)
                                        .lineLimit(2)
                                        .foregroundColor(selectedTranscription?.id == transcription.id ? .accentColor : .primary)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedTranscription = transcription
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedTranscription?.id == transcription.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                )
                            }
                        }
                    }
                }
                .listStyle(SidebarListStyle())
                
                Spacer()
                
                // Recording Controls
                VStack(spacing: 15) {
                    // Microphone Status Indicator
                    VStack {
                        Circle()
                            .fill(audioRecorder.isRecording ? Color.red : Color.gray)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                            )
                            .scaleEffect(audioRecorder.isRecording ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: audioRecorder.isRecording)
                        
                        Text(audioRecorder.isRecording ? "Recording..." : "Ready")
                            .font(.caption)
                            .foregroundColor(audioRecorder.isRecording ? .red : .secondary)
                    }
                    
                    // Record Button
                    Button(action: toggleRecording) {
                        HStack {
                            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            Text(isRecording ? "Stop" : "Record")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isRecording ? Color.red : Color.blue)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(audioRecorder.permissionDenied)
                    
                    // Permission Status
                    if audioRecorder.permissionDenied {
                        VStack(spacing: 5) {
                            Text("Microphone access denied")
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                            
                            Button(action: openSystemPreferencesForMicrophone) {
                                Text("Enable in Settings")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(minWidth: 280)
            
            // Main Content Area
            VStack(spacing: 0) {
                if let transcription = selectedTranscription {
                    // Selected Transcription View
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Transcription")
                                    .font(.title)
                                    .fontWeight(.bold)
                                
                                HStack {
                                    Text(formatFullDateTime(transcription.timestamp))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    if let duration = transcription.duration {
                                        Text("•")
                                            .foregroundColor(.secondary)
                                        Text(formatDuration(duration))
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            
                            Button(action: {
                                // Copy to clipboard
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(transcription.text, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Copy to clipboard")
                            
                            Button(action: {
                                if let id = selectedTranscription?.id {
                                    _ = databaseManager.deleteTranscription(id: id)
                                    selectedTranscription = nil
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Delete transcription")
                        }
                        
                        Divider()
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(transcription.text)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .padding()
                            }
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !transcriptionChunks.isEmpty {
                    // Live Transcription View
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Live Transcription")
                                .font(.title)
                                .fontWeight(.bold)
                            Spacer()
                            Button(action: {
                                transcriptionChunks.removeAll()
                            }) {
                                Image(systemName: "clear")
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Clear transcription")
                        }
                        
                        Divider()
                        
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 8) {
                                ForEach(transcriptionChunks) { chunk in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(formatTime(chunk.timestamp))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .frame(width: 60, alignment: .leading)
                                        
                                        Text(chunk.text)
                                            .font(.body)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 8)
                                            .background(chunk.text.contains("Error") ? Color.red.opacity(0.1) : Color.blue.opacity(0.05))
                                            .cornerRadius(6)
                                    }
                                    .padding(.horizontal, 4)
                                }
                            }
                            .padding()
                        }
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Empty State
                    VStack(spacing: 20) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Active Transcription")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        Text("Start recording or select a transcription from the sidebar")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .onAppear {
            audioRecorder.requestPermission()
            
            // Set up the system tray manager with audio recorder and service
            systemTrayManager.setupAudioRecorder(audioRecorder)
            systemTrayManager.setupVoxtralService(voxtralService)
            systemTrayManager.setServerURL(serverURL)
            systemTrayManager.setToggleRecordingCallback(toggleRecording)
        }
        .onChange(of: audioRecorder.audioData) { _, newData in
            if newData != nil && isRecording {
                // Send final audio data to transcription service
                Task {
                    await sendAudioForTranscription(newData!)
                }
            }
        }
        .onChange(of: serverURL) { _, newURL in
            systemTrayManager.setServerURL(newURL)
        }
        .onChange(of: audioRecorder.audioChunk) { _, newChunk in
            if newChunk != nil && isRecording {
                // Send audio chunk to transcription service
                Task {
                    await sendAudioForTranscription(newChunk!)
                }
            }
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            audioRecorder.stopRecording()
            isRecording = false
            systemTrayManager.updateRecordingState(isRecording: false)
            
            // Save the transcription to database when stopping
            saveCurrentTranscription()
        } else {
            audioRecorder.startRecording()
            isRecording = true
            transcriptionChunks.removeAll()
            systemTrayManager.updateRecordingState(isRecording: true)
        }
    }
    
    private func saveCurrentTranscription() {
        guard !transcriptionChunks.isEmpty else { return }
        
        // Combine all chunks into a single transcription
        let fullText = transcriptionChunks.map { $0.text }.joined(separator: " ")
        
        // Calculate duration (from first to last chunk)
        let duration = transcriptionChunks.last?.timestamp.timeIntervalSince(transcriptionChunks.first?.timestamp ?? Date()) ?? 0
        
        // Save to database
        _ = databaseManager.saveTranscription(
            text: fullText,
            duration: duration,
            audioFilePath: nil
        )
        
        // Clear current transcription chunks
        transcriptionChunks.removeAll()
    }
    
    private func sendAudioForTranscription(_ audioData: Data) async {
        print("Sending audio data for transcription. Size: \(audioData.count) bytes")
        do {
            let result = try await voxtralService.transcribe(audioData: audioData, serverURL: serverURL)
            DispatchQueue.main.async {
                if !result.isEmpty {
                    print("Transcription received: \(result)")
                    self.addTranscriptionChunk(result)
                } else {
                    print("Received empty transcription result")
                }
            }
        } catch {
            print("Transcription error: \(error)")
            DispatchQueue.main.async {
                self.addTranscriptionChunk("Error: \(error.localizedDescription)")
            }
        }
    }
    
    private func addTranscriptionChunk(_ text: String) {
        let newChunk = TranscriptionChunk(text: text, timestamp: Date())
        
        // Apply deduplication with the previous chunk
        if let lastChunk = transcriptionChunks.last {
            let dedupedText = deduplicateText(lastChunk.text, newChunk.text)
            if dedupedText != newChunk.text {
                // Create a deduped version of the new chunk
                let dedupedChunk = TranscriptionChunk(text: dedupedText, timestamp: newChunk.timestamp)
                transcriptionChunks.append(dedupedChunk)
                print("Applied deduplication: '\(newChunk.text)' -> '\(dedupedText)'")
            } else {
                transcriptionChunks.append(newChunk)
            }
        } else {
            transcriptionChunks.append(newChunk)
        }
    }
    
    private func deduplicateText(_ previousText: String, _ newText: String) -> String {
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
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func formatFullDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func openSystemPreferencesForMicrophone() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SystemTrayManager())
    }
}

struct TranscriptionChunk: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let isDeduped: Bool
    
    init(text: String, timestamp: Date, isDeduped: Bool = false) {
        self.text = text
        self.timestamp = timestamp
        self.isDeduped = isDeduped
    }
}
