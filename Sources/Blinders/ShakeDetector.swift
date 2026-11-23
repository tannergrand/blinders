import AppKit

/// Menu presets, picked from `--shake-bench`. All need four quick turns inside
/// 0.6 s with no leg slower than 0.3 s; they differ only in how far each leg travels.
enum ShakeSensitivity: String, CaseIterable {
    case high, medium, low

    var title: String { rawValue.capitalized }
    var minLeg: CGFloat {
        switch self { case .high: 25; case .medium: 35; case .low: 70 }
    }
}

/// Detects a deliberate cursor shake, side to side or up and down, from a
/// stream of positions. Pure logic, so --selftest can drive it with synthetic input.
struct ShakeDetector {
    /// Each leg of the shake must travel at least this far (points).
    var minLeg: CGFloat = 35
    /// Movement back toward the start smaller than this is jitter, not a turn.
    var turnSlack: CGFloat = 8
    /// All counted turns must fall inside this window (seconds).
    var window: TimeInterval = 0.6
    var requiredTurns = 4
    var cooldown: TimeInterval = 1.0
    /// A leg slower than this is a deliberate sweep (selecting text, dragging a
    /// scrollbar), not a shake, and starts the count over.
    var maxLegTime: TimeInterval = 0.3

    init(sensitivity: ShakeSensitivity = .medium) {
        minLeg = sensitivity.minLeg
    }

    private var horizontal = Axis()
    private var vertical = Axis()
    private var lastFire: TimeInterval = -.greatestFiniteMagnitude

    /// Returns true on the sample that completes a shake on either axis.
    mutating func feed(x: CGFloat, y: CGFloat, t: TimeInterval) -> Bool {
        let h = horizontal.feed(x, t: t, config: self)
        let v = vertical.feed(y, t: t, config: self)
        guard h || v, t - lastFire > cooldown else { return false }
        horizontal.reset()
        vertical.reset()
        lastFire = t
        return true
    }

    /// Counts direction reversals along one axis.
    private struct Axis {
        private var direction = 0          // +1 or -1 along the axis, 0 unknown
        private var legStart: CGFloat = 0
        private var legStartTime: TimeInterval = 0
        private var extreme: CGFloat = 0
        private var turns: [TimeInterval] = []
        private var started = false
        private var lastTime: TimeInterval = 0

        mutating func reset() { turns.removeAll() }

        /// True once enough wide, quick turns have landed inside the window.
        mutating func feed(_ v: CGFloat, t: TimeInterval, config c: ShakeDetector) -> Bool {
            defer { lastTime = t }
            // A long pause means a fresh gesture.
            if !started || t - lastTime > c.window {
                started = true
                direction = 0
                legStart = v
                extreme = v
                turns.removeAll()
                return false
            }
            if direction == 0 {
                if abs(v - legStart) > c.turnSlack {
                    direction = v > legStart ? 1 : -1
                    extreme = v
                    legStartTime = t
                }
                return false
            }
            let further = direction == 1 ? v > extreme : v < extreme
            if further {
                extreme = v
                return false
            }
            guard abs(v - extreme) > c.turnSlack else { return false }

            // The cursor turned around.
            if abs(extreme - legStart) >= c.minLeg && t - legStartTime <= c.maxLegTime {
                turns.append(t)
            } else {
                turns.removeAll()
            }
            legStart = extreme
            legStartTime = t
            extreme = v
            direction = -direction
            turns.removeAll { t - $0 > c.window }
            return turns.count >= c.requiredTurns
        }
    }
}

/// Feeds global mouse-move events into a ShakeDetector.
/// Mouse-move monitoring needs no Accessibility permission (only key events do).
final class ShakeWatcher {
    var onShake: (() -> Void)?
    var isEnabled = false {
        didSet { isEnabled ? start() : stop() }
    }

    var sensitivity: ShakeSensitivity = .medium {
        didSet { detector = ShakeDetector(sensitivity: sensitivity) }
    }

    private var detector = ShakeDetector()
    private var monitors: [Any] = []

    private func start() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] e in
            self?.feed(e)
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] e in
            self?.feed(e)
            return e
        }) {
            monitors.append(local)
        }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        detector = ShakeDetector(sensitivity: sensitivity)
    }

    private func feed(_ event: NSEvent) {
        let p = NSEvent.mouseLocation
        if detector.feed(x: p.x, y: p.y, t: event.timestamp) {
            onShake?()
        }
    }
}
