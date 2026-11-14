import AppKit
import SwiftUI
import MacroCore

/// Small floating "● Recording" bar that stays visible while MacroForMac is hidden.
@MainActor
final class RecordingPanelController {
    private let panel: NSPanel

    init(state: AppState) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.canHide = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hosting = FirstMouseHostingView(rootView: RecordingPanelView().environmentObject(state))
        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = hosting
    }

    func show() {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12))
        }
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

/// Lets the Stop button work on the first click even though the panel never becomes key.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct RecordingPanelView: View {
    @EnvironmentObject private var app: AppState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }

            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.periodic(from: app.recordingStartedAt, by: 1)) { context in
                    Text("Recording  \(Self.elapsed(since: app.recordingStartedAt, now: context.date))")
                        .font(.system(.headline, design: .rounded).monospacedDigit())
                }
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Cancel") { app.stopRecording(keep: false) }
            Button("Stop") { app.stopRecording(keep: true) }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(.horizontal, 16)
        .frame(width: 380, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.15)))
    }

    private var hint: String {
        let steps = "\(app.recordedStepCount) step\(app.recordedStepCount == 1 ? "" : "s")"
        if let stop = app.settings.stopHotkey {
            return "\(steps) · press \(stop.displayString) to stop"
        }
        return steps
    }

    static func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
