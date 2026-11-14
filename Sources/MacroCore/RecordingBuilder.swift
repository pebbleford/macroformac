import Foundation

/// Raw input captured while recording, independent of CoreGraphics.
/// Coordinates are global screen points with the origin at the top-left of the main display.
public enum RecordedEvent: Sendable, Equatable {
    /// `isRepeat` marks the system's auto-repeat while a key is held; those are not recorded as presses.
    case keyDown(keyCode: UInt16, modifiers: KeyModifiers, characters: String?, time: TimeInterval, isRepeat: Bool = false)
    case keyUp(keyCode: UInt16, time: TimeInterval)
    case mouseDown(button: MouseButton, x: Double, y: Double, clickCount: Int, modifiers: KeyModifiers, time: TimeInterval)
    case mouseUp(button: MouseButton, x: Double, y: Double, time: TimeInterval)
    case scroll(dx: Double, dy: Double, time: TimeInterval)
}

/// Turns recorded input into tidy macro steps:
/// - quick keystrokes become "Type Text", shortcuts and special keys become key presses;
/// - keys and buttons held longer than `minimumHold` keep their hold time
///   ("Press W · held 1.2 s"), or become separate Key Down / Key Up steps when other input
///   happened while they were held (e.g. holding W while tapping Space);
/// - pauses become "Wait", double-clicks are merged, drags detected and scroll bursts combined.
public struct RecordingBuilder: Sendable {
    public var options: RecordingOptions
    public private(set) var events: [RecordedEvent] = []

    /// Scroll events closer together than this are merged into one step.
    public static let scrollMergeWindow: TimeInterval = 0.4
    /// How close (points) two clicks must be to merge into a double-click.
    public static let multiClickDistance: Double = 6

    public init(options: RecordingOptions = RecordingOptions()) {
        self.options = options
    }

    public mutating func add(_ event: RecordedEvent) {
        events.append(event)
    }

    /// Steps for everything recorded so far.
    public var steps: [MacroStep] {
        Self.build(events, options: options)
    }

