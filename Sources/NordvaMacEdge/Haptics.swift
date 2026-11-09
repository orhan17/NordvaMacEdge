import AppKit
import NordvaMacEdgeCore

/// Trackpad clicks through the public haptics API. They are only felt while a finger
/// rests on the trackpad, which is always the case during a gesture.
final class Haptics {
    private let settings: Settings

    init(settings: Settings) {
        self.settings = settings
    }

    func play(_ haptic: Haptic) {
        guard settings.haptics else { return }
        DispatchQueue.main.async {
            NSHapticFeedbackManager.defaultPerformer.perform(
                haptic == .stop ? .generic : .levelChange,
                performanceTime: .now
            )
        }
    }
}
