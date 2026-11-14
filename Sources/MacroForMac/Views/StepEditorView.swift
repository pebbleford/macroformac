import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MacroCore

/// Right column: edits the parameters of one step.
struct StepEditorView: View {
    @Binding var step: MacroStep

    var body: some View {
        Form {
            Section {
                LabeledContent("Action") {
                    Label(step.action.kind.title, systemImage: step.action.kind.symbolName)
                }
                Toggle("Enabled", isOn: $step.isEnabled)
            }

            Section(step.action.kind.title) {
                editor
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var editor: some View {
        switch step.action.kind {
        case .typeText:
            TypeTextEditor(value: payload(\.typeText, .init()))
        case .keyPress:
            KeyPressEditor(value: payload(\.keyPress, .init()))
        case .keyDown:
            KeyToggleEditor(value: payload(\.keyDown, .init()), isDown: true)
        case .keyUp:
            KeyToggleEditor(value: payload(\.keyUp, .init()), isDown: false)
        case .delay:
            DelayEditor(value: payload(\.delay, .init()))
        case .click:
            ClickEditor(value: payload(\.click, .init()))
        case .mouseDown:
            ButtonToggleEditor(value: payload(\.mouseDown, .init()), isDown: true)
        case .mouseUp:
            ButtonToggleEditor(value: payload(\.mouseUp, .init()), isDown: false)
        case .moveMouse:
            MoveMouseEditor(value: payload(\.moveMouse, .init()))
        case .drag:
            DragEditor(value: payload(\.drag, .init()))
        case .scroll:
            ScrollEditor(value: payload(\.scroll, .init()))
        case .openApp:
            OpenAppEditor(value: payload(\.openApp, .init()))
        case .openURL:
            OpenURLEditor(value: payload(\.openURL, .init()))
        case .shell:
            ShellEditor(value: payload(\.shell, .init()))
        case .appleScript:
            AppleScriptEditor(value: payload(\.appleScript, .init()))
        }
    }

    private func payload<P>(_ keyPath: WritableKeyPath<MacroAction, P?>, _ fallback: P) -> Binding<P> {
        let actionBinding = $step.action
        return Binding<P>(
            get: { actionBinding.wrappedValue[keyPath: keyPath] ?? fallback },
            set: { actionBinding.wrappedValue[keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - Keyboard

private struct TypeTextEditor: View {
    @Binding var value: MacroAction.TypeText

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $value.text)
                .font(.body.monospaced())
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
            Text("Typed exactly as written into the frontmost app, including line breaks and emoji. Typing speed is set in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct KeyPressEditor: View {
    @Binding var value: MacroAction.KeyPress

    var body: some View {
        LabeledContent("Shortcut") {
            KeyComboField(
                combo: Binding(
                    get: { value.combo },
                    set: { if let combo = $0 { value.combo = combo } }
                ),
                allowsClear: false
            )
        }
        Picker("Key", selection: $value.keyCode) {
            ForEach(KeyCodes.all, id: \.code) { key in
                Text(key.name).tag(key.code)
            }
        }
        ModifierToggles(modifiers: $value.modifiers)
        HoldField(seconds: $value.holdDuration, tapLabel: "Quick tap")
        Text("Click the shortcut button and press keys, or pick the key and modifiers by hand. Holding a key repeats it like a real keyboard.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Key Down / Key Up: the key stays pressed between the two steps.
private struct KeyToggleEditor: View {
    @Binding var value: MacroAction.KeyToggle
    let isDown: Bool

    var body: some View {
        LabeledContent("Key") {
            KeyComboField(
                combo: Binding(
                    get: { value.combo },
                    set: { if let combo = $0 { value.combo = combo } }
                ),
                allowsClear: false
            )
        }
        Picker("Key", selection: $value.keyCode) {
            ForEach(KeyCodes.all, id: \.code) { key in
                Text(key.name).tag(key.code)
            }
        }
        ModifierToggles(modifiers: $value.modifiers)
        Text(isDown
             ? "Presses the key and keeps it down until a Key Up step for the same key. Anything still held when the macro ends or is stopped is released automatically."
             : "Releases a key pressed by an earlier Key Down step.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// "Hold for" seconds, where 0 means a normal quick press.
private struct HoldField: View {
    @Binding var seconds: Double
    var tapLabel: String

    var body: some View {
        LabeledContent("Hold for") {
            HStack {
                TextField("Seconds", value: $seconds, format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                Stepper("", value: $seconds, in: 0...3600, step: 0.1)
                    .labelsHidden()
                Text(seconds > 0 ? "seconds" : "seconds (\(tapLabel.lowercased()))")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ModifierToggles: View {
    @Binding var modifiers: KeyModifiers

    var body: some View {
        HStack(spacing: 14) {
            toggle("⌃ Control", .control)
            toggle("⌥ Option", .option)
            toggle("⇧ Shift", .shift)
            toggle("⌘ Command", .command)
        }
        .toggleStyle(.checkbox)
    }

    private func toggle(_ title: String, _ modifier: KeyModifiers) -> some View {
        Toggle(title, isOn: Binding(
            get: { modifiers.contains(modifier) },
            set: { isOn in
                if isOn { modifiers.insert(modifier) } else { modifiers.remove(modifier) }
            }
        ))
    }
}

// MARK: - Timing

private struct DelayEditor: View {
    @Binding var value: MacroAction.Delay

    var body: some View {
        LabeledContent("Seconds") {
            HStack {
                TextField("Seconds", value: $value.seconds, format: .number.precision(.fractionLength(0...3)))
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                Stepper("", value: $value.seconds, in: 0...86_400, step: 0.1)
                    .labelsHidden()
            }
        }
        HStack {
            ForEach([0.1, 0.25, 0.5, 1, 2, 5], id: \.self) { seconds in
                Button("\(seconds.formatted()) s") { value.seconds = seconds }
                    .controlSize(.small)
            }
        }
        Text("Waits are scaled by the macro's speed setting.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Mouse

private struct PointFields: View {
    let title: String
    @Binding var x: Double
    @Binding var y: Double

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text("X").foregroundStyle(.secondary)
                TextField("X", value: $x, format: .number.precision(.fractionLength(0)))
                    .frame(width: 70)
                Text("Y").foregroundStyle(.secondary)
                TextField("Y", value: $y, format: .number.precision(.fractionLength(0)))
                    .frame(width: 70)
                PickPositionButton { point in
                    x = point.x.rounded()
                    y = point.y.rounded()
                }
            }
        }
    }
}

/// Captures the pointer position after a short countdown so you can hover over the target.
private struct PickPositionButton: View {
    var onPick: (CGPoint) -> Void
    @State private var remaining: Int?

    var body: some View {
        Button {
            start()
        } label: {
            if let remaining {
                Text("Hover target… \(remaining)").monospacedDigit()
            } else {
                Label("Pick", systemImage: "scope")
            }
        }
        .disabled(remaining != nil)
        .help("Move the pointer to the spot; its position is captured after 3 seconds")
    }

    private func start() {
        remaining = 3
        Task { @MainActor in
            for second in stride(from: 3, through: 1, by: -1) {
                remaining = second
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            remaining = nil
            onPick(CGEvent(source: nil)?.location ?? .zero)
            NSSound(named: "Tink")?.play()
        }
    }
}

private struct ClickEditor: View {
    @Binding var value: MacroAction.Click

    var body: some View {
        Picker("Button", selection: $value.button) {
            ForEach(MouseButton.allCases, id: \.self) { button in
                Text(button.title).tag(button)
            }
        }
        .pickerStyle(.segmented)

        Picker("Clicks", selection: $value.count) {
            Text("Single").tag(1)
            Text("Double").tag(2)
            Text("Triple").tag(3)
        }
        .pickerStyle(.segmented)

        Toggle("Click wherever the pointer is", isOn: $value.atCurrentPosition)

        if !value.atCurrentPosition {
            PointFields(title: "Position", x: $value.x, y: $value.y)
        }

        LabeledContent("Hold keys") {
            ModifierToggles(modifiers: $value.modifiers)
        }

        HoldField(seconds: $value.holdDuration, tapLabel: "Quick click")

        Text("Positions are screen points from the top-left corner of the main display.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Mouse Button Down / Up: the button stays pressed between the two steps.
private struct ButtonToggleEditor: View {
    @Binding var value: MacroAction.ButtonToggle
    let isDown: Bool

    var body: some View {
        Picker("Button", selection: $value.button) {
            ForEach(MouseButton.allCases, id: \.self) { button in
                Text(button.title).tag(button)
            }
        }
        .pickerStyle(.segmented)

        Toggle("Wherever the pointer is", isOn: $value.atCurrentPosition)

        if !value.atCurrentPosition {
            PointFields(title: "Position", x: $value.x, y: $value.y)
        }

        LabeledContent("Hold keys") {
            ModifierToggles(modifiers: $value.modifiers)
        }

        Text(isDown
             ? "Presses the button and keeps it down until a Mouse Button Up step. Move Mouse steps in between drag with it. A button still held when the macro ends is released automatically."
             : "Releases a button pressed by an earlier Mouse Button Down step.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct MoveMouseEditor: View {
    @Binding var value: MacroAction.MoveMouse

    var body: some View {
        PointFields(title: "Position", x: $value.x, y: $value.y)
    }
}

private struct DragEditor: View {
    @Binding var value: MacroAction.Drag

    var body: some View {
        PointFields(title: "From", x: $value.fromX, y: $value.fromY)
        PointFields(title: "To", x: $value.toX, y: $value.toY)
        LabeledContent("Duration") {
            HStack {
                Slider(value: $value.duration, in: 0.05...3)
                Text(String(format: "%.2f s", value.duration))
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }
}

private struct ScrollEditor: View {
    @Binding var value: MacroAction.Scroll

    var body: some View {
        LabeledContent("Vertical") {
            HStack {
                TextField("Vertical", value: $value.dy, format: .number.precision(.fractionLength(0)))
                    .frame(width: 80)
                Text("positive = up, negative = down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        LabeledContent("Horizontal") {
            HStack {
                TextField("Horizontal", value: $value.dx, format: .number.precision(.fractionLength(0)))
                    .frame(width: 80)
                Text("positive = left, negative = right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Text("Scrolls whatever is under the pointer, measured in pixels. Add a Move Mouse step first to aim it.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Apps & scripts

private struct OpenAppEditor: View {
    @Binding var value: MacroAction.OpenApp

    var body: some View {
        LabeledContent("App") {
            HStack {
                if let url = EventPerformer.applicationURL(for: value.path) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                TextField("Name, bundle ID or path", text: $value.path)
                Button("Choose…", action: choose)
            }
        }
        Text("For example “Safari”, “com.apple.Notes” or “/Applications/Xcode.app”.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            value.path = url.path
        }
    }
}

private struct OpenURLEditor: View {
    @Binding var value: MacroAction.OpenURL

    var body: some View {
        TextField("URL or file path", text: $value.url)
        Text("Web links open in your default browser; files and folders open in their default app. Works with app links like “x-apple.systempreferences:” too.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct ShellEditor: View {
    @Binding var value: MacroAction.Shell

    var body: some View {
        TextEditor(text: $value.command)
            .font(.body.monospaced())
            .frame(minHeight: 120)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
        Toggle("Wait until it finishes", isOn: $value.waitUntilExit)
        Text("Runs with zsh as a login shell, so your PATH (e.g. Homebrew) is available. If waiting, a non-zero exit status stops the macro.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct AppleScriptEditor: View {
    @Binding var value: MacroAction.AppleScript

    var body: some View {
        TextEditor(text: $value.source)
            .font(.body.monospaced())
            .frame(minHeight: 160)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.25)))
        HStack {
            Button("Insert Example") {
                if value.source.isEmpty {
                    value.source = "display notification \"Macro finished\" with title \"MacroForMac\""
                }
            }
            .disabled(!value.source.isEmpty)
            Spacer()
            Button("Automation Settings…") { Permissions.openAutomationSettings() }
        }
        Text("The first time a script controls another app, macOS asks for permission.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
