import Foundation

/// Options that control how input is turned into steps while recording.
public struct RecordingOptions: Codable, Hashable, Sendable {
    /// Merge consecutive plain keystrokes into a single "Type Text" step.
    public var mergeTypedText: Bool
    /// Insert "Wait" steps for the pauses between recorded events.
    public var recordDelays: Bool
    /// Pauses shorter than this (seconds) are dropped.
    public var minimumDelay: Double
    /// Pauses longer than this (seconds) are shortened to it. 0 = no limit.
    public var maximumDelay: Double
    /// Pointer movement (points) between mouse down and up that counts as a drag.
    public var dragThreshold: Double
    /// Record how long keys and mouse buttons are held down.
    public var recordHolds: Bool
    /// Presses held at least this long (seconds) are recorded as holds; shorter ones are taps.
    public var minimumHold: Double

    public init(mergeTypedText: Bool = true, recordDelays: Bool = true, minimumDelay: Double = 0.05,
                maximumDelay: Double = 10, dragThreshold: Double = 5,
                recordHolds: Bool = true, minimumHold: Double = 0.25) {
        self.mergeTypedText = mergeTypedText
        self.recordDelays = recordDelays
        self.minimumDelay = minimumDelay
        self.maximumDelay = maximumDelay
        self.dragThreshold = dragThreshold
        self.recordHolds = recordHolds
        self.minimumHold = minimumHold
    }

    private enum CodingKeys: String, CodingKey {
        case mergeTypedText, recordDelays, minimumDelay, maximumDelay, dragThreshold, recordHolds, minimumHold
    }

    public init(from decoder: Decoder) throws {
        let defaults = RecordingOptions()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mergeTypedText = try c.decodeIfPresent(Bool.self, forKey: .mergeTypedText) ?? defaults.mergeTypedText
        recordDelays = try c.decodeIfPresent(Bool.self, forKey: .recordDelays) ?? defaults.recordDelays
        minimumDelay = try c.decodeIfPresent(Double.self, forKey: .minimumDelay) ?? defaults.minimumDelay
        maximumDelay = try c.decodeIfPresent(Double.self, forKey: .maximumDelay) ?? defaults.maximumDelay
        dragThreshold = try c.decodeIfPresent(Double.self, forKey: .dragThreshold) ?? defaults.dragThreshold
        recordHolds = try c.decodeIfPresent(Bool.self, forKey: .recordHolds) ?? defaults.recordHolds
        minimumHold = try c.decodeIfPresent(Double.self, forKey: .minimumHold) ?? defaults.minimumHold
    }
}

/// App-wide preferences, persisted as JSON in UserDefaults.
public struct AppSettings: Codable, Hashable, Sendable {
    /// Pause between typed characters, in seconds.
    public var typingDelay: Double
    /// Global shortcut that stops playback or recording. Default ⌃⌥⌘. (period).
    public var stopHotkey: KeyCombo?
    public var recording: RecordingOptions
    /// Hide MacroForMac while recording / running so input goes to the app you were using.
    public var hideAppWhileRunning: Bool

    public static let defaultStopHotkey = KeyCombo(keyCode: KeyCodes.period, modifiers: [.control, .option, .command])

    public init(typingDelay: Double = 0.012, stopHotkey: KeyCombo? = AppSettings.defaultStopHotkey,
                recording: RecordingOptions = RecordingOptions(), hideAppWhileRunning: Bool = true) {
        self.typingDelay = typingDelay
        self.stopHotkey = stopHotkey
        self.recording = recording
        self.hideAppWhileRunning = hideAppWhileRunning
    }

    private enum CodingKeys: String, CodingKey { case typingDelay, stopHotkey, recording, hideAppWhileRunning }

    public init(from decoder: Decoder) throws {
        let defaults = AppSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        typingDelay = try c.decodeIfPresent(Double.self, forKey: .typingDelay) ?? defaults.typingDelay
        // Distinguish "key missing" (use default) from an explicit null (user cleared it).
        if c.contains(.stopHotkey) {
            stopHotkey = try c.decodeIfPresent(KeyCombo.self, forKey: .stopHotkey)
        } else {
            stopHotkey = defaults.stopHotkey
        }
        recording = try c.decodeIfPresent(RecordingOptions.self, forKey: .recording) ?? defaults.recording
        hideAppWhileRunning = try c.decodeIfPresent(Bool.self, forKey: .hideAppWhileRunning) ?? defaults.hideAppWhileRunning
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(typingDelay, forKey: .typingDelay)
        if let stopHotkey {
            try c.encode(stopHotkey, forKey: .stopHotkey)
        } else {
            try c.encodeNil(forKey: .stopHotkey)
        }
        try c.encode(recording, forKey: .recording)
        try c.encode(hideAppWhileRunning, forKey: .hideAppWhileRunning)
    }
}
