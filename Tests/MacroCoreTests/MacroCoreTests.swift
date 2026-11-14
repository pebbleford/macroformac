import XCTest
@testable import MacroCore

final class CodingTests: XCTestCase {
    private let allActions: [MacroAction] = [
        .typeText(.init(text: "Hello\nWorld 👋")),
        .keyPress(.init(keyCode: 8, modifiers: [.command, .shift])),
        .delay(.init(seconds: 1.25)),
        .click(.init(x: 10, y: 20, button: .right, count: 2, atCurrentPosition: false, modifiers: .command)),
        .moveMouse(.init(x: 5, y: 6)),
        .drag(.init(fromX: 1, fromY: 2, toX: 3, toY: 4, duration: 0.5)),
        .scroll(.init(dx: -3, dy: 120)),
        .openApp(.init(path: "/Applications/Safari.app")),
        .openURL(.init(url: "https://example.com")),
        .shell(.init(command: "echo hi", waitUntilExit: false)),
        .appleScript(.init(source: "beep")),
    ]

    func testEveryKindIsCovered() {
        XCTAssertEqual(Set(allActions.map(\.kind)), Set(MacroAction.Kind.allCases))
    }

    func testActionsRoundTrip() throws {
        for action in allActions {
            let data = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(MacroAction.self, from: data)
            XCTAssertEqual(decoded, action, "round trip failed for \(action.kind)")
        }
    }

    func testFlatJSONShape() throws {
        let data = try JSONEncoder().encode(MacroAction.typeText(.init(text: "hi")))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "typeText")
        XCTAssertEqual(object["text"] as? String, "hi")
    }

    func testDecodesHandWrittenJSONWithDefaults() throws {
        let json = """
        {"version": 1, "macros": [{
            "name": "Hand written",
            "steps": [
                {"action": {"type": "click", "x": 3, "y": 4}},
                {"action": {"type": "delay", "seconds": 2}, "isEnabled": false}
            ]
        }]}
        """
        let macros = try MacroStore.decode(Data(json.utf8))
        XCTAssertEqual(macros.count, 1)
        let macro = macros[0]
        XCTAssertEqual(macro.name, "Hand written")
        XCTAssertEqual(macro.repeatCount, 1)
        XCTAssertEqual(macro.speed, 1)
        XCTAssertNil(macro.hotkey)
        XCTAssertEqual(macro.steps[0].action, .click(.init(x: 3, y: 4)))
        XCTAssertTrue(macro.steps[0].isEnabled)
        XCTAssertFalse(macro.steps[1].isEnabled)
    }

    func testDecodeAcceptsArrayAndSingleMacro() throws {
        let macro = Macro(name: "One", steps: [MacroStep(action: .delay(.init(seconds: 1)))])
        let arrayData = try JSONEncoder().encode([macro])
        XCTAssertEqual(try MacroStore.decode(arrayData), [macro])
        let singleData = try JSONEncoder().encode(macro)
        XCTAssertEqual(try MacroStore.decode(singleData), [macro])
    }

    func testDecodeRejectsGarbage() {
        XCTAssertThrowsError(try MacroStore.decode(Data("{\"hello\": 1}".utf8)))
        XCTAssertThrowsError(try MacroStore.decode(Data("not json".utf8)))
    }

    func testSettingsKeepExplicitlyClearedStopHotkey() throws {
        var settings = AppSettings()
        settings.stopHotkey = nil
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertNil(decoded.stopHotkey)

        let fromEmpty = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(fromEmpty.stopHotkey, AppSettings.defaultStopHotkey)
        XCTAssertEqual(fromEmpty, AppSettings())
    }
}

final class StoreTests: XCTestCase {
    func testSaveAndLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MacroStore(fileURL: directory.appendingPathComponent("nested/macros.json"))

