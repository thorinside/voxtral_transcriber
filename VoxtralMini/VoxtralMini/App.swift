import SwiftUI

@main
struct VoxtralMiniApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.systemTrayManager)
        }
        .windowStyle(DefaultWindowStyle())
        
        Settings {
            SettingsView(serverURL: .constant("http://dev.local:9090/transcribe"))
        }
        
        .commands {
            // Remove default "New" menu item
            CommandGroup(replacing: .newItem) {
                EmptyView()
            }
            
            // Add About to the Application menu
            CommandGroup(replacing: .appInfo) {
                Button("About Voxtral Mini") {
                    appDelegate.showAboutDialog()
                }
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let systemTrayManager = SystemTrayManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up the app to run in background but still show in dock
        NSApp.setActivationPolicy(.regular)
        
        // Ensure the system tray is properly set up
        DispatchQueue.main.async {
            self.systemTrayManager.setupStatusItem()
        }
        
        // Show the main window initially and pass reference to system tray
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let window = NSApplication.shared.mainWindow {
                self.systemTrayManager.setupMainWindow(window)
                window.makeKeyAndOrderFront(nil)
                window.center()
                NSApp.activate(ignoringOtherApps: true)
                
                // Set up window delegate to detect when window is closed
                window.delegate = self
            }
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // Show the main window if no windows are visible
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let window = NSApplication.shared.mainWindow {
                    self.systemTrayManager.setupMainWindow(window)
                    window.makeKeyAndOrderFront(nil)
                    window.center()
                    NSApp.activate(ignoringOtherApps: true)
                    
                    // Set up window delegate if not already set
                    if window.delegate == nil {
                        window.delegate = self
                    }
                } else {
                    // If no main window, try to find any application window
                    let windows = NSApplication.shared.windows
                    let appWindow = windows.first { window in
                        // Filter out windows that are likely status bar windows based on their properties
                        return window.title.isEmpty && window.frame.size.width < 500 && window.frame.size.height < 100 ? false : true
                    }
                    
                    if let window = appWindow {
                        self.systemTrayManager.setupMainWindow(window)
                        window.makeKeyAndOrderFront(nil)
                        window.center()
                        NSApp.activate(ignoringOtherApps: true)
                        
                        // Set up window delegate if not already set
                        if window.delegate == nil {
                            window.delegate = self
                        }
                    }
                }
            }
        }
        return true
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up system tray when app terminates
        systemTrayManager.cleanup()
    }
    
    func showAboutDialog() {
        let alert = NSAlert()
        alert.messageText = "Voxtral Mini"
        alert.informativeText = "A minimalist macOS app for audio transcription\n\nVersion 1.0"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// Extend AppDelegate to handle window delegate methods
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        print("Main window closed by user")
        // Notify system tray manager that the main window was closed
        systemTrayManager.mainWindowWasClosed()
        
        // Optionally, you can change the app's activation policy here if desired
        // NSApp.setActivationPolicy(.accessory)
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Update the window reference when window becomes key
        if let window = notification.object as? NSWindow {
            systemTrayManager.setupMainWindow(window)
        }
    }
}
