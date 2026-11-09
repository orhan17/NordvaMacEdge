import Foundation
import NordvaMacEdgeCore

/// A CoreAudio volume write takes ~16 ms while frames arrive every ~11 ms. Writing every
/// value queues them up and the volume lags behind the finger, so the level is computed
/// right away and only the latest value is written.
final class LevelController {
    private let minimumStep: Float = 1.0 / 200

    private let volume = VolumeControl()
    private let brightness = BrightnessControl()
    private let hud: HUD
    private let settings: Settings

    private var sensitivity: Float = 1.6
    private var kind = LevelKind.volume
    private var level: Float?
    private var lastSubmitted: Float = 0

    private let io = DispatchQueue(label: "nordvamacedge.io")
    private let pendingLock = NSLock()
    private var pending: [LevelKind: Float] = [:]
    private var draining = false

    init(hud: HUD, settings: Settings) {
        self.hud = hud
        self.settings = settings
    }

    func handle(_ event: GestureEvent) {
        switch event {
        case let .began(edge):
            kind = settings.kind(for: edge)
            sensitivity = Float(settings.sensitivity)
            level = control(for: kind).read()
            lastSubmitted = level ?? 0
            Log.debug("slide began: edge \(edge.rawValue), \(kind), level \(describe(level))")
            show(kind, at: edge, level: level)

        case let .moved(edge, delta):
            guard let current = level else { return }
            let next = min(1, max(0, current + Float(delta) * sensitivity))
            level = next
            if abs(next - lastSubmitted) >= minimumStep || ((next == 0 || next == 1) && next != lastSubmitted) {
                submit(next, for: kind)
                lastSubmitted = next
            }
            show(kind, at: edge, level: next)

        case .ended:
            Log.debug("slide ended, level \(describe(level))")
            level = nil
            DispatchQueue.main.async { [hud] in hud.hideSoon() }

        case .tapped:
            break

        case let .doubleTapped(corner):
            io.async { [self] in runAction(for: corner) }
        }
    }

    private func runAction(for corner: Corner) {
        if corner.isTop {
            brightness.write(1)
            Log.debug("double-tap: brightness to 100%")
            flash(.brightness, at: corner.edge, level: brightness.read() ?? 1)
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

    private func submit(_ value: Float, for kind: LevelKind) {
        pendingLock.lock()
        pending[kind] = value
        let shouldStart = !draining
        draining = true
        pendingLock.unlock()
        if shouldStart {
            io.async { [self] in drain() }
        }
    }

    private func drain() {
        while true {
            pendingLock.lock()
            guard let (kind, value) = pending.popFirst() else {
                draining = false
                pendingLock.unlock()
                return
            }
            pendingLock.unlock()
            control(for: kind).write(value)
        }
    }

    private func control(for kind: LevelKind) -> LevelControl {
        kind == .volume ? volume : brightness
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