        XCTAssertNil(try store.load())
        let macros = Macro.examples
        try store.save(macros)
        XCTAssertEqual(try store.load(), macros)
    }

    func testQuarantineMovesCorruptFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = MacroStore(fileURL: directory.appendingPathComponent("macros.json"))
        try Data("garbage".utf8).write(to: store.fileURL)

        XCTAssertThrowsError(try store.load())
        let backup = try XCTUnwrap(store.quarantineCorruptFile())
        XCTAssertFalse(store.fileExists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }

    func testImportGetsFreshIDsAndDropsTakenHotkeys() {
        let combo = KeyCombo(keyCode: 18, modifiers: [.control, .option])
        let existing = [Macro(name: "Existing", hotkey: combo)]
        let incoming = [
            Macro(name: "Clash", hotkey: combo),
            Macro(name: "Free", hotkey: KeyCombo(keyCode: 19, modifiers: .command)),
        ]
        let prepared = MacroStore.prepareForImport(incoming, existing: existing)
        XCTAssertEqual(prepared.map(\.name), ["Clash", "Free"])
        XCTAssertNil(prepared[0].hotkey)
        XCTAssertEqual(prepared[1].hotkey, incoming[1].hotkey)
        XCTAssertNotEqual(prepared[1].id, incoming[1].id)
    }
}

final class SummaryTests: XCTestCase {
    func testSummaries() {
        XCTAssertEqual(MacroAction.keyPress(.init(keyCode: 8, modifiers: .command)).summary, "Press ⌘C")
        XCTAssertEqual(MacroAction.delay(.init(seconds: 0.5)).summary, "Wait 0.5 s")
        XCTAssertEqual(MacroAction.delay(.init(seconds: 2)).summary, "Wait 2 s")
        XCTAssertEqual(MacroAction.click(.init(x: 10.4, y: 20.6)).summary, "Click at (10, 21)")
        XCTAssertEqual(MacroAction.click(.init(count: 2, atCurrentPosition: true)).summary, "Double-click at pointer")
        XCTAssertEqual(MacroAction.typeText(.init(text: "a\nb")).summary, "Type “a⏎b”")
        XCTAssertEqual(MacroAction.openApp(.init(path: "/Applications/Safari.app")).summary, "Open Safari")
        XCTAssertEqual(MacroAction.scroll(.init(dx: 0, dy: -200)).summary, "Scroll down 200")
    }

    func testKeyComboDisplay() {
        XCTAssertEqual(KeyCombo(keyCode: 47, modifiers: [.command, .control, .option]).displayString, "⌃⌥⌘.")
        XCTAssertEqual(KeyCombo(keyCode: 36, modifiers: .shift).displayString, "⇧↩")
        XCTAssertEqual(KeyCombo(keyCode: 122).displayString, "F1")
    }

    func testIdentifiableSubscript() {
        var macros = [Macro(name: "A"), Macro(name: "B")]
        let id = macros[1].id
        macros[id: id]?.name = "Renamed"
        XCTAssertEqual(macros[1].name, "Renamed")
        macros[id: id] = nil
        XCTAssertEqual(macros.map(\.name), ["A"])
        XCTAssertNil(macros[id: UUID()])
    }
}

// MARK: - Runner

private final class FakePerformer: MacroPerformer, @unchecked Sendable {
    private let lock = NSLock()
    private var _performed: [MacroAction] = []
    var failOn: MacroAction.Kind?
    var onPerform: (() -> Void)?

    var performed: [MacroAction] {
        lock.lock(); defer { lock.unlock() }
        return _performed
    }

    private func record(_ action: MacroAction) {
        lock.lock(); defer { lock.unlock() }
        _performed.append(action)
    }

    func perform(_ action: MacroAction) async throws {
        record(action)
        onPerform?()
        if action.kind == failOn { throw NSError(domain: "test", code: 1) }
        await Task.yield()
    }
}

private final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func add(_ value: Double) { lock.lock(); values.append(value); lock.unlock() }
    var all: [Double] { lock.lock(); defer { lock.unlock() }; return values }
}

final class RunnerTests: XCTestCase {
    private let a = MacroAction.typeText(.init(text: "a"))
    private let b = MacroAction.keyPress(.init(keyCode: 36))

    func testRepeatsAndSkipsDisabledSteps() async throws {
        let macro = Macro(name: "m", steps: [
            MacroStep(action: a),
            MacroStep(action: .typeText(.init(text: "skip")), isEnabled: false),
            MacroStep(action: b),
        ], repeatCount: 3)
        let performer = FakePerformer()
        try await MacroRunner.run(macro, performer: performer, sleep: { _ in })
        XCTAssertEqual(performer.performed, [a, b, a, b, a, b])
    }

