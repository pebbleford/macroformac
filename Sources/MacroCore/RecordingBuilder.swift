import Foundation

/// Raw input captured while recording, independent of CoreGraphics.
/// Coordinates are global screen points with the origin at the top-left of the main display.
public enum RecordedEvent: Sendable, Equatable {
    case keyDown(keyCode: UInt16, modifiers: KeyModifiers, characters: String?, time: TimeInterval)
    case mouseDown(button: MouseButton, x: Double, y: Double, clickCount: Int, modifiers: KeyModifiers, time: TimeInterval)
    case mouseUp(button: MouseButton, x: Double, y: Double, time: TimeInterval)
    case scroll(dx: Double, dy: Double, time: TimeInterval)
}

/// Turns a stream of recorded input into tidy macro steps:
/// typed characters become "Type Text", pauses become "Wait",
/// double-clicks are merged, drags detected and scroll bursts combined.
public struct RecordingBuilder: Sendable {
    public private(set) var steps: [MacroStep] = []
    public var options: RecordingOptions

    /// Scroll events closer together than this are merged into one step.
    public static let scrollMergeWindow: TimeInterval = 0.4
    /// How close (points) two clicks must be to merge into a double-click.
    public static let multiClickDistance: Double = 6

    private struct PendingPress: Sendable {
        var button: MouseButton
        var x: Double
        var y: Double
        var clickCount: Int
        var modifiers: KeyModifiers
        var time: TimeInterval
    }

    private var pendingPress: PendingPress?
    private var lastEventTime: TimeInterval?
    private var lastScrollTime: TimeInterval?

    public init(options: RecordingOptions = RecordingOptions()) {
        self.options = options
    }

    public mutating func add(_ event: RecordedEvent) {
        switch event {
        case let .keyDown(keyCode, modifiers, characters, time):
            addKey(keyCode: keyCode, modifiers: modifiers, characters: characters, time: time)

        case let .mouseDown(button, x, y, clickCount, modifiers, time):
            pendingPress = PendingPress(button: button, x: x, y: y, clickCount: max(1, clickCount),
                                        modifiers: modifiers, time: time)

        case let .mouseUp(button, x, y, time):
            guard let press = pendingPress, press.button == button else { return }
            pendingPress = nil
            addMouse(press: press, upX: x, upY: y, upTime: time)

        case let .scroll(dx, dy, time):
            addScroll(dx: dx, dy: dy, time: time)
        }
    }

    /// Final steps. A press without a release (e.g. the click on "Stop") is dropped,
    /// as are trailing waits.
    public mutating func finish() -> [MacroStep] {
        pendingPress = nil
        while let last = steps.last, case .delay = last.action {
            steps.removeLast()
        }
        return steps
    }

    // MARK: Keys

    private mutating func addKey(keyCode: UInt16, modifiers: KeyModifiers, characters: String?, time: TimeInterval) {
        if KeyCodes.isModifierKey(keyCode) { return }

        if options.mergeTypedText, let text = Self.typeableText(characters, modifiers: modifiers) {
            if let index = steps.indices.last, case .typeText(var typed) = steps[index].action {
                // Keep typing in the same step; the pause inside a word isn't worth a Wait step
                // unless it is long.
                let gap = time - (lastEventTime ?? time)
                if gap < max(1.0, options.minimumDelay) {
                    typed.text += text
                    steps[index].action = .typeText(typed)
                    lastEventTime = time
                    return
                }
            }
            appendWait(before: time)
            steps.append(MacroStep(action: .typeText(.init(text: text))))
            lastEventTime = time
            return
        }

        appendWait(before: time)
        steps.append(MacroStep(action: .keyPress(.init(keyCode: keyCode, modifiers: modifiers))))
        lastEventTime = time
    }

    /// Text that can be replayed as typing, or nil for shortcuts and special keys.
    public static func typeableText(_ characters: String?, modifiers: KeyModifiers) -> String? {
        if modifiers.contains(.command) || modifiers.contains(.control) { return nil }
        guard let characters, !characters.isEmpty else { return nil }
        for scalar in characters.unicodeScalars {
            let value = scalar.value
            if value < 0x20 || value == 0x7F { return nil }            // Return, Tab, Esc, Delete…
            if (0xF700...0xF8FF).contains(value) { return nil }        // Arrows, F-keys, Home/End…
        }
        return characters
    }

    // MARK: Mouse

    private mutating func addMouse(press: PendingPress, upX: Double, upY: Double, upTime: TimeInterval) {
        let distance = hypot(upX - press.x, upY - press.y)

        if press.button == .left && distance >= options.dragThreshold {
            appendWait(before: press.time)
            let duration = min(max(upTime - press.time, 0.1), 3)
            steps.append(MacroStep(action: .drag(.init(fromX: press.x, fromY: press.y, toX: upX, toY: upY,
                                                       duration: (duration * 100).rounded() / 100))))
            lastEventTime = upTime
            return
        }

        if press.clickCount > 1, mergeMultiClick(press) {
            lastEventTime = upTime
            return
        }

        appendWait(before: press.time)
        steps.append(MacroStep(action: .click(.init(x: press.x.rounded(), y: press.y.rounded(), button: press.button,
                                                    count: 1, modifiers: press.modifiers))))
        lastEventTime = upTime
    }

    /// The system reports the 2nd click of a double-click with clickCount 2; fold it into the
    /// previous click step (dropping the short wait in between).
    private mutating func mergeMultiClick(_ press: PendingPress) -> Bool {
        var index = steps.count - 1
        while index >= 0, case .delay = steps[index].action {
            index -= 1
        }
        guard index >= 0, case .click(var click) = steps[index].action,
              click.button == press.button,
              click.count == press.clickCount - 1,
              hypot(click.x - press.x, click.y - press.y) <= Self.multiClickDistance
        else { return false }

        click.count = press.clickCount
        steps.removeSubrange((index + 1)...)
        steps[index].action = .click(click)
        return true
    }

    // MARK: Scroll

    private mutating func addScroll(dx: Double, dy: Double, time: TimeInterval) {
        guard dx != 0 || dy != 0 else { return }
        if let index = steps.indices.last, case .scroll(var scroll) = steps[index].action,
           let last = lastScrollTime, time - last < Self.scrollMergeWindow {
            scroll.dx += dx
            scroll.dy += dy
            steps[index].action = .scroll(scroll)
        } else {
            appendWait(before: time)
            steps.append(MacroStep(action: .scroll(.init(dx: dx, dy: dy))))
        }
        lastScrollTime = time
        lastEventTime = time
    }

    // MARK: Waits

    private mutating func appendWait(before time: TimeInterval) {
        guard options.recordDelays, let last = lastEventTime else { return }
        var gap = time - last
        if options.maximumDelay > 0 { gap = min(gap, options.maximumDelay) }
        guard gap >= options.minimumDelay else { return }
        let rounded = (gap * 100).rounded() / 100
        steps.append(MacroStep(action: .delay(.init(seconds: rounded))))
    }
}
