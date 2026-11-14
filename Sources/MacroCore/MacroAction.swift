import Foundation

public enum MouseButton: String, Codable, CaseIterable, Hashable, Sendable {
    case left, right, middle

    public var title: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .middle: return "Middle"
        }
    }
}

/// One thing a macro can do. Encoded as a flat JSON object with a `type` discriminator,
/// e.g. `{"type": "typeText", "text": "Hello"}`.
public enum MacroAction: Hashable, Sendable {
    case typeText(TypeText)
    case keyPress(KeyPress)
    case delay(Delay)
    case click(Click)
    case moveMouse(MoveMouse)
    case drag(Drag)
    case scroll(Scroll)
    case openApp(OpenApp)
    case openURL(OpenURL)
    case shell(Shell)
    case appleScript(AppleScript)

    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case typeText, keyPress, delay, click, moveMouse, drag, scroll, openApp, openURL, shell, appleScript

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .typeText: return "Type Text"
            case .keyPress: return "Press Keys"
            case .delay: return "Wait"
            case .click: return "Click"
            case .moveMouse: return "Move Mouse"
            case .drag: return "Drag"
            case .scroll: return "Scroll"
            case .openApp: return "Open App"
            case .openURL: return "Open URL or File"
            case .shell: return "Run Shell Command"
            case .appleScript: return "Run AppleScript"
            }
        }

        /// SF Symbol name.
        public var symbolName: String {
            switch self {
            case .typeText: return "character.cursor.ibeam"
            case .keyPress: return "command"
            case .delay: return "timer"
            case .click: return "cursorarrow.click"
            case .moveMouse: return "cursorarrow.motionlines"
            case .drag: return "hand.draw"
            case .scroll: return "scroll"
            case .openApp: return "macwindow"
            case .openURL: return "link"
            case .shell: return "terminal"
            case .appleScript: return "applescript"
            }
        }

        /// Whether performing this action posts synthetic keyboard / mouse events
        /// (and therefore needs the Accessibility permission).
        public var postsInputEvents: Bool {
            switch self {
            case .typeText, .keyPress, .click, .moveMouse, .drag, .scroll: return true
            case .delay, .openApp, .openURL, .shell, .appleScript: return false
            }
        }

        public var defaultAction: MacroAction {
            switch self {
            case .typeText: return .typeText(TypeText())
            case .keyPress: return .keyPress(KeyPress())
            case .delay: return .delay(Delay())
            case .click: return .click(Click())
            case .moveMouse: return .moveMouse(MoveMouse())
            case .drag: return .drag(Drag())
            case .scroll: return .scroll(Scroll())
            case .openApp: return .openApp(OpenApp())
            case .openURL: return .openURL(OpenURL())
            case .shell: return .shell(Shell())
            case .appleScript: return .appleScript(AppleScript())
            }
        }
    }

    // MARK: Payloads

    public struct TypeText: Codable, Hashable, Sendable {
        public var text: String
        public init(text: String = "") { self.text = text }
    }

    public struct KeyPress: Codable, Hashable, Sendable {
        public var keyCode: UInt16
        public var modifiers: KeyModifiers
        public init(keyCode: UInt16 = KeyCodes.returnKey, modifiers: KeyModifiers = []) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
        public init(_ combo: KeyCombo) { self.init(keyCode: combo.keyCode, modifiers: combo.modifiers) }
        public var combo: KeyCombo {
            get { KeyCombo(keyCode: keyCode, modifiers: modifiers) }
            set { keyCode = newValue.keyCode; modifiers = newValue.modifiers }
        }
    }

    public struct Delay: Codable, Hashable, Sendable {
        public var seconds: Double
        public init(seconds: Double = 0.5) { self.seconds = seconds }
    }

    public struct Click: Codable, Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var button: MouseButton
        /// 1 = single, 2 = double, 3 = triple click.
        public var count: Int
        /// Ignore x/y and click wherever the pointer currently is.
        public var atCurrentPosition: Bool
        /// Modifier keys held during the click (e.g. ⌘-click).
        public var modifiers: KeyModifiers

        public init(x: Double = 0, y: Double = 0, button: MouseButton = .left, count: Int = 1,
                    atCurrentPosition: Bool = false, modifiers: KeyModifiers = []) {
            self.x = x
            self.y = y
            self.button = button
            self.count = count
            self.atCurrentPosition = atCurrentPosition
            self.modifiers = modifiers
        }

        private enum CodingKeys: String, CodingKey { case x, y, button, count, atCurrentPosition, modifiers }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
            y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
            button = try c.decodeIfPresent(MouseButton.self, forKey: .button) ?? .left
            count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
            atCurrentPosition = try c.decodeIfPresent(Bool.self, forKey: .atCurrentPosition) ?? false
            modifiers = try c.decodeIfPresent(KeyModifiers.self, forKey: .modifiers) ?? []
        }
    }

    public struct MoveMouse: Codable, Hashable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
    }

    public struct Drag: Codable, Hashable, Sendable {
        public var fromX: Double
        public var fromY: Double
        public var toX: Double
        public var toY: Double
        /// How long the drag movement takes, in seconds.
        public var duration: Double
        public init(fromX: Double = 0, fromY: Double = 0, toX: Double = 100, toY: Double = 100, duration: Double = 0.3) {
            self.fromX = fromX
            self.fromY = fromY
            self.toX = toX
            self.toY = toY
            self.duration = duration
        }
    }

    public struct Scroll: Codable, Hashable, Sendable {
        /// Horizontal distance in pixels (positive scrolls left).
        public var dx: Double
        /// Vertical distance in pixels (positive scrolls up).
        public var dy: Double
        public init(dx: Double = 0, dy: Double = -200) { self.dx = dx; self.dy = dy }
    }

    public struct OpenApp: Codable, Hashable, Sendable {
        /// Path to the .app bundle, a bundle identifier, or an app name like "Safari".
        public var path: String
        public init(path: String = "") { self.path = path }
    }

    public struct OpenURL: Codable, Hashable, Sendable {
        public var url: String
        public init(url: String = "https://") { self.url = url }
    }

    public struct Shell: Codable, Hashable, Sendable {
        public var command: String
        public var waitUntilExit: Bool
        public init(command: String = "", waitUntilExit: Bool = true) {
            self.command = command
            self.waitUntilExit = waitUntilExit
        }
    }

    public struct AppleScript: Codable, Hashable, Sendable {
        public var source: String
        public init(source: String = "") { self.source = source }
    }

    // MARK: Info

    public var kind: Kind {
        switch self {
        case .typeText: return .typeText
        case .keyPress: return .keyPress
        case .delay: return .delay
        case .click: return .click
        case .moveMouse: return .moveMouse
        case .drag: return .drag
        case .scroll: return .scroll
        case .openApp: return .openApp
        case .openURL: return .openURL
        case .shell: return .shell
        case .appleScript: return .appleScript
        }
    }

    /// One-line human readable description, used in step lists.
    public var summary: String {
        switch self {
        case .typeText(let p):
            return p.text.isEmpty ? "Type (no text yet)" : "Type “\(Self.preview(p.text))”"
        case .keyPress(let p):
            return "Press \(p.combo.displayString)"
        case .delay(let p):
            return "Wait \(Self.format(p.seconds)) s"
        case .click(let p):
            let kind: String
            switch p.count {
            case ...1: kind = "click"
            case 2: kind = "double-click"
            case 3: kind = "triple-click"
            default: kind = "\(p.count)× click"
            }
            let button = p.button == .left ? "" : "\(p.button.title) "
            let mods = p.modifiers.isEmpty ? "" : "\(p.modifiers.symbols)-"
            let place = p.atCurrentPosition ? "at pointer" : "at \(Self.point(p.x, p.y))"
            return "\(mods)\(button)\(kind) \(place)".capitalizedFirst
        case .moveMouse(let p):
            return "Move pointer to \(Self.point(p.x, p.y))"
        case .drag(let p):
            return "Drag \(Self.point(p.fromX, p.fromY)) → \(Self.point(p.toX, p.toY))"
        case .scroll(let p):
            var parts: [String] = []
            if p.dy != 0 { parts.append(p.dy > 0 ? "up \(Self.format(abs(p.dy)))" : "down \(Self.format(abs(p.dy)))") }
            if p.dx != 0 { parts.append(p.dx > 0 ? "left \(Self.format(abs(p.dx)))" : "right \(Self.format(abs(p.dx)))") }
            return parts.isEmpty ? "Scroll (no distance)" : "Scroll " + parts.joined(separator: ", ")
        case .openApp(let p):
            return p.path.isEmpty ? "Open app (none chosen)" : "Open \(Self.appName(p.path))"
        case .openURL(let p):
            return "Open \(Self.preview(p.url))"
        case .shell(let p):
            return p.command.isEmpty ? "Run shell command (empty)" : "Run $ \(Self.preview(p.command))"
        case .appleScript(let p):
            return p.source.isEmpty ? "Run AppleScript (empty)" : "AppleScript: \(Self.preview(p.source))"
        }
    }

    static func preview(_ text: String, limit: Int = 48) -> String {
        let flat = text
            .replacingOccurrences(of: "\r\n", with: "⏎")
            .replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\t", with: "⇥")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    static func format(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    static func point(_ x: Double, _ y: Double) -> String {
        "(\(Int(x.rounded())), \(Int(y.rounded())))"
    }

    public static func appName(_ path: String) -> String {
        let last = (path as NSString).lastPathComponent
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: Codable

extension MacroAction: Codable {
    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .typeText: self = .typeText(try TypeText(from: decoder))
        case .keyPress: self = .keyPress(try KeyPress(from: decoder))
        case .delay: self = .delay(try Delay(from: decoder))
        case .click: self = .click(try Click(from: decoder))
        case .moveMouse: self = .moveMouse(try MoveMouse(from: decoder))
        case .drag: self = .drag(try Drag(from: decoder))
        case .scroll: self = .scroll(try Scroll(from: decoder))
        case .openApp: self = .openApp(try OpenApp(from: decoder))
        case .openURL: self = .openURL(try OpenURL(from: decoder))
        case .shell: self = .shell(try Shell(from: decoder))
        case .appleScript: self = .appleScript(try AppleScript(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TypeKey.self)
        try container.encode(kind, forKey: .type)
        switch self {
        case .typeText(let p): try p.encode(to: encoder)
        case .keyPress(let p): try p.encode(to: encoder)
        case .delay(let p): try p.encode(to: encoder)
        case .click(let p): try p.encode(to: encoder)
        case .moveMouse(let p): try p.encode(to: encoder)
        case .drag(let p): try p.encode(to: encoder)
        case .scroll(let p): try p.encode(to: encoder)
        case .openApp(let p): try p.encode(to: encoder)
        case .openURL(let p): try p.encode(to: encoder)
        case .shell(let p): try p.encode(to: encoder)
        case .appleScript(let p): try p.encode(to: encoder)
        }
    }
}

// MARK: Case accessors (handy for SwiftUI bindings: `$step.action.typeText`)

extension MacroAction {
    public var typeText: TypeText? {
        get { if case .typeText(let v) = self { return v } else { return nil } }
        set { if let newValue { self = .typeText(newValue) } }
    }
    public var keyPress: KeyPress? {
        get { if case .keyPress(let v) = self { return v } else { return nil } }
        set { if let newValue { self = .keyPress(newValue) } }
    }
    public var delay: Delay? {
        get { if case .delay(let v) = self { return v } else { return nil } }
        set { if let newValue { self = .delay(newValue) } }
    }
    public var click: Click? {
        get { if case .click(let v) = self { return v } else { return nil } }
        set { if let newValue { self = .click(newValue) } }
    }
    public var moveMouse: MoveMouse? {
        get { if case .moveMouse(let v) = self { return v } else { return nil } }
        set { if let newValue { self = .moveMouse(newValue) } }
    }
    public var drag: Drag? {
        get { if case .drag(let v) = self { return v } else { return nil } }
        set { if let newValue { self = .drag(newValue) } }
    }
    public var scroll: Scroll? {
        get { if case .scroll(let v) = self { return v } else { return nil } }
        set { if let newValue { self = .scroll(newValue) } }
    }
    public var openApp: OpenApp? {
        get { if case .openApp(let v) = self { return v } else { return nil } }
        set { if let newValue { self = .openApp(newValue) } }
    }
    public var openURL: OpenURL? {
        get { if case .openURL(let v) = self { return v } else { return nil } }
        set { if let newValue { self = .openURL(newValue) } }
    }
    public var shell: Shell? {
        get { if case .shell(let v) = self { return v } else { return nil } }
        set { if let newValue { self = .shell(newValue) } }
    }
    public var appleScript: AppleScript? {
        get { if case .appleScript(let v) = self { return v } else { return nil } }
        set { if let newValue { self = .appleScript(newValue) } }
    }
}
