import ApplicationServices
import CoreGraphics

/// With "Tap to click" on, macOS turns a corner double-tap into a double-click on whatever
/// is under the pointer. This swallows those clicks. Needs Accessibility access.
final class ClickBlocker {
    private let shouldBlock: () -> Bool
    private var tap: CFMachPort?
    private var swallowNextUp = false

    init(shouldBlock: @escaping () -> Bool) {
        self.shouldBlock = shouldBlock
    }

    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    var isRunning: Bool {
        tap != nil
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.hasPermission else { return false }
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: clickCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.debug("could not create the click event tap")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        Log.debug("clicks from corner taps are swallowed")
        return true
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS silently disables a tap whose callback was too slow.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .leftMouseDown:
            let block = shouldBlock()
            Log.debug("click: \(block ? "swallowed" : "passed"), clickState \(event.getIntegerValueField(.mouseEventClickState))")
            if block {
                swallowNextUp = true
                return nil
            }
        case .leftMouseUp:
            // A swallowed press needs its release swallowed too, or apps get an unmatched mouse-up.
            if swallowNextUp {
                swallowNextUp = false
                return nil
            }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}

private let clickCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let blocker = Unmanaged<ClickBlocker>.fromOpaque(refcon).takeUnretainedValue()
    return blocker.handle(type, event)
}
