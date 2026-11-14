import ServiceManagement
import SwiftUI
import MacroCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            RecordingSettings()
                .tabItem { Label("Recording", systemImage: "record.circle") }
            PermissionSettings()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 520, height: 360)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var app: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            LabeledContent("Stop all macros") {
                HStack {
                    KeyComboField(combo: $app.settings.stopHotkey, placeholder: "None", requiresModifier: true)
                    if app.stopHotkeyConflict {
                        Label("In use by another app", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }

            LabeledContent("Typing speed") {
                VStack(alignment: .leading, spacing: 2) {
                    Slider(value: typingSpeed, in: 0...0.1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Fast").font(.caption)
                    } maximumValueLabel: {
                        Text("Slow").font(.caption)
                    }
                    Text("\(Int((app.settings.typingDelay * 1000).rounded())) ms between characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Hide MacroForMac while running or recording from its window", isOn: $app.settings.hideAppWhileRunning)
                .help("So keystrokes and clicks go to the app you were using")

            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        app.presentAlert("Couldn't change login item", error.localizedDescription)
                    }
                }

            LabeledContent("Library") {
                HStack {
                    Button("Show in Finder") { app.revealLibraryInFinder() }
                    Button("Export All…") { app.exportAll() }
                    Button("Import…") { app.importMacros() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var typingSpeed: Binding<Double> {
        $app.settings.typingDelay
    }
}

private struct RecordingSettings: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Form {
            Toggle("Combine typed characters into “Type Text” steps", isOn: $app.settings.recording.mergeTypedText)
            Toggle("Record pauses as “Wait” steps", isOn: $app.settings.recording.recordDelays)

            if app.settings.recording.recordDelays {
                LabeledContent("Ignore pauses shorter than") {
                    Stepper(value: $app.settings.recording.minimumDelay, in: 0...2, step: 0.05) {
                        Text(String(format: "%.2f s", app.settings.recording.minimumDelay)).monospacedDigit()
                    }
                }
                LabeledContent("Shorten pauses longer than") {
                    Stepper(value: $app.settings.recording.maximumDelay, in: 0...300, step: 1) {
                        Text(app.settings.recording.maximumDelay == 0
                             ? "No limit"
                             : String(format: "%.0f s", app.settings.recording.maximumDelay))
                            .monospacedDigit()
                    }
                }
            }

            Text("While recording, clicks and typing inside MacroForMac itself are ignored. Mouse movement is not recorded — only where you click, drag and scroll.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

private struct PermissionSettings: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Form {
            LabeledContent("Accessibility") {
                HStack {
                    status(app.accessibilityGranted)
                    Button("Open Settings") { Permissions.openAccessibilitySettings() }
                }
            }
            Text("Required to type, press shortcuts, click and record.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Input Monitoring") {
                HStack {
                    status(Permissions.inputMonitoringGranted)
                    Button("Open Settings") { Permissions.openInputMonitoringSettings() }
                }
            }
            Text("Optional. Lets MacroForMac record with a lighter, listen-only event tap.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Automation") {
                Button("Open Settings") { Permissions.openAutomationSettings() }
            }
            Text("Asked for automatically the first time an AppleScript step controls another app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Rebuilt the app yourself? macOS ties permissions to the app's signature, so you may need to remove MacroForMac from the list with “–” and add it again.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private func status(_ granted: Bool) -> some View {
        Label(granted ? "Allowed" : "Not allowed", systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(granted ? .green : .red)
    }
}
