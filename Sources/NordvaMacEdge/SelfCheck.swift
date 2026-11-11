import Foundation

/// `--check`: nudges volume and the brightness of every display by 2% and back. Skips the volume write when muted, since it would unmute.
enum SelfCheck {
    static func run() -> Int32 {
        var failed = false

        let source = TouchSource(onFrame: { _, _ in })
        if let source, source.start() {
            source.stop()
            print("trackpad: ok")
        } else {
            print("trackpad: FAILED")
            failed = true
        }

        let volume = VolumeControl()
        if volume.isMuted {
            print("volume: muted, skipping the write check")
        } else if !roundTrip(name: "volume", control: volume) {
            failed = true
        }

        for display in Brightness.onlineDisplays() {
            let name = "brightness of display \(display)"
            if DisplayBrightness.supports(display) {
                if !roundTrip(name: name, control: DisplayBrightness(display: display)) { failed = true }
            } else if let monitor = MonitorBrightness(display: display) {
                monitor.cacheLifetime = 0
                if !roundTrip(name: name + " over DDC", control: monitor) { failed = true }
            } else {
                print("\(name): not adjustable")
            }
        }

        return failed ? 1 : 0
    }

    @discardableResult
    private static func set(_ control: LevelControl, _ level: Float) -> Bool {
        let wrote = control.write(level)
        if control.repeatsLastWrite {
            Thread.sleep(forTimeInterval: 0.1)
            control.write(level)
        }
        Thread.sleep(forTimeInterval: 0.2)
        return wrote
    }

    private static func roundTrip(name: String, control: LevelControl) -> Bool {
        guard let original = control.read() else {
            print("\(name): CANNOT READ")
            return false
        }
        let test = original >= 0.5 ? original - 0.02 : original + 0.02
        let wrote = set(control, test)
        let seen = control.read()
        set(control, original)
        let restored = control.read()

        let applied = wrote && seen.map { abs($0 - test) < 0.005 } == true
        let back = restored.map { abs($0 - original) < 0.005 } == true
        let describe = { (value: Float?) in value.map { String(format: "%.3f", $0) } ?? "none" }
        print("\(name): was \(describe(original)), wrote \(describe(test)), read \(describe(seen)), restored \(describe(restored)) - \(applied && back ? "ok" : "FAILED")")
        return applied && back
    }
}
