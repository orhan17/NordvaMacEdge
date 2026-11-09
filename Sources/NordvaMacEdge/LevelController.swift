import Foundation
import NordvaMacEdgeCore

/// Превращает жесты в изменения громкости и яркости.
///
/// Уровень считается сразу, на потоке трекпада, а в систему пишется на отдельной
/// очереди и только последнее значение. Запись громкости занимает ~16 мс, а кадры
/// приходят каждые ~11 мс: если писать каждое значение по очереди, запись всё сильнее
/// отстаёт от пальца, и громкость продолжает ехать, когда палец уже поднят.
///
/// `handle` вызывается под замком GestureEngine, поэтому состояние жеста без своего замка.
final class LevelController {
    /// Сколько диапазона проходит слайд на всю высоту трекпада. При 1.6 полный диапазон
    /// укладывается примерно в 60% высоты, поэтому не приходится перехватывать палец.
    private let sensitivity: Float = 1.6
    /// Не дёргаем систему ради изменений, которых никто не заметит.
    private let minimumStep: Float = 1.0 / 200

    private let volume = VolumeControl()
    private let brightness = BrightnessControl()
    private let hud: HUD
    private let kindForEdge: (Edge) -> LevelKind

    private var kind = LevelKind.volume
    private var level: Float?
    private var lastSubmitted: Float = 0

    private let io = DispatchQueue(label: "nordvamacedge.io")
    private let pendingLock = NSLock()
    private var pending: [LevelKind: Float] = [:]
    private var draining = false

    init(hud: HUD, kindForEdge: @escaping (Edge) -> LevelKind) {
        self.hud = hud
        self.kindForEdge = kindForEdge
    }

    func handle(_ event: GestureEvent) {
        switch event {
        case let .began(edge):
            kind = kindForEdge(edge)
            level = control(for: kind).read()
            lastSubmitted = level ?? 0
            Log.debug("начало жеста: край \(edge.rawValue), \(kind), уровень \(describe(level))")
            show(kind, at: edge, level: level)

        case let .moved(edge, delta):
            guard let current = level else { return }
            let next = min(1, max(0, current + Float(delta) * sensitivity))
            level = next
            // Границы отправляем всегда, иначе можно не дойти до ровных 0 или 100%.
            if abs(next - lastSubmitted) >= minimumStep || ((next == 0 || next == 1) && next != lastSubmitted) {
                submit(next, for: kind)
                lastSubmitted = next
            }
            show(kind, at: edge, level: next)

        case .ended:
            Log.debug("конец жеста, уровень \(describe(level))")
            level = nil
            DispatchQueue.main.async { [hud] in hud.hideSoon() }

        case .tapped:
            break

        case let .doubleTapped(corner):
            io.async { [self] in runAction(for: corner) }
        }
    }

    // MARK: - Углы

    /// Слушаются только два угла: верхний на стороне яркости и нижний на стороне громкости.
    private func runAction(for corner: Corner) {
        if corner.isTop {
            brightness.write(1)
            Log.debug("двойной тап: яркость на максимум")
            flash(.brightness, at: corner.edge, level: brightness.read() ?? 1)
        } else {
            guard let muted = volume.toggleMute() else {
                Log.debug("двойной тап: это устройство вывода не умеет выключать звук")
                return
            }
            Log.debug("двойной тап: звук \(muted ? "выключен" : "включён")")
            flash(.volume, at: corner.edge, level: muted ? 0 : volume.read())
        }
    }

    /// Показать индикатор и сразу запланировать скрытие.
    private func flash(_ kind: LevelKind, at edge: Edge, level: Float?) {
        DispatchQueue.main.async { [hud] in
            hud.show(kind: kind, edge: edge, level: level)
            hud.hideSoon()
        }
    }

    // MARK: - Запись

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

    /// Пишет, пока есть что писать. Пока идёт одна запись, новые значения
    /// перезаписывают ожидающее, а не встают в очередь.
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
        level.map { String(format: "%.2f", $0) } ?? "нет"
    }
}
