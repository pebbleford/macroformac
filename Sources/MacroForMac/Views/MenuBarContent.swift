import AppKit
import SwiftUI
import MacroCore

/// The menu behind the menu bar icon: run any macro without opening the window.
struct MenuBarContent: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if app.isRecording {
            Button("Stop Recording") { app.stopRecording(keep: true, fromMenuBar: true) }
            Button("Cancel Recording") { app.stopRecording(keep: false, fromMenuBar: true) }
            Divider()
        } else if let running = app.runningMacro {
            Button("Stop “\(running.name)”") { app.stopPlayback() }
            Divider()
        }

        if app.macros.isEmpty {
            Text("No macros yet")
        } else {
            ForEach(app.macros) { macro in
                Button(title(for: macro)) { app.run(macro.id) }
                    .disabled(app.isBusy || macro.steps.isEmpty)
            }
        }

        Divider()

        Button("Record New Macro") { app.startRecording(into: nil) }
            .disabled(app.isBusy)
        Button("Open MacroForMac") {
            openWindow(id: "main")
            app.showMainWindow()
        }

        if #available(macOS 14.0, *) {
            SettingsLink { Text("Settings…") }
        } else {
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }

        Divider()

        Button("Quit MacroForMac") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func title(for macro: Macro) -> String {
        let name = macro.name.isEmpty ? "Untitled Macro" : macro.name
        if let hotkey = macro.hotkey {
            return "\(name)   \(hotkey.displayString)"
        }
        return name
    }
}
