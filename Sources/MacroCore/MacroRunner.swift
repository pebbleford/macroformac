import Foundation

/// Performs a single action. The macOS app implements this with CGEvent, NSWorkspace and Process;
/// tests use a recording fake.
public protocol MacroPerformer: AnyObject {
    func perform(_ action: MacroAction) async throws
}

public struct RunProgress: Sendable, Equatable {
    /// Zero-based pass number.
    public var iteration: Int
    /// Index of the step in `macro.steps`.
    public var stepIndex: Int
    public var stepID: UUID
}

/// Sequences a macro's steps: repeats, speed, disabled steps and cancellation.
public enum MacroRunner {
    /// Longest single wait honoured (one week) to keep nanosecond math in range.
    public static let maximumWait: Double = 7 * 24 * 60 * 60

    public static func defaultSleep(_ seconds: Double) async throws {
        let clamped = min(max(0, seconds), maximumWait)
        try await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
    }

    /// Runs the macro until it finishes or the surrounding task is cancelled
    /// (then throws `CancellationError`). Errors thrown by the performer stop the run.
    public static func run(
        _ macro: Macro,
        performer: MacroPerformer,
        sleep: @escaping @Sendable (Double) async throws -> Void = MacroRunner.defaultSleep,
        onStep: @escaping @Sendable (RunProgress) -> Void = { _ in }
    ) async throws {
        let speed = macro.speed > 0 ? macro.speed : 1
        let steps = macro.steps.enumerated().filter { $0.element.isEnabled }
        guard !steps.isEmpty else { return }

        var iteration = 0
        while macro.loopsForever || iteration < macro.repeatCount {
            for (index, step) in steps {
                try Task.checkCancellation()
                onStep(RunProgress(iteration: iteration, stepIndex: index, stepID: step.id))
                if case .delay(let wait) = step.action {
                    try await sleep(wait.seconds / speed)
                } else {
                    try await performer.perform(step.action)
                }
            }
            iteration += 1
            if macro.loopsForever {
                // Keep endless loops from spinning flat out and stay responsive to cancellation.
                try await sleep(0.01)
            }
        }
        try Task.checkCancellation()
    }
}
