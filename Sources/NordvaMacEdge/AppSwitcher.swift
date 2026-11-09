import CoreGraphics
import Foundation
import NordvaMacEdgeCore

/// Переключение приложений медленным слайдом по нижнему краю.
///
/// Нажимает настоящий Command+Tab, поэтому выглядит и работает как системный
/// переключатель: палец вправо - следующее приложение, влево - предыдущее,
/// отрыв пальца - переключиться. Нажимать клавиши за пользователя macOS позволяет
/// только с доступом Accessibility, без него события молча теряются.
///
/// `handle` вызывается под замком GestureEngine, поэтому счётчик без своего замка.
final class AppSwitcher {
    private enum Key {
        static let command: CGKeyCode = 0x37
        static let shift: CGKeyCode = 0x38
        static let tab: CGKeyCode = 0x30
    }

    /// Сколько ширины трекпада на одно приложение, около 1 см.
    private let step = 0.07

    private let queue = DispatchQueue(label: "nordvamacedge.switcher")
    private let source = CGEventSource(stateID: .hidSystemState)
    private var travel = 0.0
    private var isOpen = false

    func handle(_ event: GestureEvent) {
        switch event {
        case .began:
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
        // Как у настоящего Command+Tab: сразу выделено следующее приложение.
        tab(forward: true)
        isOpen = true
        Log.debug("переключатель открыт")
    }

    private func move(by steps: Int) {
        guard isOpen else { return }
        for _ in 0..<abs(steps) {
            tab(forward: steps > 0)
        }
    }

    private func close() {
        guard isOpen else { return }
        // Отпущенный Command и есть «переключиться». Если его не отпустить, система
        // будет считать, что Command зажат, пока его не нажмут на клавиатуре.
        post(Key.command, down: false, flags: [])
        isOpen = false
        Log.debug("переключатель закрыт")
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
