import CoreGraphics
import Foundation

/// MultitouchSupport only reads touches, so the pointer would move along with the finger.
/// It is detached from the mouse and warped back on every frame while a gesture is held.
final class PointerHold {
    private var heldAt: CGPoint?
    private var frames = 0
    private var maxDrift = 0.0

    func update(hold: Bool) {
        if hold {
            guard let current = CGEvent(source: nil)?.location else { return }
            guard let target = heldAt else {
                heldAt = current
                frames = 0
                maxDrift = 0
                CGAssociateMouseAndMouseCursorPosition(0)
                return
            }
            frames += 1
            let drift = hypot(current.x - target.x, current.y - target.y)
            if drift > 0 {
                maxDrift = max(maxDrift, drift)
                CGWarpMouseCursorPosition(target)
            }
        } else if heldAt != nil {
            heldAt = nil
            // Also clears the 0.25 s input freeze macOS applies after a warp.
            CGAssociateMouseAndMouseCursorPosition(1)
            Log.debug("pointer released: \(frames) frames, max drift \(String(format: "%.1f", maxDrift)) pt")
        }
    }
}
