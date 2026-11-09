import CoreGraphics
import Foundation

/// Держит курсор на месте, пока идёт жест.
///
/// MultitouchSupport только читает касания и не забирает их у системы, поэтому
/// курсор поехал бы вместе с пальцем. Отвязка мыши от курсора официально работает
/// только у активного приложения, поэтому на каждом кадре касания курсор ещё и
/// возвращается назад. Такой способ не требует разрешения Accessibility.
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
            // Заодно сбрасывает паузу в 0,25 с, которую система ставит после перемещения
            // курсора. Без этого курсор бы подвисал после каждого жеста.
            CGAssociateMouseAndMouseCursorPosition(1)
            Log.debug("курсор отпущен: кадров \(frames), макс. смещение \(String(format: "%.1f", maxDrift)) pt")
        }
    }
}
