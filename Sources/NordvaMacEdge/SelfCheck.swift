import Foundation

/// Проверка системных вызовов без пальцев на трекпаде. Двигает громкость и яркость
/// на 1% и сразу возвращает обратно. Если звук выключен, запись пропускает: она бы его включила.
enum SelfCheck {
    static func run() -> Int32 {
        var failed = false

        let source = TouchSource(onFrame: { _, _ in })
        if let source, source.start() {
            source.stop()
            print("трекпад: ок")
        } else {
            print("трекпад: НЕ РАБОТАЕТ")
            failed = true
        }

        let volume = VolumeControl()
        if volume.isMuted {
            print("громкость: звук выключен, запись не проверяю")
        } else if !roundTrip(name: "громкость", control: volume) {
            failed = true
        }

        if !roundTrip(name: "яркость", control: BrightnessControl()) {
            failed = true
        }

        return failed ? 1 : 0
    }

    private static func roundTrip(name: String, control: LevelControl) -> Bool {
        guard let original = control.read() else {
            print("\(name): НЕ ЧИТАЕТСЯ")
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
        let describe = { (value: Float?) in value.map { String(format: "%.3f", $0) } ?? "нет" }
        print("\(name): было \(describe(original)), записал \(describe(test)), прочитал \(describe(seen)), вернул \(describe(restored)) - \(applied && back ? "ок" : "НЕ РАБОТАЕТ")")
        return applied && back
    }
}
