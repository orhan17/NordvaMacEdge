import ApplicationServices
import CoreGraphics

/// Гасит клики, которые система делает из тапов по углам, когда включено
/// «касание для клика». Без этого двойной тап по углу был бы ещё и двойным кликом
/// по тому, что под курсором: например, открыл бы файл в Finder.
///
/// Фильтровать чужие события можно только с разрешением Accessibility. Без него
/// приложение работает, просто клик от тапа проходит.
final class ClickBlocker {
    private let shouldBlock: () -> Bool
    private var tap: CFMachPort?
    /// Погасили нажатие, значит надо погасить и отпускание, иначе приложение
    /// получит отпускание кнопки, которую никто не нажимал.
    private var swallowNextUp = false

    init(shouldBlock: @escaping () -> Bool) {
        self.shouldBlock = shouldBlock
    }

    static var hasPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Показывает системный запрос и открывает нужный раздел Настроек.
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
            Log.debug("не получилось перехватить клики")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        Log.debug("клики от тапов по углам гасятся")
        return true
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Система отключает перехват, если колбэк тормозил. Включаем обратно.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .leftMouseDown:
            let block = shouldBlock()
            Log.debug("клик: \(block ? "погашен" : "пропущен"), clickState \(event.getIntegerValueField(.mouseEventClickState))")
            if block {
                swallowNextUp = true
                return nil
            }
        case .leftMouseUp:
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
