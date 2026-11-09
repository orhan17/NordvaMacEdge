public enum Edge: String, Sendable {
    case left
    case right
}

public enum Corner: String, Sendable, CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var edge: Edge {
        self == .topLeft || self == .bottomLeft ? .left : .right
    }

    public var isTop: Bool {
        self == .topLeft || self == .topRight
    }
}

/// Палец на трекпаде. x: 0 слева, 1 справа. y: 0 снизу, 1 сверху.
public struct TouchPoint: Equatable, Sendable {
    public let id: Int32
    public let x: Double
    public let y: Double

    public init(id: Int32, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public enum GestureEvent: Equatable, Sendable {
    case began(Edge)
    /// deltaY > 0 значит палец идёт вверх.
    case moved(Edge, deltaY: Double)
    case ended(Edge)
    /// Короткое касание угла. Приходит на каждый тап, нужен, чтобы погасить клик,
    /// который система сделает из этого касания при включённом «касании для клика».
    case tapped(Corner)
    case doubleTapped(Corner)
}

/// Отличает слайд вдоль края и тапы по углам от обычного движения курсора.
///
/// Главная идея: решение принимается по тому, где палец КОСНУЛСЯ трекпада.
/// Палец, который начал в центре и доехал до края, это просто курсор.
public struct EdgeGestureRecognizer: Sendable {
    public struct Config: Sendable {
        /// Ширина зоны у края в долях ширины трекпада.
        public var edgeWidth: Double = 0.08
        /// Сколько надо проехать, прежде чем принять решение. Меньше, и дрожание
        /// пальца будет случайно запускать жест.
        public var activationDistance: Double = 0.025
        /// Во сколько раз движение по y должно быть больше, чем по x. Координаты
        /// нормированные, а трекпад шире, чем выше, поэтому 1.5 это примерно 45° в реальности.
        public var verticalDominance: Double = 1.5
        /// Размер угловой зоны. По высоте доля больше, потому что трекпад ниже,
        /// чем шире: так зона получается примерно квадратной, около 2 см.
        public var cornerWidth: Double = 0.12
        public var cornerHeight: Double = 0.2
        /// Касание дольше этого уже не тап, а палец, который просто лежит.
        public var maxTapDuration: Double = 0.3
        /// Сколько секунд может пройти от отрыва первого тапа до касания вторым.
        public var doubleTapInterval: Double = 0.4
        /// Углы, которые слушаем. Остальные остаются обычной частью трекпада: клик
        /// в них работает как всегда.
        public var activeCorners: Set<Corner> = [.topLeft, .bottomRight]

        public init() {}
    }

    private struct Candidate: Equatable, Sendable {
        let edge: Edge?
        let corner: Corner?
        let id: Int32
        let startX: Double
        let startY: Double
        let startTime: Double
    }

    private struct Tap: Equatable, Sendable {
        let corner: Corner
        let endTime: Double
    }

    private enum State: Equatable, Sendable {
        case idle
        /// Эти пальцы не наши, ждём, пока все поднимутся.
        case ignoring
        /// Палец коснулся края или угла, но ещё не понятно, что это будет.
        case candidate(Candidate)
        case active(edge: Edge, id: Int32, lastY: Double)
    }

    /// Можно менять на ходу, например когда края поменяли местами.
    public var config: Config
    private var state: State = .idle
    /// Первый тап возможного двойного.
    private var lastTap: Tap?

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Пока true, курсор надо держать на месте: иначе он уедет ещё до того,
    /// как станет понятно, жест это или нет.
    public var holdsPointer: Bool {
        switch state {
        case .candidate, .active: return true
        case .idle, .ignoring: return false
        }
    }

    public mutating func reset() {
        state = .idle
        lastTap = nil
    }

    /// `time` в секундах, нужен для тапов. `isButtonDown` ленивый: состояние кнопки
    /// нужно только в момент решения.
    public mutating func process(
        _ touches: [TouchPoint],
        at time: Double,
        isButtonDown: @autoclosure () -> Bool
    ) -> [GestureEvent] {
        switch state {
        case .idle:
            guard let touch = touches.first else { return [] }
            if touches.count == 1 {
                let edge = edge(atX: touch.x)
                let corner = corner(at: touch)
                if edge != nil || corner != nil {
                    state = .candidate(Candidate(
                        edge: edge, corner: corner, id: touch.id,
                        startX: touch.x, startY: touch.y, startTime: time
                    ))
                    return []
                }
            }
            lastTap = nil
            state = .ignoring
            return []

        case .ignoring:
            if touches.isEmpty { state = .idle }
            return []

        case let .candidate(candidate):
            if touches.isEmpty {
                state = .idle
                return finishTap(candidate, at: time)
            }
            // Второй палец значит скролл или ладонь, зажатая кнопка значит клик или перетаскивание.
            guard touches.count == 1, let touch = touches.first, touch.id == candidate.id, !isButtonDown() else {
                lastTap = nil
                state = .ignoring
                return []
            }
            let dx = abs(touch.x - candidate.startX)
            let dy = abs(touch.y - candidate.startY)
            guard max(dx, dy) >= config.activationDistance else { return [] }
            // Палец сдвинулся, значит это уже не тап. Слайд, только если начали у самого
            // края и ведём вертикально, иначе отдаём курсору.
            lastTap = nil
            guard let edge = candidate.edge, dy >= dx * config.verticalDominance else {
                state = .ignoring
                return []
            }
            state = .active(edge: edge, id: candidate.id, lastY: touch.y)
            return [.began(edge)]

        case let .active(edge, id, lastY):
            guard touches.count == 1, let touch = touches.first, touch.id == id else {
                state = touches.isEmpty ? .idle : .ignoring
                return [.ended(edge)]
            }
            state = .active(edge: edge, id: id, lastY: touch.y)
            let delta = touch.y - lastY
            return delta == 0 ? [] : [.moved(edge, deltaY: delta)]
        }
    }

    private mutating func finishTap(_ candidate: Candidate, at time: Double) -> [GestureEvent] {
        guard let corner = candidate.corner, time - candidate.startTime <= config.maxTapDuration else {
            lastTap = nil
            return []
        }
        if let previous = lastTap,
           previous.corner == corner,
           candidate.startTime - previous.endTime <= config.doubleTapInterval {
            // Третий тап начнёт новую пару, а не сработает ещё раз.
            lastTap = nil
            return [.tapped(corner), .doubleTapped(corner)]
        }
        lastTap = Tap(corner: corner, endTime: time)
        return [.tapped(corner)]
    }

    private func edge(atX x: Double) -> Edge? {
        if x <= config.edgeWidth { return .left }
        if x >= 1 - config.edgeWidth { return .right }
        return nil
    }

    private func corner(at touch: TouchPoint) -> Corner? {
        let left = touch.x <= config.cornerWidth
        let right = touch.x >= 1 - config.cornerWidth
        let top = touch.y >= 1 - config.cornerHeight
        let bottom = touch.y <= config.cornerHeight
        let corner: Corner?
        switch (left, right, top, bottom) {
        case (true, _, true, _): corner = .topLeft
        case (true, _, _, true): corner = .bottomLeft
        case (_, true, true, _): corner = .topRight
        case (_, true, _, true): corner = .bottomRight
        default: corner = nil
        }
        return corner.flatMap { config.activeCorners.contains($0) ? $0 : nil }
    }
}
