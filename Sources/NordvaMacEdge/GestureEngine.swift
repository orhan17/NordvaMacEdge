import CoreGraphics
import Foundation
import NordvaMacEdgeCore

final class GestureEngine {
    private static let clickSuppressWindow = 0.35

    private let lock = NSLock()
    private let hold = PointerHold()
    private var recognizer = EdgeGestureRecognizer()
    private var enabled = true
    private var lastFrameAt = DispatchTime.now()
    private var lastTimestamp = 0.0
    private var previousTouchCount = 0
    private var suppressClicksUntil = 0.0
    private let onEvent: (GestureEvent) -> Void

    init(onEvent: @escaping (GestureEvent) -> Void) {
        self.onEvent = onEvent
    }

    var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set {
            lock.withLock {
                enabled = newValue
                if !newValue { finish() }
            }
        }
    }

    func process(_ touches: [TouchPoint], at timestamp: Double) {
        lock.lock()
        defer { lock.unlock() }
        lastFrameAt = .now()
        lastTimestamp = timestamp
        guard enabled else { return }

        if Log.isEnabled, touches.count != previousTouchCount {
            let list = touches.map { String(format: "#%d x=%.3f y=%.3f", $0.id, $0.x, $0.y) }
            Log.debug("fingers \(touches.count): \(list.joined(separator: ", "))")
        }
        previousTouchCount = touches.count

        let events = recognizer.process(
            touches,
            at: timestamp,
            isButtonDown: CGEventSource.buttonState(.combinedSessionState, button: .left)
        )
        hold.update(hold: recognizer.holdsPointer)
        dispatch(events)
    }

    func setActiveCorners(_ corners: Set<Corner>) {
        lock.withLock { recognizer.config.activeCorners = corners }
    }

    func setBottomEdgeEnabled(_ enabled: Bool) {
        lock.withLock { recognizer.config.bottomEdgeEnabled = enabled }
    }

    func shouldSuppressClick() -> Bool {
        lock.withLock { ProcessInfo.processInfo.systemUptime < suppressClicksUntil }
    }

    func reset() {
        lock.withLock { finish() }
    }

    /// If frames stop mid-gesture (sleep, device gone), the pointer would stay frozen
    /// and Command could stay pressed, so the gesture is ended here.
    func releaseIfStalled() {
        lock.withLock {
            guard recognizer.holdsPointer else { return }
            let elapsed = DispatchTime.now().uptimeNanoseconds - lastFrameAt.uptimeNanoseconds
            if elapsed > 1_000_000_000 {
                Log.debug("frames stopped mid-gesture, releasing the pointer")
                finish()
            }
        }
    }

    private func dispatch(_ events: [GestureEvent]) {
        for event in events {
            switch event {
            case let .tapped(corner):
                suppressClicksUntil = ProcessInfo.processInfo.systemUptime + Self.clickSuppressWindow
                Log.debug("tap: \(corner.rawValue)")
            case let .doubleTapped(corner):
                Log.debug("double-tap: \(corner.rawValue)")
            case .began, .moved, .ended:
                break
            }
            onEvent(event)
        }
    }

    private func finish() {
        dispatch(recognizer.process([], at: lastTimestamp, isButtonDown: false))
        recognizer.reset()
        hold.update(hold: false)
        previousTouchCount = 0
    }
}
