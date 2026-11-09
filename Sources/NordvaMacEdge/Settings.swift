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