    /// Final steps. A mouse press without a release (e.g. the click on "Stop") is dropped,
    /// a key that was never released counts as a tap, and trailing waits are removed.
    public func finish() -> [MacroStep] {
        steps
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

    // MARK: - Build

    static func build(_ events: [RecordedEvent], options: RecordingOptions) -> [MacroStep] {
        var emitter = Emitter(options: options)
        for item in items(from: pair(events), options: options) {
            emitter.add(item)
        }
        return emitter.finish()
    }

    /// A key or button press matched with its release (or a scroll, which has no duration).
    private struct Press {
        enum Source {
            case key(code: UInt16, modifiers: KeyModifiers, characters: String?)
            case mouse(button: MouseButton, x: Double, y: Double, clickCount: Int, modifiers: KeyModifiers)
            case scroll(dx: Double, dy: Double)
        }

        var source: Source
        var start: TimeInterval
        var end: TimeInterval
        var upX: Double = 0
        var upY: Double = 0
        var released = false
    }

    private static func pair(_ events: [RecordedEvent]) -> [Press] {
        var presses: [Press] = []
        var openKeys: [UInt16: Int] = [:]
        var openButtons: [MouseButton: Int] = [:]

        for event in events {
            switch event {
            case let .keyDown(code, modifiers, characters, time, isRepeat):
                if KeyCodes.isModifierKey(code) || isRepeat { continue }
                openKeys[code] = presses.count
                presses.append(Press(source: .key(code: code, modifiers: modifiers, characters: characters),
                                     start: time, end: time))

            case let .keyUp(code, time):
                if let index = openKeys.removeValue(forKey: code) {
                    presses[index].end = max(presses[index].start, time)
                    presses[index].released = true
                }

            case let .mouseDown(button, x, y, clickCount, modifiers, time):
                openButtons[button] = presses.count
                presses.append(Press(source: .mouse(button: button, x: x, y: y, clickCount: max(1, clickCount),
                                                    modifiers: modifiers),
                                     start: time, end: time, upX: x, upY: y))

            case let .mouseUp(button, x, y, time):
                if let index = openButtons.removeValue(forKey: button) {
                    presses[index].end = max(presses[index].start, time)
                    presses[index].upX = x
                    presses[index].upY = y
                    presses[index].released = true
                }

            case let .scroll(dx, dy, time):
                guard dx != 0 || dy != 0 else { continue }
                presses.append(Press(source: .scroll(dx: dx, dy: dy), start: time, end: time, released: true))
            }
        }

        // A mouse press that was never released (e.g. the click on "Stop") is dropped.
        return presses.filter { press in
            if case .mouse = press.source { return press.released }
            return true
        }
    }

    /// Something to emit as a step, positioned in time.
    private struct Item {
        enum Kind {
            case text(String)
            case action(MacroAction)
            case click(MacroAction.Click, clickCount: Int)
            case scroll(dx: Double, dy: Double)
        }

        var kind: Kind
        var start: TimeInterval
        /// Where the following wait starts counting from (the release, for holds and clicks).
        var end: TimeInterval
        var order: Int
    }

    private static func items(from presses: [Press], options: RecordingOptions) -> [Item] {
        let minimumHold = options.recordHolds ? max(0.01, options.minimumHold) : .infinity

        func isDrag(_ press: Press) -> Bool {
            guard case let .mouse(button, x, y, _, _) = press.source else { return false }
            return button == .left && hypot(press.upX - x, press.upY - y) >= options.dragThreshold
        }
        func isHold(_ press: Press) -> Bool {
            if case .scroll = press.source { return false }
            return press.released && press.end - press.start >= minimumHold && !isDrag(press)
        }
        /// Holds and drags occupy [start, end]; everything else is a moment at `start`.
        func spanEnd(_ press: Press) -> TimeInterval {
            isHold(press) || isDrag(press) ? press.end : press.start
        }

        let starts = presses.map(\.start) // chronological
        let spans = presses.indices.filter { isHold(presses[$0]) || isDrag(presses[$0]) }

        /// True if other input happened while `presses[index]` was held.
        func hasInputDuringHold(_ index: Int) -> Bool {
            let press = presses[index]
            // First press that starts strictly after this one.
            var low = 0
            var high = starts.count
            while low < high {
                let mid = (low + high) / 2
                if starts[mid] <= press.start { low = mid + 1 } else { high = mid }
            }
            if low < starts.count && starts[low] < press.end { return true }
            // Another hold or drag still going when this one started.
            for other in spans where other != index {
                if presses[other].start <= press.start && spanEnd(presses[other]) > press.start { return true }
            }
            return false
        }

        let split = Set(presses.indices.filter { isHold(presses[$0]) && hasInputDuringHold($0) })
        let splitSpans = split.map { (presses[$0].start, presses[$0].end) }
        /// Keys tapped while another key is held down (game controls, shortcuts) stay key presses.
        func duringSplitHold(_ time: TimeInterval) -> Bool {
            splitSpans.contains { $0.0 < time && time < $0.1 }
        }

        var items: [Item] = []
        func add(_ kind: Item.Kind, start: TimeInterval, end: TimeInterval) {
            items.append(Item(kind: kind, start: start, end: end, order: items.count))
        }

        for (index, press) in presses.enumerated() {
            let held = roundTime(press.end - press.start)
            switch press.source {
            case let .key(code, modifiers, characters):
                let key = MacroAction.KeyToggle(keyCode: code, modifiers: modifiers)
                if split.contains(index) {
                    add(.action(.keyDown(key)), start: press.start, end: press.start)
                    add(.action(.keyUp(key)), start: press.end, end: press.end)
                } else if isHold(press) {
                    add(.action(.keyPress(.init(keyCode: code, modifiers: modifiers, holdDuration: held))),
                        start: press.start, end: press.end)
                } else if options.mergeTypedText, !duringSplitHold(press.start),
                          let text = typeableText(characters, modifiers: modifiers) {
                    add(.text(text), start: press.start, end: press.start)
                } else {
                    add(.action(.keyPress(.init(keyCode: code, modifiers: modifiers))), start: press.start, end: press.start)
                }

            case let .mouse(button, x, y, clickCount, modifiers):
                if isDrag(press) {
                    let duration = roundTime(min(max(press.end - press.start, 0.1), 3))
                    add(.action(.drag(.init(fromX: x, fromY: y, toX: press.upX, toY: press.upY, duration: duration))),
                        start: press.start, end: press.end)
                } else if split.contains(index) {
                    let down = MacroAction.ButtonToggle(x: x.rounded(), y: y.rounded(), button: button,
                                                        atCurrentPosition: false, modifiers: modifiers)
                    let up = MacroAction.ButtonToggle(x: press.upX.rounded(), y: press.upY.rounded(), button: button,
                                                      atCurrentPosition: false, modifiers: modifiers)
                    add(.action(.mouseDown(down)), start: press.start, end: press.start)
                    add(.action(.mouseUp(up)), start: press.end, end: press.end)
                } else {
                    let hold = isHold(press) ? held : 0
                    let click = MacroAction.Click(x: x.rounded(), y: y.rounded(), button: button, count: 1,
                                                  modifiers: modifiers, holdDuration: hold)
                    add(.click(click, clickCount: hold > 0 ? 1 : clickCount), start: press.start, end: press.end)
                }

            case let .scroll(dx, dy):
                add(.scroll(dx: dx, dy: dy), start: press.start, end: press.start)
            }
        }

        return items.sorted { ($0.start, $0.order) < ($1.start, $1.order) }
    }

    /// Appends items as steps, merging typing, double-clicks and scrolls and inserting waits.
    private struct Emitter {
        let options: RecordingOptions
        var steps: [MacroStep] = []
        var lastEnd: TimeInterval?
        var lastScrollTime: TimeInterval?

        init(options: RecordingOptions) {
            self.options = options
        }

        mutating func add(_ item: Item) {
            defer { lastEnd = max(lastEnd ?? item.end, item.end) }

            switch item.kind {
            case .text(let text):
                // Keep typing in the same step; short pauses inside typing aren't worth a Wait.
                if let index = steps.indices.last, case .typeText(var typed) = steps[index].action,
                   let lastEnd, item.start - lastEnd < max(1.0, options.minimumDelay) {
                    typed.text += text
                    steps[index].action = .typeText(typed)
                    return
                }
                appendWait(before: item.start)
                steps.append(MacroStep(action: .typeText(.init(text: text))))

            case let .click(click, clickCount):
                if clickCount > 1, mergeMultiClick(click, clickCount: clickCount) { return }
                appendWait(before: item.start)
                steps.append(MacroStep(action: .click(click)))

            case let .scroll(dx, dy):
                defer { lastScrollTime = item.start }
                if let index = steps.indices.last, case .scroll(var scroll) = steps[index].action,
                   let last = lastScrollTime, item.start - last < RecordingBuilder.scrollMergeWindow {
                    scroll.dx += dx
                    scroll.dy += dy
                    steps[index].action = .scroll(scroll)
                    return
                }
                appendWait(before: item.start)
                steps.append(MacroStep(action: .scroll(.init(dx: dx, dy: dy))))

            case .action(let action):
                appendWait(before: item.start)
                steps.append(MacroStep(action: action))
            }
        }

        /// The system reports the 2nd click of a double-click with clickCount 2; fold it into the
        /// previous click step (dropping the short wait in between).
        private mutating func mergeMultiClick(_ press: MacroAction.Click, clickCount: Int) -> Bool {
            var index = steps.count - 1
            while index >= 0, case .delay = steps[index].action {
                index -= 1
            }
            guard index >= 0, case .click(var click) = steps[index].action,
                  click.button == press.button,
                  click.holdDuration == 0,
                  click.count == clickCount - 1,
                  hypot(click.x - press.x, click.y - press.y) <= RecordingBuilder.multiClickDistance
            else { return false }

            click.count = clickCount
            steps.removeSubrange((index + 1)...)
            steps[index].action = .click(click)
            return true
        }

        private mutating func appendWait(before time: TimeInterval) {
            guard options.recordDelays, let last = lastEnd else { return }
            var gap = time - last
            if options.maximumDelay > 0 { gap = min(gap, options.maximumDelay) }
            guard gap >= options.minimumDelay else { return }
            steps.append(MacroStep(action: .delay(.init(seconds: roundTime(gap)))))
        }

        mutating func finish() -> [MacroStep] {
            while let last = steps.last, case .delay = last.action {
                steps.removeLast()
            }
            return steps
        }
    }
}

/// Rounds to hundredths of a second.
private func roundTime(_ seconds: Double) -> Double {
    (seconds * 100).rounded() / 100
}
