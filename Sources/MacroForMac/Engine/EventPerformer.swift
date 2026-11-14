import AppKit
import CoreGraphics
import MacroCore

enum PlaybackError: LocalizedError {
    case eventCreationFailed
    case appNotFound(String)
    case invalidURL(String)
    case couldNotOpen(String)
    case processFailed(command: String, status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .eventCreationFailed:
            return "Couldn't create a keyboard or mouse event. Check that MacroForMac has Accessibility access."
        case .appNotFound(let name):
            return "Couldn't find the app “\(name)”."
        case .invalidURL(let url):
            return "“\(url)” isn't a valid URL or file path."
        case .couldNotOpen(let target):
            return "Couldn't open “\(target)”."
        case let .processFailed(command, status, message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(command) exited with status \(status)\(detail.isEmpty ? "" : ": \(detail)")"
        }
    }
}

/// Performs macro actions by posting synthetic events and launching apps / processes.
final class EventPerformer: MacroPerformer, @unchecked Sendable {
    /// Pause between typed characters.
    var typingDelay: Double

    private let source = CGEventSource(stateID: .hidSystemState)

    /// Keys and buttons left pressed by Key Down / Mouse Down steps.
    private var heldKeys: [UInt16: CGEventFlags] = [:]
    private var heldButtons: [MouseButton: CGPoint] = [:]

    init(typingDelay: Double) {
        self.typingDelay = max(0, typingDelay)
    }

    func perform(_ action: MacroAction) async throws {
        switch action {
        case .typeText(let p):
            try await type(p.text)
        case .keyPress(let p):
            try await press(keyCode: p.keyCode, modifiers: p.modifiers, hold: p.holdDuration)
        case .keyDown(let p):
            try keyDown(p)
            try await pause(0.02)
        case .keyUp(let p):
            try keyUp(p)
            try await pause(0.02)
        case .delay(let p):
            try await MacroRunner.defaultSleep(p.seconds)
        case .click(let p):
            try await click(p)
        case .mouseDown(let p):
            try await mouseDown(p)
        case .mouseUp(let p):
            try await mouseUp(p)
        case .moveMouse(let p):
            try move(to: CGPoint(x: p.x, y: p.y))
            try await pause(0.02)
        case .drag(let p):
            try await drag(p)
        case .scroll(let p):
            try scroll(p)
            try await pause(0.02)
        case .openApp(let p):
            try await openApp(p.path)
        case .openURL(let p):
            try await openURL(p.url)
        case .shell(let p):
            try await runProcess(
                executable: "/bin/zsh",
                arguments: ["-l", "-c", p.command],
                input: nil,
                wait: p.waitUntilExit,
                label: "Shell command"
            )
        case .appleScript(let p):
            try await runProcess(
                executable: "/usr/bin/osascript",
                arguments: [],
                input: p.source,
                wait: true,
                label: "AppleScript"
            )
        }
    }

    // MARK: Keyboard

    private func type(_ text: String) async throws {
        for character in text {
            try Task.checkCancellation()
            switch character {
            case "\n", "\r", "\r\n":
                try await press(keyCode: KeyCodes.returnKey, modifiers: [])
                continue
            case "\t":
                try await press(keyCode: KeyCodes.tab, modifiers: [])
                continue
            default:
                break
            }
            let units = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { throw PlaybackError.eventCreationFailed }
            // Clear any modifiers the user may still be holding so text isn't turned into shortcuts.
            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            try await pause(typingDelay)
        }
    }

