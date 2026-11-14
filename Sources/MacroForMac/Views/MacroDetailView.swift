import SwiftUI
import MacroCore

/// Middle column: a macro's settings and its list of steps.
struct MacroDetailView: View {
    @EnvironmentObject private var app: AppState
    @Binding var macro: Macro
    @Binding var selectedStepID: MacroStep.ID?

    private let speeds: [Double] = [0.25, 0.5, 1, 2, 4, 10]

    var body: some View {
        VStack(spacing: 0) {
            PermissionBanner()
            header
            Divider()
            if macro.steps.isEmpty {
                emptySteps
            } else {
                stepList
            }
        }
        .navigationTitle(macro.name.isEmpty ? "Untitled Macro" : macro.name)
        .toolbar { toolbar }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Macro name", text: $macro.name)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Shortcut").foregroundStyle(.secondary)
                    HStack {
                        KeyComboField(combo: $macro.hotkey, placeholder: "None", requiresModifier: true)
                        if app.hotkeyConflicts.contains(macro.id) {
                            Label("Already in use", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                }
                GridRow {
                    Text("Repeat").foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Toggle("Loop until stopped", isOn: loopBinding)
                        if !macro.loopsForever {
                            Stepper(value: $macro.repeatCount, in: 1...100_000) {
                                Text("\(macro.repeatCount)×").monospacedDigit()
                            }
                        }
                    }
                }
                GridRow {
                    Text("Speed").foregroundStyle(.secondary)
                    Picker("Speed", selection: $macro.speed) {
                        ForEach(speeds, id: \.self) { speed in
                            Text(speedLabel(speed)).tag(speed)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("Scales waits, hold times and drags")
                }
            }
            .controlSize(.small)

            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loopBinding: Binding<Bool> {
        Binding(
            get: { macro.repeatCount == 0 },
            set: { macro.repeatCount = $0 ? 0 : 1 }
        )
    }

    private func speedLabel(_ speed: Double) -> String {
        switch speed {
        case 1: return "Normal (1×)"
        case ..<1: return "Slower (\(speed)×)"
        default: return "Faster (\(Int(speed))×)"
        }
    }

    private var footnote: String {
        var parts: [String] = []
        if let hotkey = macro.hotkey {
            parts.append("Press \(hotkey.displayString) in any app to run it (again to stop).")
        }
        if let stop = app.settings.stopHotkey {
            parts.append("\(stop.displayString) stops any macro.")
        }
        let wait = macro.totalWaitTime
        if wait > 0 {
            parts.append(String(format: "Waits total %.1f s per run.", wait))
        }
        return parts.isEmpty ? "Add a shortcut to run this macro from any app." : parts.joined(separator: " ")
    }

    // MARK: Steps

    private var stepList: some View {
        List(selection: $selectedStepID) {
            ForEach(Array(macro.steps.enumerated()), id: \.element.id) { index, step in
                StepRow(number: index + 1, step: step, isCurrent: app.currentStepID == step.id)
                    .contextMenu { stepMenu(step) }
            }
            .onMove { from, to in
                macro.steps.move(fromOffsets: from, toOffset: to)
            }
        }
        .onDeleteCommand(perform: deleteSelectedStep)
    }

    @ViewBuilder
    private func stepMenu(_ step: MacroStep) -> some View {
        Button(step.isEnabled ? "Disable" : "Enable") {
            macro.steps[id: step.id]?.isEnabled.toggle()
        }
        Button("Duplicate") {
            guard let index = macro.steps.firstIndex(where: { $0.id == step.id }) else { return }
            let copy = MacroStep(action: step.action, isEnabled: step.isEnabled)
            macro.steps.insert(copy, at: index + 1)
            selectedStepID = copy.id
        }
        Divider()
        Button("Move Up") { move(step.id, by: -1) }
            .disabled(macro.steps.first?.id == step.id)
        Button("Move Down") { move(step.id, by: 1) }
            .disabled(macro.steps.last?.id == step.id)
        Divider()
        Button("Delete", role: .destructive) {
            if selectedStepID == step.id { selectedStepID = nil }
            macro.steps.removeAll { $0.id == step.id }
        }
    }

    private func move(_ id: MacroStep.ID, by offset: Int) {
        guard let index = macro.steps.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard macro.steps.indices.contains(target) else { return }
        macro.steps.swapAt(index, target)
    }

    private func deleteSelectedStep() {
        guard let id = selectedStepID, let index = macro.steps.firstIndex(where: { $0.id == id }) else { return }
        macro.steps.remove(at: index)
        if macro.steps.isEmpty {
            selectedStepID = nil
        } else {
            selectedStepID = macro.steps[min(index, macro.steps.count - 1)].id
        }
    }

    private func addStep(_ kind: MacroAction.Kind) {
        let step = MacroStep(action: kind.defaultAction)
        if let id = selectedStepID, let index = macro.steps.firstIndex(where: { $0.id == id }) {
            macro.steps.insert(step, at: index + 1)
        } else {
            macro.steps.append(step)
        }
        selectedStepID = step.id
    }

    private var emptySteps: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No steps yet")
                .font(.title3.weight(.semibold))
            Text("Record what you do, or add steps one at a time.")
                .foregroundStyle(.secondary)
            HStack {
                addStepMenu
                    .fixedSize()
                Button {
                    app.startRecording(into: macro.id)
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var addStepMenu: some View {
        Menu {
            Section("Keyboard") {
                addButton(.typeText)
                addButton(.keyPress)
                addButton(.keyDown)
                addButton(.keyUp)
            }
            Section("Mouse") {
                addButton(.click)
                addButton(.mouseDown)
                addButton(.mouseUp)
                addButton(.moveMouse)
                addButton(.drag)
                addButton(.scroll)
            }
            Section("Timing") {
                addButton(.delay)
            }
            Section("Apps & Scripts") {
                addButton(.openApp)
                addButton(.openURL)
                addButton(.shell)
                addButton(.appleScript)
            }
        } label: {
            Label("Add Step", systemImage: "plus")
        }
        .help("Add a step after the selected one")
    }

    private func addButton(_ kind: MacroAction.Kind) -> some View {
        Button {
            addStep(kind)
        } label: {
            Label(kind.title, systemImage: kind.symbolName)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            addStepMenu

            let recordingThis = app.isRecording && app.recordingMacroID == macro.id
            Button {
                if recordingThis {
                    app.stopRecording(keep: true)
                } else {
                    app.startRecording(into: macro.id)
                }
            } label: {
                Label(recordingThis ? "Stop Recording" : "Record", systemImage: recordingThis ? "stop.circle" : "record.circle")
            }
            .help("Record keyboard and mouse input and append it to this macro (⇧⌘R)")
            .disabled(app.runningMacroID != nil || (app.isRecording && !recordingThis))

            let runningThis = app.runningMacroID == macro.id
            Button {
                app.toggleRun(macro.id)
            } label: {
                Label(runningThis ? "Stop" : "Run", systemImage: runningThis ? "stop.fill" : "play.fill")
            }
            .help(runningThis ? "Stop this macro" : "Run in the app you were using before (⌘↩)")
            .disabled(app.isRecording || (app.runningMacroID != nil && !runningThis))
        }
    }
}

struct StepRow: View {
    let number: Int
    let step: MacroStep
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .trailing)
            Image(systemName: step.action.kind.symbolName)
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(step.action.summary)
                .lineLimit(1)
                .strikethrough(!step.isEnabled)
            Spacer(minLength: 4)
            if isCurrent {
                Image(systemName: "play.fill")
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
        .opacity(step.isEnabled ? 1 : 0.5)
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch step.action.kind {
        case .typeText, .keyPress, .keyDown, .keyUp: return .blue
        case .click, .mouseDown, .mouseUp, .moveMouse, .drag, .scroll: return .purple
        case .delay: return .orange
        case .openApp, .openURL: return .teal
        case .shell, .appleScript: return .pink
        }
    }
}
