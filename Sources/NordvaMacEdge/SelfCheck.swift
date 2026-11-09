import Foundation

/// `--check`: nudges volume and brightness by 1% and back. Skips the volume write when muted, since it would unmute.
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

        if !roundTrip(name: "brightness", control: BrightnessControl()) {
            failed = true
        }

        return failed ? 1 : 0
    }

    private static func roundTrip(name: String, control: LevelControl) -> Bool {
        guard let original = control.read() else {
            print("\(name): CANNOT READ")
            return false
        }
        let test = original >= 0.5 ? original - 0.01 : original + 0.01
        let wrote = control.write(test)
        Thread.sleep(forTimeInterval: 0.2)
        let seen = control.read()
        control.write(original)
        Thread.sleep(forTimeInterval: 0.2)
        let restored = control.read()

        let applied = wrote && seen.map { abs($0 - test) < 0.005 } == true
        let back = restored.map { abs($0 - original) < 0.005 } == true
        let describe = { (value: Float?) in value.map { String(format: "%.3f", $0) } ?? "none" }
        print("\(name): was \(describe(original)), wrote \(describe(test)), read \(describe(seen)), restored \(describe(restored)) - \(applied && back ? "ok" : "FAILED")")
        return applied && back
    }
}
