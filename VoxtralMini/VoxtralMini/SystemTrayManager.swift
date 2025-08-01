import Foundation
import AppKit
import SwiftUI

class SystemTrayManager: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    private var audioRecorder: AudioRecorder?
    private var voxtralService: VoxtralService?
    private var serverURL: String = "http://dev.local:9090/transcribe"
    private var isRecordingFromTray = false
    private var mainWindow: NSWindow?
    
    // Callback to trigger main app recording
    var onToggleRecording: (() -> Void)?
    
    override init() {
        super.init()
        // Don't setup status item here, do it in setupStatusItem() method
    }
    
    func cleanup() {
        // Remove status item when app terminates
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }
    
    func setupAudioRecorder(_ recorder: AudioRecorder) {
        self.audioRecorder = recorder
    }
    
    func setupVoxtralService(_ service: VoxtralService) {
        self.voxtralService = service
    }
    
    func setToggleRecordingCallback(_ callback: @escaping () -> Void) {
        self.onToggleRecording = callback
    }
    
    func setServerURL(_ url: String) {
        self.serverURL = url
    }
    
    func setupMainWindow(_ window: NSWindow) {
        self.mainWindow = window
    }
    
    // Called when the main window is closed by the user
    func mainWindowWasClosed() {
        print("SystemTrayManager notified that main window was closed")
        self.mainWindow = nil
        // Update the menu to reflect the closed state
        updateMenu()
    }
    
    func setupStatusItem() {
        // Remove existing status item if any
        if let existingItem = statusItem {
            NSStatusBar.system.removeStatusItem(existingItem)
        }
        
        // Create new status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let statusItem = statusItem, let button = statusItem.button else {
            print("Failed to create status item or button")
            return
        }
        
        // Set up the button
        button.title = "🎙️"
        button.action = #selector(statusItemClicked)
        button.target = self
        button.toolTip = "Voxtral Mini - Click for menu"
        
        print("System tray status item created successfully")
        
        // Set up the menu
        updateMenu()
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        
        // App title
        let titleItem = NSMenuItem(title: "Voxtral Mini", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Recording status
        let recordStatusItem = NSMenuItem(
            title: isRecordingFromTray ? "🔴 Recording..." : "⏹️ Not Recording",
            action: nil,
            keyEquivalent: ""
        )
        recordStatusItem.isEnabled = false
        menu.addItem(recordStatusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Show/Open main window
        let windowActionTitle = (mainWindow == nil || !(mainWindow?.isVisible ?? false)) ? "📱 Open VoxtralMini" : "📱 Show VoxtralMini"
        let windowItem = NSMenuItem(
            title: windowActionTitle,
            action: #selector(showMainWindow),
            keyEquivalent: "o"
        )
        windowItem.target = self
        menu.addItem(windowItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Start/Stop recording
        let recordActionTitle = isRecordingFromTray ? "⏹️ Stop Recording" : "🎙️ Start Recording"
        let recordItem = NSMenuItem(
            title: recordActionTitle,
            action: #selector(toggleRecording),
            keyEquivalent: "r"
        )
        recordItem.target = self
        menu.addItem(recordItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // About
        let aboutItem = NSMenuItem(
            title: "About",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func statusItemClicked() {
        // Show the menu when the status item is clicked
        statusItem?.button?.performClick(nil)
    }
    
    @objc private func toggleRecording() {
        // Use the main app's recording logic instead of separate system tray logic
        onToggleRecording?()
    }
    
    @objc private func showMainWindow() {
        if let window = mainWindow {
            // Window exists, bring it to front
            window.makeKeyAndOrderFront(nil)
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            print("Brought existing window to front")
        } else {
            // No window reference, try to find any application window
            let windows = NSApplication.shared.windows
            let appWindow = windows.first { window in
                // Filter out windows that are likely status bar windows based on their properties
                return window.title.isEmpty && window.frame.size.width < 500 && window.frame.size.height < 100 ? false : true
            }
            
            if let window = appWindow {
                mainWindow = window
                window.makeKeyAndOrderFront(nil)
                window.center()
                NSApp.activate(ignoringOtherApps: true)
                print("Found and showed application window")
            } else {
                // No window found, try to trigger the app's reopen behavior
                NSApp.delegate?.applicationShouldHandleReopen?(NSApp, hasVisibleWindows: false)
                print("Triggered app reopen behavior")
            }
        }
        
        // Update menu to reflect new window state
        updateMenu()
    }
    
    @objc private func showSettings() {
        // Use the standard macOS Settings window
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Voxtral Mini"
        alert.informativeText = "A minimalist macOS app for audio transcription\n\nVersion 1.0"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    private func showNotification(title: String, message: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = message
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    // Public method to update recording state from ContentView
    func updateRecordingState(isRecording: Bool) {
        // Update recording state from ContentView
        isRecordingFromTray = isRecording
        updateMenu()
    }
    
}
