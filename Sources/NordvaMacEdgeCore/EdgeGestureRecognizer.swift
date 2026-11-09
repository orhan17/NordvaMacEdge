public enum Edge: String, Sendable {
    case left
    case right
    case bottom
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

/// Normalized trackpad position: x from 0 (left) to 1 (right), y from 0 (bottom) to 1 (top).
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
    /// Along the edge: y for the side edges (up is positive), x for the bottom edge (right is positive).
    case moved(Edge, delta: Double)
    case ended(Edge)
    case tapped(Corner)
    case doubleTapped(Corner)

    public var edge: Edge? {
        switch self {
        case let .began(edge), let .moved(edge, _), let .ended(edge): return edge
        case .tapped, .doubleTapped: return nil
        }
    }
}

/// Gestures are decided by where the finger landed, not where it is now: a finger that
/// started in the middle and reached the edge is just the pointer.
public struct EdgeGestureRecognizer: Sendable {
    public struct Config: Sendable {
        public var edgeWidth: Double = 0.08
        public var activationDistance: Double = 0.025
        public var verticalDominance: Double = 1.5
        public var cornerWidth: Double = 0.12
        public var cornerHeight: Double = 0.2
        public var maxTapDuration: Double = 0.3
        public var doubleTapInterval: Double = 0.4
        public var activeCorners: Set<Corner> = [.topLeft, .bottomRight]
        public var bottomEdgeEnabled = false
        public var bottomHeight: Double = 0.07
        /// Trackpad widths per second, 0.3 is about 4.5 cm/s.
        public var maxBottomSpeed: Double = 0.3
        public var stillRadius: Double = 0.006

        public init() {}
    }

    private struct Candidate: Equatable, Sendable {
        let edge: Edge?
        let corner: Corner?
        let bottom: Bool
        let id: Int32
        let startX: Double
        let startY: Double
        let startTime: Double
        var anchorX: Double
        var anchorTime: Double
    }

    private struct Tap: Equatable, Sendable {
        let corner: Corner
        let endTime: Double
    }

    private enum State: Equatable, Sendable {
        case idle
        case ignoring
        case candidate(Candidate)
        case active(edge: Edge, id: Int32, last: Double)
    }

    public var config: Config
    private var state: State = .idle
    private var lastTap: Tap?

    public init(config: Config = Config()) {
        self.config = config
    }

    /// A touch on the bottom edge alone does not hold the pointer, so normal pointing
    /// that starts there never stutters while the gesture is being decided.
    public var holdsPointer: Bool {
        switch state {
        case let .candidate(candidate): return candidate.edge != nil || candidate.corner != nil
        case .active: return true
        case .idle, .ignoring: return false
        }
    }

    public mutating func reset() {
        state = .idle
        lastTap = nil
    }

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
                let bottom = config.bottomEdgeEnabled && touch.y <= config.bottomHeight
                if edge != nil || corner != nil || bottom {
                    state = .candidate(Candidate(
                        edge: edge, corner: corner, bottom: bottom, id: touch.id,
                        startX: touch.x, startY: touch.y, startTime: time,
                        anchorX: touch.x, anchorTime: time
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

        case var .candidate(candidate):
            if touches.isEmpty {
                state = .idle
                return finishTap(candidate, at: time)
            }
            guard touches.count == 1, let touch = touches.first, touch.id == candidate.id, !isButtonDown() else {
                lastTap = nil
                state = .ignoring
                return []
            }
            let dx = abs(touch.x - candidate.startX)
            let dy = abs(touch.y - candidate.startY)
            if max(dx, dy) < config.stillRadius {
                candidate.anchorX = touch.x
                candidate.anchorTime = time
                state = .candidate(candidate)
            }
            guard max(dx, dy) >= config.activationDistance else { return [] }
            lastTap = nil
            if let edge = candidate.edge, dy >= dx * config.verticalDominance {
                state = .active(edge: edge, id: candidate.id, last: touch.y)
                return [.began(edge)]
            }
            if candidate.bottom, dx >= dy, speedSinceAnchor(candidate, x: touch.x, at: time) <= config.maxBottomSpeed {
                state = .active(edge: .bottom, id: candidate.id, last: touch.x)
                return [.began(.bottom)]
            }
            state = .ignoring
            return []

        case let .active(edge, id, last):
            guard touches.count == 1, let touch = touches.first, touch.id == id else {
                state = touches.isEmpty ? .idle : .ignoring
                return [.ended(edge)]
            }
            let position = edge == .bottom ? touch.x : touch.y
            state = .active(edge: edge, id: id, last: position)
            let delta = position - last
            return delta == 0 ? [] : [.moved(edge, delta: delta)]
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
            lastTap = nil
            return [.tapped(corner), .doubleTapped(corner)]
        }
        lastTap = Tap(corner: corner, endTime: time)
        return [.tapped(corner)]
    }

    /// Measured from when the finger left its resting spot, not from touch-down: otherwise
    /// "rest, then move fast" would count as slow and open the app switcher.
    private func speedSinceAnchor(_ candidate: Candidate, x: Double, at time: Double) -> Double {
        let elapsed = max(time - candidate.anchorTime, 0.001)
        return abs(x - candidate.anchorX) / elapsed
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
