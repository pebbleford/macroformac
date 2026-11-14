import Foundation

/// Modifier keys, stored independently of AppKit / CoreGraphics so the model stays portable.
public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option = KeyModifiers(rawValue: 1 << 1)
    public static let shift = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
    public static let function = KeyModifiers(rawValue: 1 << 4)

    /// Symbols in the standard macOS order: ⌃⌥⇧⌘.
    public var symbols: String {
        var result = ""
        if contains(.function) { result += "fn " }
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    /// True when the combination contains a "real" shortcut modifier (⌘, ⌃ or ⌥).
    public var hasShortcutModifier: Bool {
        !intersection([.command, .control, .option]).isEmpty
    }
}

/// A key plus modifiers, e.g. ⌘C. `keyCode` is a macOS virtual key code.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: KeyModifiers

    public init(keyCode: UInt16, modifiers: KeyModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String {
        modifiers.symbols + KeyCodes.name(for: keyCode)
    }
}

/// Virtual key codes (ANSI layout) and their display names.
public enum KeyCodes {
    public struct Key: Hashable, Sendable {
        public let code: UInt16
        public let name: String
    }

    public static let returnKey: UInt16 = 36
    public static let tab: UInt16 = 48
    public static let space: UInt16 = 49
    public static let delete: UInt16 = 51
    public static let escape: UInt16 = 53
    public static let period: UInt16 = 47

    /// Keys offered in pickers, in a friendly order.
    public static let all: [Key] = {
        var keys: [Key] = []
        let letters: [(String, UInt16)] = [
            ("A", 0), ("B", 11), ("C", 8), ("D", 2), ("E", 14), ("F", 3), ("G", 5), ("H", 4),
            ("I", 34), ("J", 38), ("K", 40), ("L", 37), ("M", 46), ("N", 45), ("O", 31), ("P", 35),
            ("Q", 12), ("R", 15), ("S", 1), ("T", 17), ("U", 32), ("V", 9), ("W", 13), ("X", 7),
            ("Y", 16), ("Z", 6),
        ]
        let digits: [(String, UInt16)] = [
            ("0", 29), ("1", 18), ("2", 19), ("3", 20), ("4", 21),
            ("5", 23), ("6", 22), ("7", 26), ("8", 28), ("9", 25),
        ]
        let special: [(String, UInt16)] = [
            ("Return ↩", 36), ("Tab ⇥", 48), ("Space", 49), ("Delete ⌫", 51), ("Forward Delete ⌦", 117),
            ("Escape ⎋", 53), ("Left Arrow ←", 123), ("Right Arrow →", 124), ("Down Arrow ↓", 125),
            ("Up Arrow ↑", 126), ("Home ↖", 115), ("End ↘", 119), ("Page Up ⇞", 116), ("Page Down ⇟", 121),
            ("Help", 114),
        ]
        let functionKeys: [(String, UInt16)] = [
            ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96), ("F6", 97), ("F7", 98),
            ("F8", 100), ("F9", 101), ("F10", 109), ("F11", 103), ("F12", 111), ("F13", 105),
            ("F14", 107), ("F15", 113), ("F16", 106), ("F17", 64), ("F18", 79), ("F19", 80), ("F20", 90),
        ]
        let punctuation: [(String, UInt16)] = [
            ("-", 27), ("=", 24), ("[", 33), ("]", 30), ("\\", 42), (";", 41), ("'", 39),
            (",", 43), (".", 47), ("/", 44), ("`", 50), ("§", 10),
        ]
        let keypad: [(String, UInt16)] = [
            ("Keypad 0", 82), ("Keypad 1", 83), ("Keypad 2", 84), ("Keypad 3", 85), ("Keypad 4", 86),
            ("Keypad 5", 87), ("Keypad 6", 88), ("Keypad 7", 89), ("Keypad 8", 91), ("Keypad 9", 92),
            ("Keypad .", 65), ("Keypad *", 67), ("Keypad +", 69), ("Keypad -", 78), ("Keypad /", 75),
            ("Keypad =", 81), ("Keypad Enter ⌤", 76), ("Keypad Clear ⌧", 71),
        ]
        for group in [letters, digits, special, functionKeys, punctuation, keypad] {
            keys += group.map { Key(code: $0.1, name: $0.0) }
        }
        return keys
    }()

    private static let shortNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        76: "⌤", 71: "⌧",
    ]

    private static let namesByCode: [UInt16: String] = {
        var map: [UInt16: String] = [:]
        for key in all where map[key.code] == nil { map[key.code] = key.name }
        return map
    }()

    /// Compact name used in shortcut strings (e.g. "↩", "A", "F5").
    public static func name(for code: UInt16) -> String {
        if let short = shortNames[code] { return short }
        if let name = namesByCode[code] { return name }
        return "Key \(code)"
    }

    /// Keys for which macOS sets the fn flag automatically (arrows, F-keys, navigation keys).
    public static func impliesFunctionFlag(_ code: UInt16) -> Bool {
        functionFlagKeys.contains(code)
    }

    /// F1–F20 can be used as global shortcuts without any modifier.
    public static func isFunctionKey(_ code: UInt16) -> Bool {
        [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90].contains(code)
    }

    /// Modifier keys themselves (never recorded as key presses).
    public static func isModifierKey(_ code: UInt16) -> Bool {
        (54...63).contains(code)
    }

    private static let functionFlagKeys: Set<UInt16> = [
        123, 124, 125, 126, 115, 119, 116, 121, 117, 114,
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]
}
