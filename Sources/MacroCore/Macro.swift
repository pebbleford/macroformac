import Foundation

public struct MacroStep: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var action: MacroAction
    public var isEnabled: Bool

    public init(id: UUID = UUID(), action: MacroAction, isEnabled: Bool = true) {
        self.id = id
        self.action = action
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey { case id, action, isEnabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        action = try c.decode(MacroAction.self, forKey: .action)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

public struct Macro: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var steps: [MacroStep]
    /// Global keyboard shortcut that runs (or stops) this macro.
    public var hotkey: KeyCombo?
    /// How many times to run the steps. 0 means "loop until stopped".
    public var repeatCount: Int
    /// Playback speed multiplier for waits: 2 = twice as fast, 0.5 = half speed.
    public var speed: Double

    public init(id: UUID = UUID(), name: String, steps: [MacroStep] = [], hotkey: KeyCombo? = nil,
                repeatCount: Int = 1, speed: Double = 1) {
        self.id = id
        self.name = name
        self.steps = steps
        self.hotkey = hotkey
        self.repeatCount = repeatCount
        self.speed = speed
    }

    private enum CodingKeys: String, CodingKey { case id, name, steps, hotkey, repeatCount, speed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Macro"
        steps = try c.decodeIfPresent([MacroStep].self, forKey: .steps) ?? []
        hotkey = try c.decodeIfPresent(KeyCombo.self, forKey: .hotkey)
        repeatCount = max(0, try c.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1)
        let decodedSpeed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        speed = decodedSpeed > 0 ? decodedSpeed : 1
    }

    public var loopsForever: Bool { repeatCount == 0 }

    /// Whether any enabled step needs to post keyboard / mouse events.
    public var needsInputEvents: Bool {
        steps.contains { $0.isEnabled && $0.action.kind.postsInputEvents }
    }

    /// Total of all enabled waits for one pass, adjusted for speed.
    public var totalWaitTime: Double {
        let total = steps.reduce(0.0) { sum, step in
            guard step.isEnabled, case .delay(let d) = step.action else { return sum }
            return sum + d.seconds
        }
        return total / (speed > 0 ? speed : 1)
    }

    /// A copy with fresh identifiers and no shortcut (shortcuts must be unique).
    public func duplicated(name newName: String? = nil) -> Macro {
        Macro(
            name: newName ?? "\(name) Copy",
            steps: steps.map { MacroStep(action: $0.action, isEnabled: $0.isEnabled) },
            hotkey: nil,
            repeatCount: repeatCount,
            speed: speed
        )
    }

    /// Example macros created on first launch.
    public static var examples: [Macro] {
        [
            Macro(
                name: "Example: Type a Greeting",
                steps: [
                    MacroStep(action: .typeText(.init(text: "Hello from MacroForMac! 👋"))),
                    MacroStep(action: .delay(.init(seconds: 0.3))),
                    MacroStep(action: .keyPress(.init(keyCode: KeyCodes.returnKey))),
                ]
            ),
            Macro(
                name: "Example: Select All & Copy",
                steps: [
                    MacroStep(action: .keyPress(.init(keyCode: 0, modifiers: .command))),
                    MacroStep(action: .delay(.init(seconds: 0.1))),
                    MacroStep(action: .keyPress(.init(keyCode: 8, modifiers: .command))),
                ]
            ),
            Macro(
                name: "Example: Open Calculator",
                steps: [
                    MacroStep(action: .openApp(.init(path: "/System/Applications/Calculator.app"))),
                ]
            ),
        ]
    }
}

extension Array where Element: Identifiable {
    /// Safe lookup / update by identifier. Setting `nil` removes the element.
    public subscript(id id: Element.ID) -> Element? {
        get { first { $0.id == id } }
        set {
            guard let index = firstIndex(where: { $0.id == id }) else { return }
            if let newValue {
                self[index] = newValue
            } else {
                remove(at: index)
            }
        }
    }
}