    func testSpeedScalesWaits() async throws {
        let macro = Macro(name: "m", steps: [
            MacroStep(action: .delay(.init(seconds: 2))),
            MacroStep(action: a),
            MacroStep(action: .delay(.init(seconds: 1))),
        ], speed: 4)
        let log = SleepLog()
        let performer = FakePerformer()
        try await MacroRunner.run(macro, performer: performer, sleep: { log.add($0) })
        XCTAssertEqual(log.all, [0.5, 0.25])
        XCTAssertEqual(performer.performed, [a])
    }

    func testReportsProgress() async throws {
        let steps = [MacroStep(action: a), MacroStep(action: b)]
        let macro = Macro(name: "m", steps: steps, repeatCount: 2)
        let log = ProgressLog()
        try await MacroRunner.run(macro, performer: FakePerformer(), sleep: { _ in }, onStep: { log.add($0) })
        XCTAssertEqual(log.all.map(\.stepID), [steps[0].id, steps[1].id, steps[0].id, steps[1].id])
        XCTAssertEqual(log.all.map(\.iteration), [0, 0, 1, 1])
    }

    func testEmptyMacroDoesNothing() async throws {
        let performer = FakePerformer()
        try await MacroRunner.run(Macro(name: "empty"), performer: performer)
        XCTAssertTrue(performer.performed.isEmpty)
    }

    func testPerformerErrorStopsRun() async {
        let macro = Macro(name: "m", steps: [MacroStep(action: a), MacroStep(action: b), MacroStep(action: a)])
        let performer = FakePerformer()
        performer.failOn = .keyPress
        do {
            try await MacroRunner.run(macro, performer: performer, sleep: { _ in })
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(performer.performed, [a, b])
        }
    }

