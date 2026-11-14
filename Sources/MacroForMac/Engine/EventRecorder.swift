import AppKit
import CoreGraphics
import MacroCore

enum RecorderError: LocalizedError {
    case tapUnavailable

    var errorDescription: String? {
        "MacroForMac can't watch the keyboard and mouse yet. Allow it under System Settings → Privacy & Security → Accessibility (or Input Monitoring), then try again."
    }
}

/// Captures global keyboard and mouse input with a CGEvent tap and turns it into steps.
/// Input aimed at MacroForMac's own windows and menus (e.g. the Stop button) is ignored.
@MainActor
final class EventRecorder {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var builder: RecordingBuilder
    private var menuTracking = 0
    private var observers: [NSObjectProtocol] = []

    /// Shortcuts that should never end up in a recording (e.g. the stop shortcut).
    var ignoredCombos: [KeyCombo] = []
    /// Called with the current number of steps whenever it changes.
    var onStepCountChange: ((Int) -> Void)?

    init(options: RecordingOptions) {
        builder = RecordingBuilder(options: options)
    }

    func start() throws {
        guard tap == nil else { return }

        let types: [CGEventType] = [
            .keyDown, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .scrollWheel,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }

        // A listen-only tap needs Input Monitoring; an (unmodifying) active tap works with Accessibility.
        let options: CGEventTapOptions = Permissions.inputMonitoringGranted ? .listenOnly : .defaultTap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: mask,
            callback: recorderTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw RecorderError.tapUnavailable
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menuTracking += 1
            }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menuTracking = max(0, self.menuTracking - 1)
            }
        })
    }

    /// Stops listening and returns the recorded steps.
    func stop() -> [MacroStep] {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        return builder.finish()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        default:
            break
        }

        let time = ProcessInfo.processInfo.systemUptime
        let before = builder.steps.count

        switch type {
        case .keyDown:
            // Typing into MacroForMac itself isn't part of the macro.
            if NSApp.isActive { return }
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let modifiers = KeyModifiers(cgFlags: event.flags).normalized(for: keyCode)
            if ignoredCombos.contains(KeyCombo(keyCode: keyCode, modifiers: modifiers)) { return }
            builder.add(.keyDown(keyCode: keyCode, modifiers: modifiers, characters: characters(of: event), time: time))

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard let button = mouseButton(type: type, event: event) else { return }
            if menuTracking > 0 || isOverOwnWindow(event.location) { return }
            let clickCount = Int(event.getIntegerValueField(.mouseEventClickState))
            let modifiers = KeyModifiers(cgFlags: event.flags).subtracting(.function)
            builder.add(.mouseDown(button: button, x: event.location.x, y: event.location.y,
                                   clickCount: clickCount, modifiers: modifiers, time: time))

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard let button = mouseButton(type: type, event: event) else { return }
            builder.add(.mouseUp(button: button, x: event.location.x, y: event.location.y, time: time))

        case .scrollWheel:
            if menuTracking > 0 || isOverOwnWindow(event.location) { return }
            let dy = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            let dx = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
            builder.add(.scroll(dx: dx, dy: dy, time: time))

        default:
            return
        }

        if builder.steps.count != before {
            onStepCountChange?(builder.steps.count)
        }
    }

    private func mouseButton(type: CGEventType, event: CGEvent) -> MouseButton? {
        switch type {
        case .leftMouseDown, .leftMouseUp: return .left
        case .rightMouseDown, .rightMouseUp: return .right
        case .otherMouseDown, .otherMouseUp:
            return event.getIntegerValueField(.mouseEventButtonNumber) == 2 ? .middle : nil
        default: return nil
        }
    }

    private func characters(of event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return nil }
        return String(utf16CodeUnits: buffer, count: min(length, buffer.count))
    }

    /// True when the topmost window under the pointer belongs to MacroForMac
    /// (main window, recording panel or the menu bar icon).
    private func isOverOwnWindow(_ cgPoint: CGPoint) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return false }
        // CG coordinates have their origin top-left; AppKit's are bottom-left.
        let point = NSPoint(x: cgPoint.x, y: primaryHeight - cgPoint.y)
        let number = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        return NSApp.windows.contains { $0.windowNumber == number }
    }
}

/// C callback for the event tap. The tap's run loop source is on the main run loop.
private func recorderTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo {
        let recorder = Unmanaged<EventRecorder>.fromOpaque(userInfo).takeUnretainedValue()
        MainActor.assumeIsolated {
            recorder.handle(type: type, event: event)
        }
    }
    return Unmanaged.passUnretained(event)
}
