import SwiftUI
import MacroCore

/// Sidebar: the macro library.
struct MacroListView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        listBody
        .onDeleteCommand {
            if let id = app.selectedMacroID { app.deleteMacro(id) }
        }
        .applyIf(UIProbe.variant != 4) {
            $0.toolbar {
                ToolbarItem {
                    Button {
                        app.addMacro()
                    } label: {
                        Label("New Macro", systemImage: "plus")
                    }
                    .help("New macro (⌘N)")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(app.macros.count) macro\(app.macros.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var listBody: some View {
        if UIProbe.variant == 2 {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(app.macros) { macro in
                        MacroRow(
                            macro: macro,
                            isRunning: app.runningMacroID == macro.id,
                            isRecording: app.recordingMacroID == macro.id,
                            hasConflict: app.hotkeyConflicts.contains(macro.id)
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(app.selectedMacroID == macro.id ? Color.accentColor.opacity(0.25) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { app.selectedMacroID = macro.id }
                        .contextMenu { contextMenu(for: macro) }
                    }
                }
                .padding(8)
            }
        } else {
        List(selection: $app.selectedMacroID) {
            ForEach(app.macros) { macro in
                MacroRow(
                    macro: macro,
                    isRunning: app.runningMacroID == macro.id,
                    isRecording: app.recordingMacroID == macro.id,
                    hasConflict: app.hotkeyConflicts.contains(macro.id)
                )
                .contextMenu { contextMenu(for: macro) }
            }
            .onMove { from, to in
                app.macros.move(fromOffsets: from, toOffset: to)
            }
        }
        .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private func contextMenu(for macro: Macro) -> some View {
        Button(app.runningMacroID == macro.id ? "Stop" : "Run") { app.toggleRun(macro.id) }
        Button("Record Steps") { app.startRecording(into: macro.id) }
        Divider()
        Button("Duplicate") { app.duplicateMacro(macro.id) }
        Button("Export…") { app.exportMacros([macro.id]) }
        Divider()
        Button("Delete", role: .destructive) { app.deleteMacro(macro.id) }
    }
}

private struct MacroRow: View {
    let macro: Macro
    let isRunning: Bool
    let isRecording: Bool
    let hasConflict: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(macro.name.isEmpty ? "Untitled Macro" : macro.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let hotkey = macro.hotkey {
                Text(hotkey.displayString)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(hasConflict ? Color.orange.opacity(0.25) : Color.secondary.opacity(0.15))
                    )
                    .help(hasConflict ? "This shortcut is already in use" : "Runs this macro from any app")
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let count = macro.steps.count
        var text = "\(count) step\(count == 1 ? "" : "s")"
        if macro.loopsForever {
            text += " · loops"
        } else if macro.repeatCount > 1 {
            text += " · ×\(macro.repeatCount)"
        }
        return text
    }

    private var statusSymbol: String {
        if isRecording { return "record.circle.fill" }
        if isRunning { return "play.circle.fill" }
        return "bolt.horizontal.circle"
    }

    private var statusColor: Color {
        if isRecording { return .red }
        if isRunning { return .green }
        return .accentColor
    }
}
