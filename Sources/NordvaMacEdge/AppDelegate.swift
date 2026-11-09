import AppKit
import NordvaMacEdgeCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let demoHUD: Bool
    private let settings = Settings()
    private let hud = HUD()
    private var statusItem: NSStatusItem?
    private var engine: GestureEngine?
    private var touches: TouchSource?
    private var clickBlocker: ClickBlocker?
    private var watchdog: Timer?
    private var permissionPoll: Timer?

    private lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        surfaceSize: { [weak self] in self?.touches?.surfaceSize },
        requestAccess: { [weak self] in self?.askPermission() }
    )

    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    private let permissionItem = NSMenuItem(
        title: "Allow Access for App Switcher and Corners…",
        action: #selector(askPermission),
        keyEquivalent: ""
    )
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    private let snapshotPath: String?

    init(demoHUD: Bool, snapshotPath: String?) {
        self.demoHUD = demoHUD
        self.snapshotPath = snapshotPath
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if demoHUD {
            runHUDDemo()
            return
        }

        setUpMenu()

        let haptics = Haptics(settings: settings)
        let levels = LevelController(hud: hud, settings: settings, haptics: haptics)
        let switcher = AppSwitcher(settings: settings, haptics: haptics)
        engine = GestureEngine { event in
            if event.edge == .bottom {
                switcher.handle(event)
            } else {
                levels.handle(event)
            }
        }
        settings.onChange = { [weak self] in self?.applySettings() }
        applySettings()

        touches = TouchSource(onFrame: { [weak engine] touches, time in engine?.process(touches, at: time) })
        startTouches()

        if let snapshotPath {
            settingsWindow.snapshot(to: URL(fileURLWithPath: snapshotPath))
            NSApp.terminate(nil)
            return
        }

        clickBlocker = ClickBlocker { [weak engine] in engine?.shouldSuppressClick() ?? false }
        clickBlocker?.start()
        updatePermissionItem()
        Log.debug("accessibility: \(ClickBlocker.hasPermission ? "granted" : "not granted")")
        if !ClickBlocker.hasPermission, settings.appSwitcher {
            askPermission()
        }

        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak engine] _ in
            engine?.releaseIfStalled()
        }

        // The trackpad stops sending frames after sleep, so the device is recreated on wake.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.reset()
        touches?.stop()
    }

    private func applySettings() {
        guard let engine else { return }
        if engine.isEnabled != settings.enabled {
            engine.isEnabled = settings.enabled
        }
        let settings = settings
        engine.configure { config in
            config.enabledEdges = settings.enabledSideEdges
            config.activeCorners = settings.activeCorners
            config.bottomEdgeEnabled = settings.appSwitcher && ClickBlocker.hasPermission
            config.maxBottomSpeed = settings.switcherMaxSpeed
        }
    }

    private func startTouches() {
        let started = touches?.start() ?? false
        statusLine.isHidden = started
        statusLine.title = "Trackpad unavailable"
        Log.debug(started ? "ready for gestures" : "trackpad unavailable")
    }

    @objc private func willSleep() {
        engine?.reset()
        touches?.stop()
    }

    @objc private func didWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.engine?.reset()
            self?.startTouches()
        }
    }

    @objc private func askPermission() {
        ClickBlocker.requestPermission()
        permissionPoll?.invalidate()
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self, ClickBlocker.hasPermission else { return }
            timer.invalidate()
            self.clickBlocker?.start()
            self.updatePermissionItem()
            self.applySettings()
        }
    }

    private func updatePermissionItem() {
        permissionItem.isHidden = clickBlocker?.isRunning ?? false
    }

    private func setUpMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "NordvaMacEdge")
        statusItem = item

        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        statusLine.isHidden = true
        menu.addItem(statusLine)
        for entry in [enabledItem, settingsItem, permissionItem] {
            entry.target = self
            menu.addItem(entry)
        }
        permissionItem.isHidden = true
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NordvaMacEdge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        enabledItem.state = settings.enabled ? .on : .off
        if ClickBlocker.hasPermission { clickBlocker?.start() }
        updatePermissionItem()
        applySettings()
    }

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

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