    func testLoopForeverStopsWhenCancelled() async throws {
        let macro = Macro(name: "loop", steps: [MacroStep(action: a)], repeatCount: 0)
        let performer = FakePerformer()
        let task = Task {
            try await MacroRunner.run(macro, performer: performer, sleep: { _ in await Task.yield() })
        }
        // Let it spin for a moment, then cancel.
        while performer.performed.count < 25 { await Task.yield() }
        task.cancel()
        do {
            try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertGreaterThanOrEqual(performer.performed.count, 25)
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [RunProgress] = []
    func add(_ value: RunProgress) { lock.lock(); values.append(value); lock.unlock() }
    var all: [RunProgress] { lock.lock(); defer { lock.unlock() }; return values }
}

// MARK: - Recording

final class RecordingBuilderTests: XCTestCase {
    private func key(_ code: UInt16, _ chars: String?, _ mods: KeyModifiers = [], at time: Double) -> RecordedEvent {
        .keyDown(keyCode: code, modifiers: mods, characters: chars, time: time)
    }

    func testTypingIsMergedIntoText() {
        var builder = RecordingBuilder()
        builder.add(key(4, "h", at: 0.0))
        builder.add(key(34, "i", at: 0.1))
        builder.add(key(49, " ", at: 0.2))
        builder.add(key(0, "A", .shift, at: 0.3))
        XCTAssertEqual(builder.finish().map(\.action), [.typeText(.init(text: "hi A"))])
    }

    func testShortcutsAndSpecialKeysBecomeKeyPresses() {
        var builder = RecordingBuilder(options: RecordingOptions(recordDelays: false))
        builder.add(key(4, "h", at: 0))
        builder.add(key(36, "\r", at: 0.1))
        builder.add(key(8, "c", .command, at: 0.2))
        builder.add(key(123, "\u{F702}", at: 0.3))
        builder.add(key(56, nil, .shift, at: 0.35)) // a bare modifier key is ignored
        XCTAssertEqual(builder.finish().map(\.action), [
            .typeText(.init(text: "h")),
            .keyPress(.init(keyCode: 36)),
            .keyPress(.init(keyCode: 8, modifiers: .command)),
            .keyPress(.init(keyCode: 123)),
        ])
    }

    func testPausesBecomeWaitsAndShortOnesAreDropped() {
        var builder = RecordingBuilder(options: RecordingOptions(minimumDelay: 0.05, maximumDelay: 5))
        builder.add(key(36, "\r", at: 10.0))
        builder.add(key(36, "\r", at: 10.02))   // 20 ms: dropped
        builder.add(key(36, "\r", at: 11.524))  // ~1.5 s
        builder.add(key(36, "\r", at: 60))      // capped at 5 s
        let ret = MacroAction.keyPress(.init(keyCode: 36))
        XCTAssertEqual(builder.finish().map(\.action), [
            ret, ret, .delay(.init(seconds: 1.5)), ret, .delay(.init(seconds: 5)), ret,
        ])
    }

    func testLongPauseSplitsTyping() {
        var builder = RecordingBuilder()
        builder.add(key(4, "a", at: 0))
        builder.add(key(4, "b", at: 3))
        XCTAssertEqual(builder.finish().map(\.action), [
            .typeText(.init(text: "a")), .delay(.init(seconds: 3)), .typeText(.init(text: "b")),
        ])
    }

    func testClickDoubleClickAndDrag() {
        var builder = RecordingBuilder(options: RecordingOptions(recordDelays: false))
        // Single click
        builder.add(.mouseDown(button: .left, x: 100, y: 100, clickCount: 1, modifiers: [], time: 0))
        builder.add(.mouseUp(button: .left, x: 101, y: 100, time: 0.05))
        // Double click elsewhere
        builder.add(.mouseDown(button: .left, x: 300, y: 300, clickCount: 1, modifiers: [], time: 1))
        builder.add(.mouseUp(button: .left, x: 300, y: 300, time: 1.05))
        builder.add(.mouseDown(button: .left, x: 300, y: 301, clickCount: 2, modifiers: [], time: 1.2))
        builder.add(.mouseUp(button: .left, x: 300, y: 301, time: 1.25))
        // Drag
        builder.add(.mouseDown(button: .left, x: 0, y: 0, clickCount: 1, modifiers: [], time: 2))
        builder.add(.mouseUp(button: .left, x: 200, y: 50, time: 2.5))
        // ⌘ right click
        builder.add(.mouseDown(button: .right, x: 5, y: 5, clickCount: 1, modifiers: .command, time: 3))
        builder.add(.mouseUp(button: .right, x: 5, y: 5, time: 3.1))

        XCTAssertEqual(builder.finish().map(\.action), [
            .click(.init(x: 100, y: 100)),
            .click(.init(x: 300, y: 300, count: 2)),
            .drag(.init(fromX: 0, fromY: 0, toX: 200, toY: 50, duration: 0.5)),
            .click(.init(x: 5, y: 5, button: .right, modifiers: .command)),
        ])
    }

    func testDoubleClickMergeRemovesWaitInBetween() {
        var builder = RecordingBuilder(options: RecordingOptions(minimumDelay: 0.05))
        builder.add(.mouseDown(button: .left, x: 10, y: 10, clickCount: 1, modifiers: [], time: 0))
        builder.add(.mouseUp(button: .left, x: 10, y: 10, time: 0.05))
        builder.add(.mouseDown(button: .left, x: 10, y: 10, clickCount: 2, modifiers: [], time: 0.25))
        builder.add(.mouseUp(button: .left, x: 10, y: 10, time: 0.3))
        XCTAssertEqual(builder.finish().map(\.action), [.click(.init(x: 10, y: 10, count: 2))])
    }

    func testUnreleasedPressIsDropped() {
        var builder = RecordingBuilder()
        builder.add(key(36, "\r", at: 0))
        builder.add(.mouseDown(button: .left, x: 1, y: 1, clickCount: 1, modifiers: [], time: 2))
        XCTAssertEqual(builder.finish().map(\.action), [.keyPress(.init(keyCode: 36))])
    }

    func testScrollBurstsAreMerged() {
        var builder = RecordingBuilder()
        builder.add(.scroll(dx: 0, dy: -10, time: 0))
        builder.add(.scroll(dx: 0, dy: -15, time: 0.05))
        builder.add(.scroll(dx: 2, dy: -5, time: 0.1))
        builder.add(.scroll(dx: 0, dy: 40, time: 2.1))
        XCTAssertEqual(builder.finish().map(\.action), [
            .scroll(.init(dx: 2, dy: -30)), .delay(.init(seconds: 2)), .scroll(.init(dx: 0, dy: 40)),
        ])
    }

    func testTypeableText() {
        XCTAssertEqual(RecordingBuilder.typeableText("é", modifiers: .option), "é")
        XCTAssertNil(RecordingBuilder.typeableText("c", modifiers: .command))
        XCTAssertNil(RecordingBuilder.typeableText("\t", modifiers: []))
        XCTAssertNil(RecordingBuilder.typeableText("", modifiers: []))
        XCTAssertNil(RecordingBuilder.typeableText(nil, modifiers: []))
    }
}
