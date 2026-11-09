import AppKit
import NordvaMacEdgeCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Keys {
        static let enabled = "enabled"
        static let swapEdges = "swapEdges"
    }

    private let demoHUD: Bool
    private let defaults = UserDefaults.standard
    private let hud = HUD()
    private var statusItem: NSStatusItem?
    private var engine: GestureEngine?
    private var touches: TouchSource?
    private var clickBlocker: ClickBlocker?
    private var watchdog: Timer?
    private var permissionPoll: Timer?

    private let enabledItem = NSMenuItem(title: "Включено", action: #selector(toggleEnabled), keyEquivalent: "")
    private let swapItem = NSMenuItem(title: "Поменять края местами", action: #selector(toggleSwap), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLogin), keyEquivalent: "")
    private let permissionItem = NSMenuItem(
        title: "Разрешить доступ, чтобы тап в углу не кликал…",
        action: #selector(askPermission),
        keyEquivalent: ""
    )
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let brightnessHint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let volumeHint = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    private var swapped: Bool {
        defaults.bool(forKey: Keys.swapEdges)
    }

    /// Углы едут вместе с краями: яркость сверху на своей стороне, звук снизу на своей.
    private var activeCorners: Set<Corner> {
        swapped ? [.topRight, .bottomLeft] : [.topLeft, .bottomRight]
    }

    init(demoHUD: Bool) {
        self.demoHUD = demoHUD
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if demoHUD {
            runHUDDemo()
            return
        }

        defaults.register(defaults: [Keys.enabled: true, Keys.swapEdges: false])
        setUpMenu()

        let levels = LevelController(hud: hud) { [defaults] edge in
            // По умолчанию как в Slidr: справа громкость, слева яркость.
            let swapped = defaults.bool(forKey: Keys.swapEdges)
            return (edge == .right) != swapped ? .volume : .brightness
        }
        let engine = GestureEngine(onEvent: levels.handle)
        engine.isEnabled = defaults.bool(forKey: Keys.enabled)
        engine.setActiveCorners(activeCorners)
        self.engine = engine

        touches = TouchSource(onFrame: engine.process)
        startTouches()

        clickBlocker = ClickBlocker { [weak engine] in engine?.shouldSuppressClick() ?? false }
        clickBlocker?.start()
        updatePermissionItem()

        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak engine] _ in
            engine?.releaseIfStalled()
        }

        // После сна устройство перестаёт присылать кадры, его надо пересоздавать.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.reset()
        touches?.stop()
    }

    // MARK: - Трекпад

    private func startTouches() {
        let started = touches?.start() ?? false
        statusLine.isHidden = started
        statusLine.title = "Трекпад недоступен"
        Log.debug(started ? "готов к жестам" : "трекпад недоступен")
    }

    @objc private func willSleep() {
        engine?.reset()
        touches?.stop()
    }

    @objc private func didWake() {
        // Сразу после пробуждения устройство может быть ещё не готово.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.engine?.reset()
            self?.startTouches()
        }
    }

    // MARK: - Доступ для гашения кликов

    @objc private func askPermission() {
        ClickBlocker.requestPermission()
        // Система не сообщает, когда доступ выдали, поэтому проверяем сами.
        permissionPoll?.invalidate()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self, ClickBlocker.hasPermission else { return }
            timer.invalidate()
            self.clickBlocker?.start()
            self.updatePermissionItem()
        }
    }

    private func updatePermissionItem() {
        permissionItem.isHidden = clickBlocker?.isRunning ?? false
    }

    // MARK: - Меню

    private func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "NordvaMacEdge")
        statusItem = item

        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        statusLine.isHidden = true
        menu.addItem(statusLine)
        for entry in [enabledItem, swapItem, loginItem] {
            entry.target = self
            menu.addItem(entry)
        }
        permissionItem.target = self
        permissionItem.isHidden = true
        menu.addItem(permissionItem)

        menu.addItem(.separator())
        for hint in [brightnessHint, volumeHint] {
            hint.isEnabled = false
            menu.addItem(hint)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        enabledItem.state = defaults.bool(forKey: Keys.enabled) ? .on : .off
        swapItem.state = swapped ? .on : .off
        brightnessHint.title = "Двойной тап \(swapped ? "справа" : "слева") вверху: яркость на максимум"
        volumeHint.title = "Двойной тап \(swapped ? "слева" : "справа") внизу: звук вкл/выкл"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if ClickBlocker.hasPermission { clickBlocker?.start() }
        updatePermissionItem()
    }

    @objc private func toggleEnabled() {
        let enabled = !defaults.bool(forKey: Keys.enabled)
        defaults.set(enabled, forKey: Keys.enabled)
        engine?.isEnabled = enabled
    }

    @objc private func toggleSwap() {
        defaults.set(!swapped, forKey: Keys.swapEdges)
        engine?.setActiveCorners(activeCorners)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Не получилось изменить автозапуск"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: - Показ индикатора без трекпада

    private func runHUDDemo() {
        hud.show(kind: .volume, edge: .right, level: 0.65)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [hud] in
            hud.show(kind: .brightness, edge: .left, level: 0.3)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            NSApp.terminate(nil)
        }
    }
}
