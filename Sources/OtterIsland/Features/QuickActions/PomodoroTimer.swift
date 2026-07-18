import Foundation
import Combine

/// Minuteur Pomodoro simple (25 min de focus) affiché dans le panneau Loutre.
@MainActor
final class PomodoroTimer: ObservableObject {
    @Published private(set) var remaining: TimeInterval
    @Published private(set) var isRunning = false

    let workDuration: TimeInterval = 25 * 60
    private var timer: Timer?

    init() {
        remaining = 25 * 60
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        remaining = workDuration
    }

    private func tick() {
        remaining = max(0, remaining - 1)
        if remaining == 0 { pause() }
    }

    var display: String {
        let total = Int(remaining)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
