import CoreGraphics
import Foundation
import NordvaMacEdgeCore

/// Presses the real Command+Tab: right for the next app, left for the previous one,
/// lift to switch. Posting key events requires Accessibility access.
final class AppSwitcher {
    private enum Key {
        static let command: CGKeyCode = 0x37
        static let shift: CGKeyCode = 0x38
        static let tab: CGKeyCode = 0x30
    }

    private let settings: Settings
    private let queue = DispatchQueue(label: "nordvamacedge.switcher")
    private let source = CGEventSource(stateID: .hidSystemState)
    private var step = 0.07
    private var travel = 0.0
    private var isOpen = false

    init(settings: Settings) {
        self.settings = settings
    }

    func handle(_ event: GestureEvent) {
        switch event {
        case .began:
            step = settings.switcherStep
            travel = 0
            queue.async { [self] in open() }
        case let .moved(_, delta):
            travel += delta
            var steps = 0
            while travel >= step {
                steps += 1
                travel -= step
            }
            while travel <= -step {
                steps -= 1
                travel += step
            }
            if steps != 0 {
                queue.async { [self] in move(by: steps) }
            }
        case .ended:
            queue.async { [self] in close() }
        case .tapped, .doubleTapped:
            break
        }
    }

    private func open() {
        post(Key.command, down: true, flags: .maskCommand)
        tab(forward: true)
        isOpen = true
        Log.debug("app switcher opened")
    }

    private func move(by steps: Int) {
        guard isOpen else { return }
        for _ in 0..<abs(steps) {
            tab(forward: steps > 0)
        }
    }

    private func close() {
        guard isOpen else { return }
        // Must always run: a synthetic Command that is never released stays "pressed"
        // for the whole system until the real key is pressed.
        post(Key.command, down: false, flags: [])
        isOpen = false
        Log.debug("app switcher closed")
    }

    private func tab(forward: Bool) {
        if forward {
            post(Key.tab, down: true, flags: .maskCommand)
            post(Key.tab, down: false, flags: .maskCommand)
        } else {
            let flags: CGEventFlags = [.maskCommand, .maskShift]
            post(Key.shift, down: true, flags: flags)
            post(Key.tab, down: true, flags: flags)
            post(Key.tab, down: false, flags: flags)
            post(Key.shift, down: false, flags: .maskCommand)
        }
    }

    private func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}