    private func keyFlags(_ keyCode: UInt16, _ modifiers: KeyModifiers) -> CGEventFlags {
        var flags = modifiers.cgFlags
        if KeyCodes.impliesFunctionFlag(keyCode) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    private func keyEvent(_ keyCode: UInt16, down: Bool, flags: CGEventFlags, isRepeat: Bool = false) throws -> CGEvent {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down)
        else { throw PlaybackError.eventCreationFailed }
        event.flags = flags
        if isRepeat {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        return event
    }

    /// Presses and releases a key. With `hold` > 0 the key stays down that long.
    private func press(keyCode: UInt16, modifiers: KeyModifiers, hold: Double = 0) async throws {
        let flags = keyFlags(keyCode, modifiers)
        let down = try keyEvent(keyCode, down: true, flags: flags)
        let up = try keyEvent(keyCode, down: false, flags: flags)
        down.post(tap: .cghidEventTap)
        do {
            if hold > 0 {
                try await holdKey(keyCode, flags: flags, for: hold)
            } else {
                try await pause(0.015)
            }
        } catch {
            up.post(tap: .cghidEventTap) // never leave a key stuck down
            throw error
        }
        up.post(tap: .cghidEventTap)
        try await pause(0.02)
    }

    /// Waits while a key is held, sending auto-repeat key downs the way a real keyboard does
    /// (so holding Delete keeps deleting, holding an arrow keeps moving).
    private func holdKey(_ keyCode: UInt16, flags: CGEventFlags, for duration: Double) async throws {
        let (initialDelay, interval) = await MainActor.run { (NSEvent.keyRepeatDelay, NSEvent.keyRepeatInterval) }
        guard duration > initialDelay, interval > 0 else {
            try await pause(duration)
            return
        }
        try await pause(initialDelay)
        var elapsed = initialDelay
        repeat {
            try keyEvent(keyCode, down: true, flags: flags, isRepeat: true).post(tap: .cghidEventTap)
            let step = min(interval, duration - elapsed)
            try await pause(step)
            elapsed += step
        } while elapsed < duration - 0.001
    }

    private func keyDown(_ key: MacroAction.KeyToggle) throws {
        let flags = keyFlags(key.keyCode, key.modifiers)
        try keyEvent(key.keyCode, down: true, flags: flags).post(tap: .cghidEventTap)
        heldKeys[key.keyCode] = flags
    }

    private func keyUp(_ key: MacroAction.KeyToggle) throws {
        heldKeys.removeValue(forKey: key.keyCode)
        try keyEvent(key.keyCode, down: false, flags: keyFlags(key.keyCode, key.modifiers)).post(tap: .cghidEventTap)
    }

    /// Releases anything a Key Down or Mouse Down step left pressed. Called when a macro
    /// finishes, fails or is stopped, so nothing stays stuck down.
    func releaseHeldInputs() {
        for (keyCode, flags) in heldKeys {
            if let up = try? keyEvent(keyCode, down: false, flags: flags) {
                up.post(tap: .cghidEventTap)
            }
        }
        heldKeys.removeAll()
        for (button, point) in heldButtons {
            let types = mouseTypes(for: button)
            if let up = try? mouseEvent(types.up, at: point, button: types.button) {
                up.post(tap: .cghidEventTap)
            }
        }
        heldButtons.removeAll()
    }

    // MARK: Mouse

    private var pointerLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func mouseTypes(for button: MouseButton) -> (down: CGEventType, up: CGEventType, drag: CGEventType, button: CGMouseButton) {
        switch button {
        case .left: return (.leftMouseDown, .leftMouseUp, .leftMouseDragged, .left)
        case .right: return (.rightMouseDown, .rightMouseUp, .rightMouseDragged, .right)
        case .middle: return (.otherMouseDown, .otherMouseUp, .otherMouseDragged, .center)
        }
    }

    private func mouseEvent(_ type: CGEventType, at point: CGPoint, button: CGMouseButton) throws -> CGEvent {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        else { throw PlaybackError.eventCreationFailed }
        return event
    }

    /// Moves the pointer. While a Mouse Down step holds a button, this drags with it.
    private func move(to point: CGPoint) throws {
        let heldButton: MouseButton? = heldButtons[.left] != nil ? .left : heldButtons.keys.first
        if let heldButton {
            let types = mouseTypes(for: heldButton)
            try mouseEvent(types.drag, at: point, button: types.button).post(tap: .cghidEventTap)
            heldButtons[heldButton] = point
        } else {
            try mouseEvent(.mouseMoved, at: point, button: .left).post(tap: .cghidEventTap)
        }
    }

    private func mouseDown(_ press: MacroAction.ButtonToggle) async throws {
        let point = press.atCurrentPosition ? pointerLocation : CGPoint(x: press.x, y: press.y)
        if !press.atCurrentPosition {
            try move(to: point)
            try await pause(0.03)
        }
        let types = mouseTypes(for: press.button)
        let event = try mouseEvent(types.down, at: point, button: types.button)
        event.flags = press.modifiers.cgFlags
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
        heldButtons[press.button] = point
        try await pause(0.02)
    }

    private func mouseUp(_ release: MacroAction.ButtonToggle) async throws {
        let point = release.atCurrentPosition ? pointerLocation : CGPoint(x: release.x, y: release.y)
        if !release.atCurrentPosition && point != pointerLocation {
            try move(to: point)
            try await pause(0.03)
        }
        let types = mouseTypes(for: release.button)
        let event = try mouseEvent(types.up, at: point, button: types.button)
        event.flags = release.modifiers.cgFlags
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.post(tap: .cghidEventTap)
        heldButtons.removeValue(forKey: release.button)
        try await pause(0.02)
    }

    private func click(_ click: MacroAction.Click) async throws {
        let point = click.atCurrentPosition ? pointerLocation : CGPoint(x: click.x, y: click.y)
        let types = mouseTypes(for: click.button)
        let flags = click.modifiers.cgFlags
        if !click.atCurrentPosition {
            try move(to: point)
            try await pause(0.03)
        }
        let count = max(1, click.count)
        for clickNumber in 1...count {
            let down = try mouseEvent(types.down, at: point, button: types.button)
            let up = try mouseEvent(types.up, at: point, button: types.button)
            down.setIntegerValueField(.mouseEventClickState, value: Int64(clickNumber))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(clickNumber))
            down.flags = flags
            up.flags = flags
            down.post(tap: .cghidEventTap)
            let hold = clickNumber == count && click.holdDuration > 0 ? click.holdDuration : 0.02
            do {
                try await pause(hold)
            } catch {
                up.post(tap: .cghidEventTap) // never leave a button stuck down
                throw error
            }
            up.post(tap: .cghidEventTap)
            try await pause(clickNumber < count ? 0.06 : 0.03)
        }
    }

