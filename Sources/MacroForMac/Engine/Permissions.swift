import AppKit
import ApplicationServices
import CoreGraphics

/// Accessibility is required to post keystrokes and clicks (playback) and lets us observe input
/// (recording). Input Monitoring alone is also enough for recording.
///
/// macOS remembers these permissions for one exact build of the app. When MacroForMac is updated
/// (or rebuilt), the switch in System Settings can still look "on" while macOS treats the new copy
/// as a different app. `resetAndRequestAccessibility()` clears the stale entry and adds this copy.
enum Permissions {
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static var inputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }

    static var canRecord: Bool {
        accessibilityGranted || inputMonitoringGranted
    }

    /// macOS runs apps opened straight from a download in a temporary, read-only location
    /// ("App Translocation"). Permissions don't stick reliably there.
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    // MARK: Remembering that access was granted

    private static let wasTrustedKey = "MacroForMac.accessibilityWasGranted"

    /// Records that access works for this copy, so a later "not trusted" can be recognised as a
    /// permission macOS dropped after an update rather than one that was never given.
    static func noteAccessibilityGranted() {
        UserDefaults.standard.set(true, forKey: wasTrustedKey)
    }

    static var accessibilityWasGrantedBefore: Bool {
        UserDefaults.standard.bool(forKey: wasTrustedKey)
    }

    // MARK: Requesting

    /// Shows the system prompt and adds the app to the Accessibility list.
    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    /// Clears MacroForMac's entries in Privacy & Security (only this app's), then asks again so
    /// the list shows this exact copy and you just switch it on.
    @MainActor
    static func resetAndRequestAccessibility() async {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.macroformac.MacroForMac"
        await Task.detached(priority: .userInitiated) {
            for service in ["Accessibility", "PostEvent", "ListenEvent"] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                process.arguments = ["reset", service, bundleID]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    NSLog("MacroForMac: tccutil reset \(service) failed: \(error)")
                }
            }
        }.value
        UserDefaults.standard.removeObject(forKey: wasTrustedKey)
        requestAccessibility()
        // Give the system prompt a moment, then show the list with MacroForMac in it.
        try? await Task.sleep(nanoseconds: 600_000_000)
        openAccessibilitySettings()
    }

    /// Quits and reopens MacroForMac (some permission changes only apply after a restart).
    @MainActor
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: System Settings

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    static func openAutomationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}
