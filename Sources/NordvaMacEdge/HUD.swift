import AppKit
import NordvaMacEdgeCore

/// Индикатор уровня. Системный значок громкости сам не появится: он показывается
/// только на нажатие клавиш, а мы меняем уровень напрямую.
final class HUD {
    private static let size = NSSize(width: 46, height: 196)
    private static let margin: CGFloat = 14

    private let panel: NSPanel
    private let bar = LevelBarView(frame: NSRect(x: 19, y: 46, width: 8, height: 136))
    private let icon = NSImageView(frame: NSRect(x: 12, y: 13, width: 22, height: 22))
    private var hideWork: DispatchWorkItem?
    private var generation = 0

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        // Иначе индикатор не появится поверх полноэкранного приложения или на другом столе.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: 20)
        background.addSubview(bar)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .labelColor
        background.addSubview(icon)
        panel.contentView = background
    }

    func show(kind: LevelKind, edge: Edge, level: Float?) {
        generation += 1
        hideWork?.cancel()
        hideWork = nil

        bar.level = level ?? 0
        icon.image = NSImage(systemSymbolName: symbolName(kind: kind, level: level), accessibilityDescription: nil)
        place(at: edge)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    func hideSoon() {
        let shownGeneration = generation
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                self?.panel.animator().alphaValue = 0
            }, completionHandler: {
                // Пока индикатор гас, мог начаться новый жест.
                guard let self, self.generation == shownGeneration else { return }
                self.panel.orderOut(nil)
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func place(at edge: Edge) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let x = edge == .left ? area.minX + Self.margin : area.maxX - Self.size.width - Self.margin
        panel.setFrameOrigin(NSPoint(x: x, y: area.midY - Self.size.height / 2))
    }

    private func symbolName(kind: LevelKind, level: Float?) -> String {
        switch kind {
        case .brightness:
            return (level ?? 0) < 0.4 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            guard let level, level > 0 else { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            return level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

private final class LevelBarView: NSView {
    var level: Float = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.width / 2
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        guard level > 0 else { return }
        // Минимальная высота, чтобы скругление на малых уровнях не сплющивалось.
        let height = max(bounds.height * CGFloat(level), bounds.width)
        let filled = NSRect(x: 0, y: 0, width: bounds.width, height: height)
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}
