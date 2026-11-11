import Foundation
import NordvaMacEdgeCore

/// A CoreAudio volume write takes ~16 ms while frames arrive every ~11 ms. Writing every
/// value queues them up and the volume lags behind the finger, so the level is computed
/// right away and only the latest value is written.
final class LevelController {
    private let minimumStep: Float = 1.0 / 200

    private let volume = VolumeControl()
    private let brightness = Brightness()
    private let hud: HUD
    private let settings: Settings
    private let haptics: Haptics

    private var sensitivity: Float = 1.6
    private var kind = LevelKind.volume
    private var control: LevelControl?
    private var level: Float?
    private var lastSubmitted: Float = 0

    private let io = DispatchQueue(label: "nordvamacedge.io")
    private let pendingLock = NSLock()
    private var pending: [ObjectIdentifier: (control: LevelControl, value: Float)] = [:]
    private var draining = false

    init(hud: HUD, settings: Settings, haptics: Haptics) {
        self.hud = hud
        self.settings = settings
        self.haptics = haptics
    }

    func handle(_ event: GestureEvent) {
        switch event {
        case let .began(edge):
            kind = settings.kind(for: edge)
            sensitivity = Float(settings.sensitivity)
            if kind == .volume {
                control = volume
                level = volume.read()
            } else {
                (control, level) = brightness.underPointer()
            }
            lastSubmitted = level ?? 0
            Log.debug("slide began: edge \(edge.rawValue), \(kind) via \(control.map { "\(type(of: $0))" } ?? "none"), level \(describe(level))")
            show(kind, at: edge, level: level)

        case let .moved(edge, delta):
            guard let current = level, let control else { return }
            let next = min(1, max(0, current + Float(delta) * sensitivity))
            level = next
            if let click = haptic(from: Double(current), to: Double(next)) {
                haptics.play(click)
            }
            if abs(next - lastSubmitted) >= minimumStep || ((next == 0 || next == 1) && next != lastSubmitted) {
                submit(next, to: control)
                lastSubmitted = next
            }
            show(kind, at: edge, level: next)

        case .ended:
            Log.debug("slide ended, level \(describe(level))")
            level = nil
            control = nil
            DispatchQueue.main.async { [hud] in hud.hideSoon() }

        case .tapped:
            break

        case let .doubleTapped(corner):
            io.async { [self] in runAction(for: corner) }
        }
    }

    private func runAction(for corner: Corner) {
        if corner.isTop {
            let display = brightness.underPointer().control
            submit(1, to: display)
            Log.debug("double-tap: brightness to 100% via \(type(of: display))")
            flash(.brightness, at: corner.edge, level: 1)
        } else {
            guard let muted = volume.toggleMute() else {
                Log.debug("double-tap: this output device cannot mute")
                return
            }
            Log.debug("double-tap: \(muted ? "muted" : "unmuted")")
            flash(.volume, at: corner.edge, level: muted ? 0 : volume.read())
        }
    }

    private func flash(_ kind: LevelKind, at edge: Edge, level: Float?) {
        DispatchQueue.main.async { [hud] in
            hud.show(kind: kind, edge: edge, level: level)
            hud.hideSoon()
        }
    }

    private func submit(_ value: Float, to control: LevelControl) {
        pendingLock.lock()
        pending[ObjectIdentifier(control)] = (control, value)
        let shouldStart = !draining
        draining = true
        pendingLock.unlock()
        if shouldStart {
            io.async { [self] in drain() }
        }
    }

    private func drain() {
        var last: (control: LevelControl, value: Float)?
        while true {
            pendingLock.lock()
            if let (_, next) = pending.popFirst() {
                pendingLock.unlock()
                next.control.write(next.value)
                last = next
                if next.control.writeInterval > 0 {
                    Thread.sleep(forTimeInterval: next.control.writeInterval)
                }
                continue
            }
            if let repeated = last, repeated.control.repeatsLastWrite {
                pendingLock.unlock()
                last = nil
                Thread.sleep(forTimeInterval: 0.1)
                if pendingLock.withLock({ pending.isEmpty }) {
                    repeated.control.write(repeated.value)
                }
                continue
            }
            draining = false
            pendingLock.unlock()
            return
        }
    }

    private func show(_ kind: LevelKind, at edge: Edge, level: Float?) {
        DispatchQueue.main.async { [hud] in
            hud.show(kind: kind, edge: edge, level: level)
        }
    }

    private func describe(_ level: Float?) -> String {
        level.map { String(format: "%.2f", $0) } ?? "none"
    }
}
