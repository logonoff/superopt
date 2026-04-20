import Cocoa
import QuartzCore

/// Ripple animation ported from GNOME Shell js/ui/ripples.js and _corner-ripple.scss.
/// Three concentric quarter-circle ripples expand from the top-left corner of a screen.
class RippleAnimation {
    private var activeWindows: [NSWindow] = []

    private struct RippleConfig {
        let delay: CFTimeInterval
        let duration: CFTimeInterval
        let startScale: CGFloat
        let startOpacity: Float
        let finalScale: CGFloat
    }

    // GNOME's parameters
    private let ripples: [RippleConfig] = [
        RippleConfig(delay: 0.0, duration: 0.83, startScale: 0.25,
                     startOpacity: 1.0, finalScale: 1.5),
        RippleConfig(delay: 0.05, duration: 1.0, startScale: 0.0,
                     startOpacity: 0.7, finalScale: 1.25),
        RippleConfig(delay: 0.35, duration: 1.0, startScale: 0.0,
                     startOpacity: 0.3, finalScale: 1.0)
    ]

    private static let rippleSize: CGFloat = 52
    private static let windowSize: CGFloat = ceil(rippleSize * 1.5) + 2

    func play(onScreen screen: NSScreen) {
        let window = makeWindow(on: screen)
        guard let rootLayer = window.contentView?.layer else { return }

        let path = makeQuarterCirclePath()
        let now = CACurrentMediaTime()

        for config in ripples {
            animateRipple(config: config, path: path, now: now, rootLayer: rootLayer)
        }

        window.orderFrontRegardless()
        activeWindows.append(window)

        let maxDuration = ripples.map { $0.delay + $0.duration }.max() ?? 1.5
        DispatchQueue.main.asyncAfter(
            deadline: .now() + maxDuration + 0.1
        ) { [weak self] in
            window.orderOut(nil)
            self?.activeWindows.removeAll { $0 === window }
        }
    }

    private func makeWindow(on screen: NSScreen) -> NSWindow {
        let frame = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - Self.windowSize,
            width: Self.windowSize, height: Self.windowSize
        )
        let window = NSWindow(
            contentRect: frame, styleMask: .borderless,
            backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        window.contentView = view
        return window
    }

    private func makeQuarterCirclePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: Self.rippleSize))
        path.addLine(to: CGPoint(x: Self.rippleSize, y: Self.rippleSize))
        path.addArc(
            center: CGPoint(x: 0, y: Self.rippleSize),
            radius: Self.rippleSize,
            startAngle: 0, endAngle: -.pi / 2, clockwise: true
        )
        path.closeSubpath()
        return path
    }

    private func animateRipple(
        config: RippleConfig, path: CGPath,
        now: CFTimeInterval, rootLayer: CALayer
    ) {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = NSColor(white: 1.0, alpha: 0.25).cgColor
        layer.bounds = CGRect(x: 0, y: 0,
                              width: Self.rippleSize, height: Self.rippleSize)
        layer.anchorPoint = CGPoint(x: 0, y: 1)
        layer.position = CGPoint(x: 0, y: Self.windowSize)
        layer.opacity = 0

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = config.startScale
        scaleAnim.toValue = config.finalScale
        scaleAnim.duration = config.duration
        scaleAnim.beginTime = now + config.delay
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scaleAnim.fillMode = .both
        scaleAnim.isRemovedOnCompletion = false

        let opacityAnim = CABasicAnimation(keyPath: "opacity")
        opacityAnim.fromValue = sqrt(config.startOpacity)
        opacityAnim.toValue = 0
        opacityAnim.duration = config.duration
        opacityAnim.beginTime = now + config.delay
        opacityAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        opacityAnim.fillMode = .both
        opacityAnim.isRemovedOnCompletion = false

        rootLayer.addSublayer(layer)
        layer.add(scaleAnim, forKey: "scale")
        layer.add(opacityAnim, forKey: "opacity")
    }
}
