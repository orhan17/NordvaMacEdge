import AppKit
import NordvaMacEdgeCore
import SwiftUI

final class SettingsWindowController {
    private let settings: Settings
    private let surfaceSize: () -> (width: Double, height: Double)?
    private let requestAccess: () -> Void
    private let previewHUD: () -> Void
    private var window: NSWindow?

    init(
        settings: Settings,
        surfaceSize: @escaping () -> (width: Double, height: Double)?,
        requestAccess: @escaping () -> Void,
        previewHUD: @escaping () -> Void
    ) {
        self.settings = settings
        self.surfaceSize = surfaceSize
        self.requestAccess = requestAccess
        self.previewHUD = previewHUD
    }

    func show() {
        if window == nil {
            let view = SettingsView(settings: settings, surface: surfaceSize(), requestAccess: requestAccess, previewHUD: previewHUD)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "NordvaMacEdge Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            self.window = window
        }
        guard let window else { return }
        // center() uses the screen with the key window; the menu was opened on the screen with the pointer.
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
           !window.isVisible || window.screen != screen {
            let area = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(
                x: area.midX - size.width / 2,
                y: area.minY + (area.height - size.height) * 2 / 3
            ))
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// `--settings-snapshot <path>`: renders the window content to a PNG without showing it.
    func snapshot(to url: URL) {
        let view = NSHostingView(rootView: SettingsView(settings: settings, surface: surfaceSize(), requestAccess: {}, previewHUD: {}))
        view.frame.size = view.fittingSize
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: Settings
    let surface: (width: Double, height: Double)?
    let requestAccess: () -> Void
    let previewHUD: () -> Void

    @State private var accessGranted = ClickBlocker.hasPermission
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Gestures") {
                toggle("Volume", detail: "Slide along the \(settings.volumeSide.rawValue) edge", isOn: $settings.volumeEdge)
                toggle("Brightness", detail: "Slide along the \(settings.brightnessSide.rawValue) edge, for the display under the pointer", isOn: $settings.brightnessEdge)
                toggle(
                    "Corner double-taps",
                    detail: "Top \(settings.brightnessSide.rawValue): brightness to 100%. "
                        + "Bottom \(settings.volumeSide.rawValue): mute or unmute.",
                    isOn: $settings.cornerTaps
                )
                toggle("App switcher", detail: "Slide slowly along the bottom edge, lift to switch", isOn: $settings.appSwitcher)
                Toggle("Swap left and right", isOn: $settings.swapEdges)
            }

            Section("Feel") {
                toggle(
                    "Haptic feedback",
                    detail: "A light trackpad click every 10%, at 0 and 100%, and for each app in the switcher",
                    isOn: $settings.haptics
                )
                slider(
                    "Volume and brightness speed",
                    value: $settings.sensitivity,
                    range: Settings.sensitivityRange,
                    ends: ("Slow", "Fast"),
                    detail: surface.map { String(format: "0 to 100%% in %.1f cm", $0.height / settings.sensitivity) }
                )
                slider(
                    "App switcher step",
                    value: $settings.switcherStep,
                    range: Settings.switcherStepRange,
                    ends: ("Short", "Long"),
                    detail: surface.map { String(format: "%.1f cm per app", $0.width * settings.switcherStep) }
                )
                slider(
                    "App switcher speed limit",
                    value: $settings.switcherMaxSpeed,
                    range: Settings.switcherMaxSpeedRange,
                    ends: ("Strict", "Relaxed"),
                    detail: surface.map { String(format: "opens below %.1f cm/s", $0.width * settings.switcherMaxSpeed) }
                )
            }

            Section("Bar") {
                Picker("Style", selection: preview($settings.hudStyle)) {
                    ForEach(HUDStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if settings.hudStyle != .percent {
                    toggle(
                        "Show percentage",
                        detail: settings.hudStyle == .ring ? "Inside the ring, instead of the icon" : "Above the bar",
                        isOn: preview($settings.hudPercent)
                    )
                }
                Picker("Color", selection: preview($settings.hudColor)) {
                    ForEach(HUDColor.allCases) { Text($0.title).tag($0) }
                }
                Picker("Size", selection: preview($settings.hudSize)) {
                    ForEach(HUDSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Position", selection: preview($settings.hudPosition)) {
                    ForEach(HUDPosition.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Stays on screen", selection: preview($settings.hudDuration)) {
                    ForEach(HUDDuration.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Spacer()
                    Button("Preview", action: previewHUD)
                }
            }

            Section("General") {
                LabeledContent("Accessibility access") {
                    if accessGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access…", action: requestAccess)
                    }
                }
                if !accessGranted {
                    Text("Needed for the app switcher and to stop corner taps from also clicking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if let error = settings.loginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Restore Defaults") { settings.restoreDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 520)
        .onReceive(poll) { _ in accessGranted = ClickBlocker.hasPermission }
    }

    /// Shows the bar after each change, so the effect is visible right away.
    private func preview<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = $0; previewHUD() }
        )
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        ends: (String, String),
        detail: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            HStack {
                Text(ends.0).font(.caption).foregroundStyle(.secondary)
                Slider(value: value, in: range)
                Text(ends.1).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