    private func drag(_ drag: MacroAction.Drag) async throws {
        let from = CGPoint(x: drag.fromX, y: drag.fromY)
        let to = CGPoint(x: drag.toX, y: drag.toY)
        try move(to: from)
        try await pause(0.05)
        try mouseEvent(.leftMouseDown, at: from, button: .left).post(tap: .cghidEventTap)
        try await pause(0.05)

        let duration = max(0.05, drag.duration)
        let frames = max(2, Int(duration / 0.016))
        do {
            for frame in 1...frames {
                try Task.checkCancellation()
                let t = Double(frame) / Double(frames)
                let point = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
                try mouseEvent(.leftMouseDragged, at: point, button: .left).post(tap: .cghidEventTap)
                try await pause(duration / Double(frames))
            }
        } catch {
            if let up = try? mouseEvent(.leftMouseUp, at: pointerLocation, button: .left) {
                up.post(tap: .cghidEventTap)
            }
            throw error
        }
        try mouseEvent(.leftMouseUp, at: to, button: .left).post(tap: .cghidEventTap)
        try await pause(0.03)
    }

    private func scroll(_ scroll: MacroAction.Scroll) throws {
        func clamp(_ value: Double) -> Int32 {
            Int32(max(Double(Int32.min), min(Double(Int32.max), value.rounded())))
        }
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: clamp(scroll.dy),
            wheel2: clamp(scroll.dx),
            wheel3: 0
        ) else { throw PlaybackError.eventCreationFailed }
        event.post(tap: .cghidEventTap)
    }

    // MARK: Apps, URLs, processes

    private func openApp(_ reference: String) async throws {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = Self.applicationURL(for: trimmed) else { throw PlaybackError.appNotFound(trimmed) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        // Give the app a moment to come to the front before the next step.
        try await pause(0.3)
    }

    /// Accepts a path ("/Applications/Safari.app"), a bundle identifier ("com.apple.Safari")
    /// or a plain name ("Safari").
    static func applicationURL(for reference: String) -> URL? {
        guard !reference.isEmpty else { return nil }
        let expanded = (reference as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: reference) {
            return url
        }
        let name = reference.hasSuffix(".app") ? reference : reference + ".app"
        let searchRoots = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/Applications/Utilities",
            (NSHomeDirectory() as NSString).appendingPathComponent("Applications"),
        ]
        for root in searchRoots {
            let path = (root as NSString).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    private func openURL(_ string: String) async throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        } else if let parsed = URL(string: trimmed), parsed.scheme != nil {
            url = parsed
        } else if !trimmed.isEmpty, !trimmed.contains(" "), let parsed = URL(string: "https://" + trimmed) {
            url = parsed
        } else {
            throw PlaybackError.invalidURL(trimmed)
        }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw PlaybackError.couldNotOpen(trimmed) }
        try await pause(0.2)
    }

    private func runProcess(executable: String, arguments: [String], input: String?, wait: Bool, label: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let inputPipe = input == nil ? nil : Pipe()
        if let inputPipe { process.standardInput = inputPipe }

        guard wait else {
            process.standardError = FileHandle.nullDevice
            try process.run()
            writeInput(input, to: inputPipe)
            return
        }

        let errorPipe = Pipe()
        process.standardError = errorPipe
        let collector = OutputCollector()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.append(handle.availableData)
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { finished in
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    collector.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                    if finished.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: CancellationError())
                    } else if finished.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: PlaybackError.processFailed(
                            command: label, status: finished.terminationStatus, message: collector.text))
                    }
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                writeInput(input, to: inputPipe)
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    private func writeInput(_ input: String?, to pipe: Pipe?) {
        guard let input, let pipe else { return }
        let handle = pipe.fileHandleForWriting
        DispatchQueue.global(qos: .userInitiated).async {
            handle.write(Data(input.utf8))
            try? handle.close()
        }
    }

    private func pause(_ seconds: Double) async throws {
        try await MacroRunner.defaultSleep(seconds)
    }
}

/// Thread-safe byte collector for process output.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data.prefix(2000), as: UTF8.self)
    }
}
