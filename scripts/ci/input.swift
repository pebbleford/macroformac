// CI helper: posts real mouse clicks and key presses, like a person using the app.
//   swiftc scripts/ci/input.swift -o /tmp/ci-input
//   /tmp/ci-input click 120 240          # left click at global screen coordinates
//   /tmp/ci-input key 18 control option  # press a key (virtual key code) with modifiers
import CoreGraphics
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
let source = CGEventSource(stateID: .hidSystemState)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

switch args.first {
case "click":
    guard args.count == 3, let x = Double(args[1]), let y = Double(args[2]) else { fail("usage: click X Y") }
    let point = CGPoint(x: x, y: y)
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        usleep(80_000)
    }
case "key":
    guard args.count >= 2, let code = CGKeyCode(args[1]) else { fail("usage: key KEYCODE [control] [option] [shift] [command]") }
    var flags: CGEventFlags = []
    for name in args.dropFirst(2) {
        switch name {
        case "control": flags.insert(.maskControl)
        case "option": flags.insert(.maskAlternate)
        case "shift": flags.insert(.maskShift)
        case "command": flags.insert(.maskCommand)
        default: fail("unknown modifier \(name)")
        }
    }
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
        usleep(80_000)
    }
default:
    fail("usage: click X Y | key KEYCODE [modifiers…]")
}
