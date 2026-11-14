import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers
import MacroCore

/// Central app model: the macro library, playback, recording, hotkeys and settings.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // MARK: Library

    @Published var macros: [Macro] = [] {
        didSet {
            guard !isLoading else { return }
            scheduleSave()
            registerHotkeysIfNeeded()
        }
    }

    @Published var selectedMacroID: Macro.ID?

    @Published var settings: AppSettings {
        didSet {
            saveSettings()
            registerHotkeysIfNeeded()
        }
    }

    // MARK: Status

    @Published private(set) var runningMacroID: Macro.ID?
    @Published private(set) var currentStepID: MacroStep.ID?
    @Published private(set) var isRecording = false
    @Published private(set) var recordingMacroID: Macro.ID?
    @Published private(set) var recordedStepCount = 0
    @Published private(set) var recordingStartedAt = Date()
    @Published private(set) var hotkeyConflicts: Set<Macro.ID> = []
    @Published private(set) var stopHotkeyConflict = false
    @Published private(set) var accessibilityGranted = Permissions.accessibilityGranted

    /// Set by the main window so other parts of the app can bring it back.
    var openMainWindowAction: (() -> Void)?

    private let store = MacroStore(fileURL: MacroStore.defaultFileURL())
    private var isLoading = false
    private var saveTask: Task<Void, Never>?
    private var playbackTask: Task<Void, Never>?
    private var recorder: EventRecorder?
    private var recordingPanel: RecordingPanelController?
    private var createdMacroForRecording = false
    private var registeredHotkeys: HotkeySignature?
    private var hotkeySuspensions = 0
    private var permissionTimer: Timer?

    private struct HotkeySignature: Equatable {
        var stop: KeyCombo?
        var macros: [UUID: KeyCombo]
        var suspended: Bool
    }

    private static let settingsKey = "MacroForMac.settings.v1"

    private init() {
        settings = Self.loadSettings()
        loadMacros()
        registerHotkeysIfNeeded()
        startPermissionPolling()
    }

    var runningMacro: Macro? {
        runningMacroID.flatMap { macros[id: $0] }
    }

    var selectedMacro: Macro? {
        selectedMacroID.flatMap { macros[id: $0] }
    }

    var isBusy: Bool {
        isRecording || runningMacroID != nil
    }

    // MARK: Persistence

    private func loadMacros() {
        isLoading = true
        defer { isLoading = false }
        do {
            if let loaded = try store.load() {
                macros = loaded
            } else {
                macros = Macro.examples
                try? store.save(macros)
            }
        } catch {
            let backup = store.quarantineCorruptFile()
            macros = []
            presentAlert(
                "Couldn't read your macros",
                "\(error.localizedDescription)\n\nThe file was moved to \(backup?.path ?? "a backup") so nothing is lost."
            )
        }
        selectedMacroID = macros.first?.id
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        do {
            try store.save(macros)
        } catch {
            presentAlert("Couldn't save your macros", error.localizedDescription)
        }
    }

    private static func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    var macrosFileURL: URL { store.fileURL }

    // MARK: Editing

    @discardableResult
    func addMacro() -> Macro {
        let macro = Macro(name: uniqueName("New Macro"))
        macros.append(macro)
        selectedMacroID = macro.id
        return macro
    }

    func duplicateMacro(_ id: Macro.ID) {
        guard let index = macros.firstIndex(where: { $0.id == id }) else { return }
        let original = macros[index]
        let copy = original.duplicated(name: uniqueName("\(original.name) Copy"))
        macros.insert(copy, at: index + 1)
        selectedMacroID = copy.id
    }

    func deleteMacro(_ id: Macro.ID) {
        if runningMacroID == id { stopPlayback() }
        if recordingMacroID == id { stopRecording(keep: false) }
        guard let index = macros.firstIndex(where: { $0.id == id }) else { return }
        if selectedMacroID == id {
            let neighbor = index + 1 < macros.count ? macros[index + 1] : (index > 0 ? macros[index - 1] : nil)
            selectedMacroID = neighbor?.id
        }
        macros.remove(at: index)
    }

    func uniqueName(_ base: String) -> String {
        let names = Set(macros.map(\.name))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    // MARK: Playback

    func runSelected() {
        if let id = selectedMacroID { run(id) }
    }

    func run(_ id: Macro.ID, fromHotkey: Bool = false) {
        guard !isRecording, playbackTask == nil else {
            NSSound.beep()
            return
        }
        guard let macro = macros[id: id] else { return }
        guard macro.steps.contains(where: \.isEnabled) else {
            presentAlert("“\(macro.name)” has no steps", "Add a step or record some input first.")
            return
        }
        if macro.needsInputEvents && !Permissions.accessibilityGranted {
            Permissions.requestAccessibility()
            presentAlert(
                "Accessibility access needed",
                "To type and click for you, MacroForMac needs Accessibility access. Turn it on in System Settings → Privacy & Security → Accessibility, then run the macro again.",
                action: .openAccessibility
            )
            return
        }

        // When started from MacroForMac's own window, step aside so the input reaches the app
        // you were using before.
        let hideFirst = !fromHotkey && NSApp.isActive && settings.hideAppWhileRunning
        let performer = EventPerformer(typingDelay: settings.typingDelay)
        let reportStep: @Sendable (RunProgress) -> Void = { progress in
            Task { @MainActor in
                guard self.runningMacroID == id else { return }
                self.currentStepID = progress.stepID
            }
        }

        runningMacroID = id
        currentStepID = nil
        playbackTask = Task {
            if hideFirst {
                NSApp.hide(nil)
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            await Self.waitForModifierKeysReleased()

            var failure: Error?
            do {
                try await MacroRunner.run(macro, performer: performer, onStep: reportStep)
            } catch is CancellationError {
                // Stopped by the user.
            } catch {
                failure = error
            }

            self.runningMacroID = nil
            self.currentStepID = nil
            self.playbackTask = nil
            if let failure {
                self.presentAlert("“\(macro.name)” stopped", failure.localizedDescription)
            }
        }
    }

    func stopPlayback() {
        playbackTask?.cancel()
    }

    func toggleRun(_ id: Macro.ID) {
        if runningMacroID == id {
            stopPlayback()
        } else {
            run(id)
        }
    }

    /// A macro triggered by its shortcut while the user still holds the modifier keys would
    /// otherwise type "shortcuts" instead of text. Wait (briefly) for them to be released.
    nonisolated private static func waitForModifierKeysReleased() async {
        let modifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        for _ in 0..<100 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: Recording

    func toggleRecording() {
        if isRecording {
            stopRecording(keep: true)
        } else {
            startRecording(into: selectedMacroID)
        }
    }

    /// Records input and appends it to `macroID`, or to a new macro when nil.
    func startRecording(into macroID: Macro.ID?) {
        guard !isRecording else { return }
        guard playbackTask == nil else {
            NSSound.beep()
            return
        }
        guard Permissions.canRecord else {
            Permissions.requestAccessibility()
            presentAlert(
                "Permission needed to record",
                "To record your keyboard and mouse, MacroForMac needs Accessibility access (System Settings → Privacy & Security → Accessibility). Turn it on, then start recording again.",
                action: .openAccessibility
            )
            return
        }

        let recorder = EventRecorder(options: settings.recording)
        recorder.ignoredCombos = [settings.stopHotkey].compactMap { $0 }
        recorder.onStepCountChange = { count in
            self.recordedStepCount = count
        }
        do {
            try recorder.start()
        } catch {
            Permissions.requestInputMonitoring()
            presentAlert("Couldn't start recording", error.localizedDescription, action: .openInputMonitoring)
            return
        }

        let targetID: Macro.ID
        if let macroID, macros[id: macroID] != nil {
            targetID = macroID
            createdMacroForRecording = false
        } else {
            let macro = Macro(name: uniqueName("Recorded Macro"))
            macros.append(macro)
            targetID = macro.id
            createdMacroForRecording = true
        }

        self.recorder = recorder
        recordingMacroID = targetID
        selectedMacroID = targetID
        recordedStepCount = 0
        recordingStartedAt = Date()
        isRecording = true

        let panel = RecordingPanelController(state: self)
        panel.show()
        recordingPanel = panel

        if settings.hideAppWhileRunning && NSApp.isActive {
            NSApp.hide(nil)
        }
    }

    /// Ends recording. With `keep` the captured steps are appended to the macro.
    func stopRecording(keep: Bool) {
        guard isRecording, let recorder else { return }
        let steps = recorder.stop()
        self.recorder = nil
        isRecording = false
        recordingPanel?.close()
        recordingPanel = nil

        if let id = recordingMacroID {
            if keep && !steps.isEmpty {
                macros[id: id]?.steps.append(contentsOf: steps)
            } else if createdMacroForRecording {
                deleteMacro(id)
            }
        }
        recordingMacroID = nil
        createdMacroForRecording = false
        recordedStepCount = 0

        showMainWindow()
    }

    // MARK: Hotkeys

    /// Shortcut fields call this while they capture keys so existing shortcuts don't fire.
    func suspendHotkeys(_ suspend: Bool) {
        hotkeySuspensions = max(0, hotkeySuspensions + (suspend ? 1 : -1))
        registerHotkeysIfNeeded()
    }

    private func registerHotkeysIfNeeded() {
        var map: [UUID: KeyCombo] = [:]
        for macro in macros {
            if let hotkey = macro.hotkey { map[macro.id] = hotkey }
        }
        let signature = HotkeySignature(stop: settings.stopHotkey, macros: map, suspended: hotkeySuspensions > 0)
        guard signature != registeredHotkeys else { return }
        registeredHotkeys = signature

        let center = HotkeyCenter.shared
        center.unregisterAll()
        guard !signature.suspended else { return }

        var used = Set<KeyCombo>()
        var stopConflict = false
        if let stop = settings.stopHotkey {
            stopConflict = !center.register(stop) { [unowned self] in self.stopHotkeyPressed() }
            used.insert(stop)
        }

        var conflicts = Set<Macro.ID>()
        for macro in macros {
            guard let combo = macro.hotkey else { continue }
            let id = macro.id
            if used.contains(combo) || !center.register(combo, handler: { [unowned self] in self.macroHotkeyPressed(id) }) {
                conflicts.insert(id)
            } else {
                used.insert(combo)
            }
        }
        if conflicts != hotkeyConflicts { hotkeyConflicts = conflicts }
        if stopConflict != stopHotkeyConflict { stopHotkeyConflict = stopConflict }
    }

    private func macroHotkeyPressed(_ id: Macro.ID) {
        if runningMacroID == id {
            stopPlayback()
        } else if isRecording || runningMacroID != nil {
            NSSound.beep()
        } else {
            run(id, fromHotkey: true)
        }
    }

    private func stopHotkeyPressed() {
        if isRecording {
            stopRecording(keep: true)
        } else {
            stopPlayback()
        }
    }

    // MARK: Import / export

    func importMacros() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose macro files exported from MacroForMac"
        guard panel.runModal() == .OK else { return }

        var imported: [Macro] = []
        for url in panel.urls {
            do {
                imported += try MacroStore.decode(Data(contentsOf: url))
            } catch {
                presentAlert("Couldn't import “\(url.lastPathComponent)”", error.localizedDescription)
                return
            }
        }
        let prepared = MacroStore.prepareForImport(imported, existing: macros)
        macros.append(contentsOf: prepared)
        selectedMacroID = prepared.first?.id ?? selectedMacroID
    }

    func exportMacros(_ ids: [Macro.ID]) {
        let chosen = macros.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let baseName = chosen.count == 1 ? chosen[0].name : "Macros"
        panel.nameFieldStringValue = baseName.replacingOccurrences(of: "/", with: "-") + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MacroStore.encode(chosen).write(to: url, options: .atomic)
        } catch {
            presentAlert("Couldn't export", error.localizedDescription)
        }
    }

    func exportAll() {
        exportMacros(macros.map(\.id))
    }

    func revealLibraryInFinder() {
        saveNow()
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    // MARK: Windows & alerts

    func showMainWindow() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindowAction?()
        }
    }

    enum AlertAction {
        case openAccessibility
        case openInputMonitoring

        var title: String {
            switch self {
            case .openAccessibility: return "Open Accessibility Settings"
            case .openInputMonitoring: return "Open Input Monitoring Settings"
            }
        }

        func perform() {
            switch self {
            case .openAccessibility: Permissions.openAccessibilitySettings()
            case .openInputMonitoring: Permissions.openInputMonitoringSettings()
            }
        }
    }

    func presentAlert(_ title: String, _ message: String, action: AlertAction? = nil) {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            if let action {
                alert.addButton(withTitle: action.title)
                alert.addButton(withTitle: "Not Now")
            } else {
                alert.addButton(withTitle: "OK")
            }
            let response = alert.runModal()
            if let action, response == .alertFirstButtonReturn {
                action.perform()
            }
        }
    }

    // MARK: Permissions

    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                AppState.shared.refreshPermissions()
            }
        }
    }

    func refreshPermissions() {
        let granted = Permissions.accessibilityGranted
        if granted != accessibilityGranted { accessibilityGranted = granted }
    }
}
