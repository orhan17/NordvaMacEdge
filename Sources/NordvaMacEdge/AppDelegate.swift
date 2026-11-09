import AppKit
import NordvaMacEdgeCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum Keys {
        static let enabled = "enabled"
        static let swapEdges = "swapEdges"
        static let appSwitcher = "appSwitcher"
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

    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let swapItem = NSMenuItem(title: "Swap Edges", action: #selector(toggleSwap), keyEquivalent: "")
    private let switcherItem = NSMenuItem(
        title: "App Switcher on Bottom Edge",
        action: #selector(toggleSwitcher),
        keyEquivalent: ""
    )
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let permissionItem = NSMenuItem(
        title: "Allow Access for App Switcher and Corners…",
        action: #selector(askPermission),
        keyEquivalent: ""
    )
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let brightnessHint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let volumeHint = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let switcherHint = NSMenuItem(
        title: "Slide slowly along the bottom edge: switch apps",
        action: nil,
        keyEquivalent: ""
    )

    private var swapped: Bool {
        defaults.bool(forKey: Keys.swapEdges)
    }

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

        defaults.register(defaults: [Keys.enabled: true, Keys.swapEdges: false, Keys.appSwitcher: true])
        setUpMenu()

        let levels = LevelController(hud: hud) { [defaults] edge in
            let swapped = defaults.bool(forKey: Keys.swapEdges)
            return (edge == .right) != swapped ? .volume : .brightness
        }
        let switcher = AppSwitcher()
        let engine = GestureEngine { event in
            if event.edge == .bottom {
                switcher.handle(event)
            } else {
                levels.handle(event)
            }
        }
        engine.isEnabled = defaults.bool(forKey: Keys.enabled)
        engine.setActiveCorners(activeCorners)
        self.engine = engine
        updateBottomEdge()

        touches = TouchSource(onFrame: engine.process)
        startTouches()

        clickBlocker = ClickBlocker { [weak engine] in engine?.shouldSuppressClick() ?? false }
        clickBlocker?.start()
        updatePermissionItem()

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
            self.updateBottomEdge()
        }
    }

    private func updatePermissionItem() {
        permissionItem.isHidden = clickBlocker?.isRunning ?? false
    }

    private func updateBottomEdge() {
        engine?.setBottomEdgeEnabled(defaults.bool(forKey: Keys.appSwitcher) && ClickBlocker.hasPermission)
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
        for entry in [enabledItem, swapItem, switcherItem, loginItem] {
            entry.target = self
            menu.addItem(entry)
        }
        permissionItem.target = self
        permissionItem.isHidden = true
        menu.addItem(permissionItem)

        menu.addItem(.separator())
        for hint in [brightnessHint, volumeHint, switcherHint] {
            hint.isEnabled = false
            menu.addItem(hint)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        enabledItem.state = defaults.bool(forKey: Keys.enabled) ? .on : .off
        swapItem.state = swapped ? .on : .off
        brightnessHint.title = "Double-tap top \(swapped ? "right" : "left"): brightness to 100%"
        volumeHint.title = "Double-tap bottom \(swapped ? "left" : "right"): mute or unmute"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        switcherItem.state = defaults.bool(forKey: Keys.appSwitcher) ? .on : .off
        if ClickBlocker.hasPermission { clickBlocker?.start() }
        updatePermissionItem()
        updateBottomEdge()
    }

    @objc private func toggleSwitcher() {
        defaults.set(!defaults.bool(forKey: Keys.appSwitcher), forKey: Keys.appSwitcher)
        updateBottomEdge()
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
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
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
