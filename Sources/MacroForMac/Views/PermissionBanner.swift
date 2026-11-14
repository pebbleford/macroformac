import AppKit
import SwiftUI

/// Shown at the top of the editor until Accessibility access is working.
struct PermissionBanner: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 8) {
            if UIProbe.variant == 5 {
                EmptyView()
            } else {
            if Permissions.isTranslocated {
                notice(
                    symbol: "folder.badge.questionmark",
                    title: "Move MacroForMac to your Applications folder",
                    message: "It's running straight from the download, where macOS doesn't keep its permissions reliably. Quit it, drag MacroForMac into Applications, and open it from there."
                ) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
            }

            if !app.accessibilityGranted {
                notice(
                    symbol: "lock.shield",
                    title: app.accessibilityWasLost
                        ? "macOS turned off MacroForMac's access after the update"
                        : "Turn on Accessibility for MacroForMac",
                    message: app.accessibilityWasLost
                        ? "Each new version counts as a new app to macOS, even if the switch in System Settings still looks on. Click Fix Permission, then switch MacroForMac on in the list that opens."
                        : "MacroForMac needs it to press keys, click and record. Click Fix Permission, then switch MacroForMac on in the list that opens. Already on? Click Fix Permission anyway: it clears the old entry so macOS recognises this copy."
                ) {
                    Button("Fix Permission") { app.fixAccessibility() }
                        .buttonStyle(.borderedProminent)
                    Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                    Button("Restart MacroForMac") { Permissions.relaunch() }
                        .help("Quit and reopen, in case macOS only applies the change after a restart")
                }
            }
            }
        }
        .padding([.horizontal, .top], Permissions.isTranslocated || !app.accessibilityGranted ? 12 : 0)
    }

    private func notice<Buttons: View>(
        symbol: String,
        title: String,
        message: String,
        @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    buttons()
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
