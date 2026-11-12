import Foundation
import NordvaMacEdgeCore
import ServiceManagement

/// Backed by UserDefaults, which is thread-safe, so gesture code reads these values
/// straight from the trackpad thread. Writes happen on the main thread from the UI.
final class Settings: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let volumeEdge = "volumeEdge"
        static let brightnessEdge = "brightnessEdge"
        static let cornerTaps = "cornerTaps"
        static let appSwitcher = "appSwitcher"
        static let swapEdges = "swapEdges"
        static let sensitivity = "sensitivity"
        static let switcherStep = "switcherStep"
        static let switcherMaxSpeed = "switcherMaxSpeed"
        static let haptics = "haptics"
        static let hudPercent = "hudPercent"
        static let hudStyle = "hudStyle"
        static let hudColor = "hudColor"
        static let hudSize = "hudSize"
        static let hudPosition = "hudPosition"
        static let hudDuration = "hudDuration"
    }

    static let sensitivityRange: ClosedRange<Double> = 0.8...3.0
    static let switcherStepRange: ClosedRange<Double> = 0.04...0.14
    static let switcherMaxSpeedRange: ClosedRange<Double> = 0.25...1.0

    private static let factory: [String: Any] = [
        Key.enabled: true,
        Key.volumeEdge: true,
        Key.brightnessEdge: true,
        Key.cornerTaps: true,
        Key.appSwitcher: true,
        Key.swapEdges: false,
        Key.sensitivity: 1.6,
        Key.switcherStep: 0.07,
        Key.switcherMaxSpeed: 0.5,
        Key.haptics: true,
        Key.hudPercent: true,
        Key.hudStyle: HUDStyle.bar.rawValue,
        Key.hudColor: HUDColor.standard.rawValue,
        Key.hudSize: HUDSize.medium.rawValue,
        Key.hudPosition: HUDPosition.middle.rawValue,
        Key.hudDuration: HUDDuration.normal.rawValue,
    ]

    private let store = UserDefaults.standard
    var onChange: (() -> Void)?
    @Published var loginError: String?

    init() {
        store.register(defaults: Self.factory)
    }

    var enabled: Bool {
        get { store.bool(forKey: Key.enabled) }
        set { save(newValue, Key.enabled) }
    }

    var volumeEdge: Bool {
        get { store.bool(forKey: Key.volumeEdge) }
        set { save(newValue, Key.volumeEdge) }
    }

    var brightnessEdge: Bool {
        get { store.bool(forKey: Key.brightnessEdge) }
        set { save(newValue, Key.brightnessEdge) }
    }

    var cornerTaps: Bool {
        get { store.bool(forKey: Key.cornerTaps) }
        set { save(newValue, Key.cornerTaps) }
    }

    var appSwitcher: Bool {
        get { store.bool(forKey: Key.appSwitcher) }
        set { save(newValue, Key.appSwitcher) }
    }

    var swapEdges: Bool {
        get { store.bool(forKey: Key.swapEdges) }
        set { save(newValue, Key.swapEdges) }
    }

    var sensitivity: Double {
        get { store.double(forKey: Key.sensitivity) }
        set { save(newValue, Key.sensitivity) }
    }

    var switcherStep: Double {
        get { store.double(forKey: Key.switcherStep) }
        set { save(newValue, Key.switcherStep) }
    }

    var switcherMaxSpeed: Double {
        get { store.double(forKey: Key.switcherMaxSpeed) }
        set { save(newValue, Key.switcherMaxSpeed) }
    }

    var haptics: Bool {
        get { store.bool(forKey: Key.haptics) }
        set { save(newValue, Key.haptics) }
    }

    var hudPercent: Bool {
        get { store.bool(forKey: Key.hudPercent) }
        set { save(newValue, Key.hudPercent) }
    }

    var hudStyle: HUDStyle {
        get { HUDStyle(rawValue: store.string(forKey: Key.hudStyle) ?? "") ?? .bar }
        set { save(newValue.rawValue, Key.hudStyle) }
    }

    var hudColor: HUDColor {
        get { HUDColor(rawValue: store.string(forKey: Key.hudColor) ?? "") ?? .standard }
        set { save(newValue.rawValue, Key.hudColor) }
    }

    var hudSize: HUDSize {
        get { HUDSize(rawValue: store.string(forKey: Key.hudSize) ?? "") ?? .medium }
        set { save(newValue.rawValue, Key.hudSize) }
    }

    var hudPosition: HUDPosition {
        get { HUDPosition(rawValue: store.string(forKey: Key.hudPosition) ?? "") ?? .middle }
        set { save(newValue.rawValue, Key.hudPosition) }
    }

    var hudDuration: HUDDuration {
        get { HUDDuration(rawValue: store.string(forKey: Key.hudDuration) ?? "") ?? .normal }
        set { save(newValue.rawValue, Key.hudDuration) }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                loginError = nil
            } catch {
                loginError = error.localizedDescription
            }
        }
    }

    var volumeSide: Edge { swapEdges ? .left : .right }
    var brightnessSide: Edge { swapEdges ? .right : .left }

    var enabledSideEdges: Set<Edge> {
        var edges: Set<Edge> = []
        if volumeEdge { edges.insert(volumeSide) }
        if brightnessEdge { edges.insert(brightnessSide) }
        return edges
    }

    var activeCorners: Set<Corner> {
        guard cornerTaps else { return [] }
        return swapEdges ? [.topRight, .bottomLeft] : [.topLeft, .bottomRight]
    }

    func kind(for edge: Edge) -> LevelKind {
        edge == volumeSide ? .volume : .brightness
    }

    func restoreDefaults() {
        objectWillChange.send()
        for key in Self.factory.keys where key != Key.enabled {
            store.removeObject(forKey: key)
        }
        onChange?()
    }

    private func save(_ value: Any, _ key: String) {
        objectWillChange.send()
        store.set(value, forKey: key)
        onChange?()
    }
}

enum HUDStyle: String, CaseIterable, Identifiable {
    case bar, ring, percent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bar: return "Bar"
        case .ring: return "Ring"
        case .percent: return "Percent only"
        }
    }
}

enum HUDColor: String, CaseIterable, Identifiable {
    case standard, blue, green, orange, pink, purple, yellow
    var id: String { rawValue }
    var title: String { self == .standard ? "Default" : rawValue.capitalized }
}

enum HUDSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scale: CGFloat {
        switch self {
        case .small: return 0.8
        case .medium: return 1
        case .large: return 1.3
        }
    }
}

enum HUDPosition: String, CaseIterable, Identifiable {
    case top, middle, bottom
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum HUDDuration: String, CaseIterable, Identifiable {
    case short, normal, long
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var seconds: Double {
        switch self {
        case .short: return 0.5
        case .normal: return 0.8
        case .long: return 2
        }
    }
}
