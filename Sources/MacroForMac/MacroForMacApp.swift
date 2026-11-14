import AppKit
import SwiftUI
import MacroCore

@main
struct MacroForMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState.shared

    var body: some Scene {
        Window("MacroForMac", id: "main") {
            ContentView()
                .environmentObject(app)
        }
        .defaultSize(width: 1100, height: 680)
        .commands {
            MacroCommands(app: app)
        }

        Settings {
            SettingsView()
                .environmentObject(app)
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(app)
        } label: {
            Image(systemName: menuBarSymbol)
        }
    }

    private var menuBarSymbol: String {
        if app.isRecording { return "record.circle" }
        if app.runningMacroID != nil { return "play.circle.fill" }
        return "bolt.horizontal.circle"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar so shortcuts keep working.
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppState.shared.saveNow()
        }
    }
}

struct MacroCommands: Commands {
    @ObservedObject var app: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Macro") { app.addMacro() }
                .keyboardShortcut("n")
            Button("Import Macros…") { app.importMacros() }
                .keyboardShortcut("o")
            Button("Export Macro…") {
                if let id = app.selectedMacroID { app.exportMacros([id]) }
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(app.selectedMacroID == nil)
        }

        CommandMenu("Macro") {
            Button(app.runningMacroID == nil ? "Run" : "Stop") {
                if app.runningMacroID != nil {
                    app.stopPlayback()
                } else {
                    app.runSelected()
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(app.selectedMacroID == nil || app.isRecording)

            Button(app.isRecording ? "Stop Recording" : "Record Steps") {
                app.toggleRecording()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(app.runningMacroID != nil)

            Divider()

            Button("Duplicate Macro") {
                if let id = app.selectedMacroID { app.duplicateMacro(id) }
            }
            .keyboardShortcut("d")
            .disabled(app.selectedMacroID == nil)

            Button("Delete Macro") {
                if let id = app.selectedMacroID { app.deleteMacro(id) }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(app.selectedMacroID == nil)
        }
    }
}
