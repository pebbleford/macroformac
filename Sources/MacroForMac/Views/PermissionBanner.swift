import SwiftUI

/// Shown at the top of the editor until Accessibility access is granted.
struct PermissionBanner: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        if !app.accessibilityGranted {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Accessibility access")
                        .font(.headline)
                    Text("MacroForMac needs it to press keys, click and record for you. Turn on MacroForMac in System Settings → Privacy & Security → Accessibility. This banner disappears once it's on.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Request Access") { Permissions.requestAccessibility() }
                        Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .padding([.horizontal, .top], 12)
        }
    }
}
