import AppKit
import SwiftUI
import MacroCore

/// A button that captures the next key combination you press.
struct KeyComboField: View {
    @EnvironmentObject private var app: AppState
    @Binding var combo: KeyCombo?
    var placeholder = "Record Shortcut"
    var allowsClear = true
    /// Global shortcuts need ⌘, ⌃ or ⌥ (F-keys excepted) so they don't swallow normal typing.
    var requiresModifier = false

    @State private var isCapturing = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isCapturing ? stopCapturing() : startCapturing()
            } label: {
                Text(label)
                    .font(isCapturing || combo == nil ? .body : .body.monospaced())
                    .foregroundStyle(isCapturing ? Color.accentColor : (combo == nil ? .secondary : .primary))
                    .frame(minWidth: 130)
            }
            .help(isCapturing ? "Press a key combination, or Esc to cancel" : "Click, then press the keys")

            if allowsClear, combo != nil, !isCapturing {
                Button {
                    combo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove shortcut")
            }
        }
        .onDisappear { stopCapturing() }
    }

    private var label: String {
        if isCapturing { return "Press keys…" }
        return combo?.displayString ?? placeholder
    }

    private func startCapturing() {
        guard !isCapturing else { return }
        isCapturing = true
        app.suspendHotkeys(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let modifiers = KeyModifiers(nsFlags: event.modifierFlags).normalized(for: event.keyCode)
            if event.keyCode == KeyCodes.escape && modifiers.isEmpty {
                stopCapturing()
                return nil
            }
            if requiresModifier && !modifiers.hasShortcutModifier && !KeyCodes.isFunctionKey(event.keyCode) {
                NSSound.beep()
                return nil
            }
            combo = KeyCombo(keyCode: event.keyCode, modifiers: modifiers)
            stopCapturing()
            return nil
        }
    }

    private func stopCapturing() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if isCapturing {
            isCapturing = false
            app.suspendHotkeys(false)
        }
    }
}
