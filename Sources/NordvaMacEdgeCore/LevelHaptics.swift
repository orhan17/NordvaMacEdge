public enum Haptic: Equatable, Sendable {
    case detent
    case stop
}

/// The trackpad click for a level moving from `old` to `new`: a stop when it reaches 0 or 100%,
/// a detent each time it crosses a multiple of `step`.
public func haptic(from old: Double, to new: Double, step: Double = 0.1) -> Haptic? {
    guard new != old else { return nil }
    if new <= 0 || new >= 1 { return .stop }
    // The epsilon keeps 0.6 / 0.1 = 5.999… from landing in the wrong detent.
    let before = Int((old / step + 1e-9).rounded(.down))
    let after = Int((new / step + 1e-9).rounded(.down))
    return before != after ? .detent : nil
}
