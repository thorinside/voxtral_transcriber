import SwiftUI
import AppKit

struct SettingsView: View {
    @Binding var serverURL: String
    @State private var testStatus: TestStatus = .idle
    @StateObject private var voxtralService = VoxtralService()
    @State private var selectedSection: SettingsSection? = .general
    
    enum TestStatus: Equatable {
        case idle
        case testing
        case success
        case failure(String)
    }
    
    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case server = "Server"
        case about = "About"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .server: return "network"
            case .about: return "info.circle"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label(section.rawValue, systemImage: section.icon)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            // Detail View
            Group {
                switch selectedSection {
                case .general:
                    generalSettingsView
                case .server:
                    serverSettingsView
                case .about:
                    aboutSettingsView
                case .none:
                    EmptyView()
                }
            }
            .navigationTitle(selectedSection?.rawValue ?? "Settings")
            .frame(minWidth: 600, minHeight: 400)
        }
        .frame(minWidth: 800, idealWidth: 900, minHeight: 500, idealHeight: 600)
    }
    
    // MARK: - Settings Views
    
    @ViewBuilder
    private var generalSettingsView: some View {
        Form {
            GroupBox {
                VStack(alignment: .leading, spacing: 20) {
                    // Header section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.accentColor)
                                .font(.title2)
                            Text("Application Settings")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        
                        Text("General application preferences and data storage information.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Database section
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(getDatabasePath())
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                    .foregroundColor(.primary)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                                    .accessibilityLabel("Database file path")
                                    .accessibilityValue(getDatabasePath())
                                
                                HStack {
                                    Image(systemName: "lock.shield.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text("All transcriptions are stored locally on your device for complete privacy.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.top, 4)
                            }
                        } label: {
                            Text("Database Location")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }
    
    @ViewBuilder
    private var serverSettingsView: some View {
        Form {
            GroupBox {
                VStack(alignment: .leading, spacing: 20) {
                    // Header section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "network")
                                .foregroundColor(.accentColor)
                                .font(.title2)
                            Text("Transcription Service")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        
                        Text("Configure the connection to your local Voxtral transcription service. The service should accept POST requests with WAV audio data.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Divider()
                    
                    // Server URL section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Server URL")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TextField("http://localhost:8080/transcribe", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .onChange(of: serverURL) { _, _ in
                                testStatus = .idle
                            }
                            .accessibilityLabel("Server URL")
                            .accessibilityHint("Enter the URL of your Voxtral transcription service")
                    }
                    
                    // Test connection section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button(action: testConnection) {
                                HStack(spacing: 6) {
                                    if testStatus == .testing {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "network.badge.shield.half.filled")
                                    }
                                    Text(testStatus == .testing ? "Testing..." : "Test Connection")
                                }
                            }
                            .disabled(serverURL.isEmpty || testStatus == .testing)
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Test connection to server")
                            .accessibilityHint("Verify that the server URL is reachable and responding")
                            
                            Spacer()
                        }
                        
                        // Status display
                        if testStatus != .idle {
                            enhancedTestStatusView
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }
    
    @ViewBuilder
    private var aboutSettingsView: some View {
        Form {
            GroupBox {
                VStack(alignment: .leading, spacing: 20) {
                    // App icon and title section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 16) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.linearGradient(
                                    colors: [.accentColor, .accentColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .accessibilityHidden(true)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Voxtral Mini")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .accessibilityAddTraits(.isHeader)
                                
                                Text("Version 1.0")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                    .accessibilityLabel("Version 1.0")
                                
                                Text("© 2024")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    
                    Divider()
                    
                    // Description section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(.accentColor)
                                .font(.headline)
                            Text("About This App")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        Text("A minimalist macOS application for real-time audio transcription using local AI services. Features include microphone capture with visual feedback, searchable transcription history, and convenient system tray integration for seamless workflow integration.")
                            .font(.body)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                    
                    Divider()
                    
                    // Privacy section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .foregroundColor(.green)
                                .font(.headline)
                            Text("Privacy & Security")
                                .font(.headline)
                                .fontWeight(.semibold)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("All audio processing happens locally on your device")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Transcriptions are stored in your local database")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("No data is sent to external servers or cloud services")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }
    
    @ViewBuilder
    private var enhancedTestStatusView: some View {
        switch testStatus {
        case .idle:
            EmptyView()
            
        case .testing:
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.9)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Testing Connection")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Verifying server availability...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .accessibilityLabel("Testing connection in progress")
            
        case .success:
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection Successful")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                    Text("Server is responding correctly")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.green.opacity(0.1))
            .cornerRadius(8)
            .accessibilityLabel("Connection successful")
            .accessibilityValue("Server is responding correctly")
            
        case .failure(let error):
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection Failed")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
            .accessibilityLabel("Connection failed")
            .accessibilityValue(error)
        }
    }
    
    @ViewBuilder
    private var testStatusView: some View {
        switch testStatus {
        case .idle:
            EmptyView()
            
        case .testing:
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Testing connection...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
        case .success:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Connection successful")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
        case .failure(let error):
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Connection failed: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    private func testConnection() {
        testStatus = .testing
        
        Task {
            do {
                let success = try await voxtralService.testConnection(serverURL: serverURL)
                DispatchQueue.main.async {
                    self.testStatus = success ? .success : .failure("Invalid response")
                }
            } catch {
                DispatchQueue.main.async {
                    self.testStatus = .failure(error.localizedDescription)
                }
            }
        }
    }
    
    private func getDatabasePath() -> String {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        return "\(documentsPath)/voxtral_mini.db"
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(
            serverURL: .constant("http://localhost:8080/transcribe")
        )
    }
}
