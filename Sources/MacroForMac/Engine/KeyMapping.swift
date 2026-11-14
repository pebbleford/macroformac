import AppKit
import Carbon.HIToolbox
import CoreGraphics
import MacroCore

extension KeyModifiers {
    init(cgFlags: CGEventFlags) {
        var result: KeyModifiers = []
        if cgFlags.contains(.maskControl) { result.insert(.control) }
        if cgFlags.contains(.maskAlternate) { result.insert(.option) }
        if cgFlags.contains(.maskShift) { result.insert(.shift) }
        if cgFlags.contains(.maskCommand) { result.insert(.command) }
        if cgFlags.contains(.maskSecondaryFn) { result.insert(.function) }
        self = result
    }

    init(nsFlags: NSEvent.ModifierFlags) {
        var result: KeyModifiers = []
        if nsFlags.contains(.control) { result.insert(.control) }
        if nsFlags.contains(.option) { result.insert(.option) }
        if nsFlags.contains(.shift) { result.insert(.shift) }
        if nsFlags.contains(.command) { result.insert(.command) }
        if nsFlags.contains(.function) { result.insert(.function) }
        self = result
    }

    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    /// Carbon modifier mask for RegisterEventHotKey.
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    /// Removes the fn flag macOS adds on its own to arrows, F-keys and navigation keys.
    func normalized(for keyCode: UInt16) -> KeyModifiers {
        KeyCodes.impliesFunctionFlag(keyCode) ? subtracting(.function) : self
    }
}
