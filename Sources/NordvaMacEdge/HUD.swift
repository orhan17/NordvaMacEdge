import AppKit
import NordvaMacEdgeCore

final class HUD {
    private static let size = NSSize(width: 46, height: 196)
    private static let percentHeight: CGFloat = 20
    private static let ringSide: CGFloat = 64
    private static let pillSize = NSSize(width: 86, height: 40)
    private static let margin: CGFloat = 14

    private let settings: Settings
    private var panel: NSPanel
    private let background = NSVisualEffectView()
    private let bar = LevelBarView()
    private let ring = LevelRingView()
    private let icon = NSImageView()
    private let percent = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?
    private var generation = 0
    private var layoutKey = ""

    init(settings: Settings) {
        self.settings = settings
        panel = Self.makePanel()

        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.addSubview(bar)
        background.addSubview(ring)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .labelColor
        background.addSubview(icon)
        percent.alignment = .center
        percent.textColor = .labelColor
        background.addSubview(percent)
        panel.contentView = background
    }

    /// Sizes the panel and its parts for the current style, size and percentage settings.
    private func layout() {
        let scale = settings.hudSize.scale
        let style = settings.hudStyle
        let showPercent = style == .percent || settings.hudPercent
        let key = "\(scale)-\(style.rawValue)-\(showPercent)"
        guard key != layoutKey else { return }
        layoutKey = key

        bar.isHidden = style != .bar
        ring.isHidden = style != .ring
        percent.isHidden = !showPercent

        let size: NSSize
        switch style {
        case .bar:
            let extra = showPercent ? Self.percentHeight : 0
            size = NSSize(width: Self.size.width * scale, height: (Self.size.height + extra) * scale)
            background.maskImage = Self.roundedMask(radius: 20 * scale)
            bar.frame = NSRect(x: (size.width - 8 * scale) / 2, y: 46 * scale, width: 8 * scale, height: 136 * scale)
            icon.isHidden = false
            icon.frame = NSRect(x: (size.width - 22 * scale) / 2, y: 13 * scale, width: 22 * scale, height: 22 * scale)
            setPercent(size: 11 * scale, frame: NSRect(x: 0, y: (46 + 136 + 4) * scale, width: size.width, height: 0))

        case .ring:
            let side = Self.ringSide * scale
            size = NSSize(width: side, height: side)
            background.maskImage = Self.roundedMask(radius: side / 2)
            ring.frame = NSRect(origin: .zero, size: size).insetBy(dx: 7 * scale, dy: 7 * scale)
            ring.lineWidth = 4 * scale
            icon.isHidden = showPercent
            icon.frame = NSRect(x: (side - 20 * scale) / 2, y: (side - 20 * scale) / 2, width: 20 * scale, height: 20 * scale)
            setPercent(size: 13 * scale, frame: NSRect(x: 0, y: side / 2, width: side, height: 0), centered: true)

        case .percent:
            size = NSSize(width: Self.pillSize.width * scale, height: Self.pillSize.height * scale)
            background.maskImage = Self.roundedMask(radius: size.height / 2)
            icon.isHidden = false
            icon.frame = NSRect(x: 13 * scale, y: (size.height - 18 * scale) / 2, width: 18 * scale, height: 18 * scale)
            setPercent(
                size: 15 * scale,
                frame: NSRect(x: 32 * scale, y: size.height / 2, width: size.width - 40 * scale, height: 0),
                centered: true
            )
        }
        panel.setContentSize(size)
        background.frame = NSRect(origin: .zero, size: size)
    }

    /// Places the label with its text centred on frame.minY when `centered`, else starting there.
    private func setPercent(size: CGFloat, frame: NSRect, centered: Bool = false) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        percent.font = font
        let height = ceil(font.ascender - font.descender + font.leading)
        var rect = frame
        rect.size.height = height
        if centered { rect.origin.y -= height / 2 }
        percent.frame = rect
    }

    func show(kind: LevelKind, edge: Edge, level: Float?) {
        generation += 1
        hideWork?.cancel()
        hideWork = nil

        layout()
        let fill = Self.color(settings.hudColor)
        bar.level = level ?? 0
        bar.fill = fill
        ring.level = level ?? 0
        ring.fill = fill
        percent.stringValue = level.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        icon.image = NSImage(systemSymbolName: symbolName(kind: kind, level: level), accessibilityDescription: nil)
        present(at: edge)
        if !panel.isOnActiveSpace {
            replacePanel()
            layout()
            present(at: edge)
        }
    }

    private func present(at edge: Edge) {
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
                guard let self, self.generation == shownGeneration else { return }
                self.panel.orderOut(nil)
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.hudDuration.seconds, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
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
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    // Despite .canJoinAllSpaces, a panel that has been on a desktop space can stay tied to it:
    // ordered front while a full-screen app's space is active, it is "visible" but off screen.
    // A panel made while that space is active does appear there, so swap in a fresh one.
    private func replacePanel() {
        let content = panel.contentView
        panel.contentView = nil
        panel.orderOut(nil)
        panel.close()
        panel = Self.makePanel()
        panel.contentView = content
        layoutKey = ""
    }

    private func place(at edge: Edge) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = edge == .left ? area.minX + Self.margin : area.maxX - size.width - Self.margin
        let y: CGFloat
        switch settings.hudPosition {
        case .top: y = area.maxY - size.height - Self.margin
        case .middle: y = area.midY - size.height / 2
        case .bottom: y = area.minY + Self.margin
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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

    private static func color(_ color: HUDColor) -> NSColor {
        switch color {
        case .standard: return .labelColor
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .orange: return .systemOrange
        case .pink: return .systemPink
        case .purple: return .systemPurple
        case .yellow: return .systemYellow
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

private final class LevelRingView: NSView {
    var level: Float = 0 {
        didSet { needsDisplay = true }
    }
    var fill: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }
    var lineWidth: CGFloat = 4 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width / 2

        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = lineWidth
        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        track.stroke()

        guard level > 0 else { return }
        // Clockwise from 12 o'clock.
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * CGFloat(min(level, 1)), clockwise: true)
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        fill.setStroke()
        arc.stroke()
    }
}

private final class LevelBarView: NSView {
    var level: Float = 0 {
        didSet { needsDisplay = true }
    }
    var fill: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.width / 2
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        guard level > 0 else { return }
        let height = max(bounds.height * CGFloat(level), bounds.width)
        let filled = NSRect(x: 0, y: 0, width: bounds.width, height: height)
        fill.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}
