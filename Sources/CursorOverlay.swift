import Cocoa
import QuartzCore

// MARK: - Agent cursor overlay
//
// Smoothness comes from:
//  • CALayers composited on the GPU. The arrow is a pre-rendered bitmap; each
//    frame only changes position/transform (no full-screen NSView redraw).
//  • The display's own vsync (CADisplayLink, 60/120 Hz) with time-based
//    interpolation, so a dropped frame never causes a stutter or slowdown.
//  • Minimum-jerk speed along an arc-length parameterised bow (Motion.swift).
//  • Springs for tilt / lift / press so no visual state pops.
// The overlay is click-through; the real pointer is never moved.

public final class CursorOverlay: NSObject {
    public static let shared = CursorOverlay()

    private struct Host { let panel: NSPanel; let root: CALayer; let cgFrame: CGRect }
    private var hosts: [Host] = []
    private var currentHost = -1

    private let cursorLayer = CALayer()
    private let arrowLayer = CALayer()
    private let captionLayer = CALayer()
    private let captionText = CATextLayer()
    private var normalImage: CGImage?
    private var pressedImage: CGImage?

    public private(set) var position: CGPoint = .zero
    private var visible = false
    private var setupDone = false

    private struct Glide {
        let path: CursorMotionPath
        let start: CFTimeInterval
        let duration: Double
        let completion: (() -> Void)?
    }
    private var glide: Glide?
    private var lastTick: CFTimeInterval = 0
    private var lastPoint: CGPoint = .zero
    private var tilt = Spring(0, stiffness: 260, dampingRatio: 0.9)
    private var lift = Spring(1, stiffness: 520, dampingRatio: 0.8)
    private var press = Spring(1, stiffness: 900, dampingRatio: 0.55)
    private var displayLink: CADisplayLink?
    private var idleTimer: Timer?

    public var autoHideAfter: TimeInterval = 4.0
    public var speed: Double = 1.0

    // Codex cursor svg geometry (24pt box); hotspot = visual tip of the rounded arrow
    private let assetBox: CGFloat = 24
    private let hotspot = CGPoint(x: 3.65, y: 3.65)
    private let scale: CGFloat = 1.18
    private let pad: CGFloat = 8
    private var side: CGFloat { (assetBox + pad * 2) * scale }

    // MARK: Setup

    public func setup(startAt start: CGPoint? = nil) {
        precondition(Thread.isMainThread)
        if setupDone { return }
        setupDone = true
        renderImages()

        arrowLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let hx = (hotspot.x + pad) * scale, hyTop = (hotspot.y + pad) * scale
        arrowLayer.anchorPoint = CGPoint(x: hx / side, y: (side - hyTop) / side)  // bottom-left unit space
        arrowLayer.position = .zero
        arrowLayer.contents = normalImage
        arrowLayer.contentsScale = 3
        arrowLayer.contentsGravity = .resize
        cursorLayer.addSublayer(arrowLayer)
        cursorLayer.opacity = 0

        captionText.fontSize = 12
        captionText.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        captionText.foregroundColor = NSColor.white.cgColor
        captionText.contentsScale = 3
        captionText.alignmentMode = .left
        captionLayer.backgroundColor = NSColor(white: 0.05, alpha: 0.86).cgColor
        captionLayer.cornerRadius = 8
        captionLayer.addSublayer(captionText)
        captionLayer.opacity = 0
        cursorLayer.addSublayer(captionLayer)

        buildHosts()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let p = start ?? (CGEvent(source: nil)?.location ?? CGPoint(x: 400, y: 400))
        position = p
        lastPoint = p
        place(p)
    }

    private func buildHosts() {
        for h in hosts { h.panel.orderOut(nil) }
        hosts.removeAll()
        cursorLayer.removeFromSuperlayer()
        currentHost = -1
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.setFrame(screen.frame, display: false)
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            let root = view.layer!
            root.masksToBounds = false
            panel.contentView = view
            panel.orderFrontRegardless()
            hosts.append(Host(panel: panel, root: root, cgFrame: CoordinateSpace.cgRect(fromCocoa: screen.frame)))
        }
        if let first = hosts.first?.panel.contentView {
            displayLink?.invalidate()
            let link = first.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            link.isPaused = true
            displayLink = link
        }
    }

    @objc private func screensChanged() {
        buildHosts()
        place(position)
    }

    // MARK: Rendering of the arrow bitmaps (done once)

    private func arrowPaths() -> (outer: CGPath, inner: CGPath) {
        let outer = CGMutablePath()
        outer.move(to: CGPoint(x: 3.10042, y: 6.29005))
        outer.addCurve(to: CGPoint(x: 6.28987, y: 3.1006), control1: CGPoint(x: 2.40168, y: 4.30935), control2: CGPoint(x: 4.30916, y: 2.40186))
        outer.addLine(to: CGPoint(x: 18.8719, y: 7.54103))
        outer.addCurve(to: CGPoint(x: 19.2801, y: 12.0693), control1: CGPoint(x: 20.9168, y: 8.263), control2: CGPoint(x: 21.1141, y: 11.0361))
        outer.addLine(to: CGPoint(x: 19.0965, y: 12.1641))
        outer.addLine(to: CGPoint(x: 14.535, y: 14.293))
        outer.addCurve(to: CGPoint(x: 14.3367, y: 14.459), control1: CGPoint(x: 14.4552, y: 14.3302), control2: CGPoint(x: 14.3867, y: 14.3878))
        outer.addLine(to: CGPoint(x: 14.2928, y: 14.5352))
        outer.addLine(to: CGPoint(x: 12.1639, y: 19.0967))
        outer.addCurve(to: CGPoint(x: 7.54084, y: 18.8721), control1: CGPoint(x: 11.2172, y: 21.1253), control2: CGPoint(x: 8.2861, y: 20.9829))
        outer.closeSubpath()

        let inner = CGMutablePath()
        inner.move(to: CGPoint(x: 5.62483, y: 4.98732))
        inner.addCurve(to: CGPoint(x: 4.98713, y: 5.62501), control1: CGPoint(x: 5.22864, y: 4.84749), control2: CGPoint(x: 4.8473, y: 5.22882))
        inner.addLine(to: CGPoint(x: 9.42756, y: 18.2061))
        inner.addCurve(to: CGPoint(x: 10.3514, y: 18.251), control1: CGPoint(x: 9.57668, y: 18.6281), control2: CGPoint(x: 10.162, y: 18.6566))
        inner.addLine(to: CGPoint(x: 12.4803, y: 13.6895))
        inner.addLine(to: CGPoint(x: 12.5819, y: 13.4942))
        inner.addCurve(to: CGPoint(x: 13.6893, y: 12.4805), control1: CGPoint(x: 12.8374, y: 13.0525), control2: CGPoint(x: 13.2237, y: 12.6977))
        inner.addLine(to: CGPoint(x: 18.2508, y: 10.3516))
        inner.addCurve(to: CGPoint(x: 18.2059, y: 9.42775), control1: CGPoint(x: 18.6564, y: 10.1622), control2: CGPoint(x: 18.6279, y: 9.57686))
        inner.closeSubpath()
        return (outer, inner)
    }

    private func renderImages() {
        normalImage = renderArrow(pressed: false)
        pressedImage = renderArrow(pressed: true)
    }

    private func renderArrow(pressed: Bool) -> CGImage? {
        let px = Int(side * 3)
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Map SVG space (y down) into the bitmap (y up).
        ctx.scaleBy(x: 3, y: 3)
        ctx.translateBy(x: 0, y: side)
        ctx.scaleBy(x: 1, y: -1)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: pad, y: pad)
        let (outer, inner) = arrowPaths()

        // Soft ambient shadow (offset downwards in screen space).
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0.6, height: -1.6), blur: 4.5, color: NSColor.black.withAlphaComponent(0.32).cgColor)
        ctx.addPath(outer)
        ctx.setFillColor(NSColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Body: white glass fill (normal) or solid ink (pressed)
        ctx.addPath(inner)
        ctx.setFillColor(pressed ? NSColor(srgbRed: 0.05, green: 0.05, blue: 0.05, alpha: 1).cgColor
                                 : NSColor.white.withAlphaComponent(0.96).cgColor)
        ctx.fillPath()
        return ctx.makeImage()
    }

    // MARK: Placement

    private func hostIndex(for p: CGPoint) -> Int {
        if let i = hosts.firstIndex(where: { $0.cgFrame.contains(p) }) { return i }
        return hosts.indices.min(by: {
            hypot(hosts[$0].cgFrame.midX - p.x, hosts[$0].cgFrame.midY - p.y) <
            hypot(hosts[$1].cgFrame.midX - p.x, hosts[$1].cgFrame.midY - p.y)
        }) ?? 0
    }

    private func place(_ p: CGPoint) {
        guard !hosts.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let i = hostIndex(for: p)
        if i != currentHost {
            cursorLayer.removeFromSuperlayer()
            hosts[i].root.addSublayer(cursorLayer)
            currentHost = i
        }
        let h = hosts[i]
        cursorLayer.position = CGPoint(x: p.x - h.cgFrame.minX, y: h.cgFrame.height - (p.y - h.cgFrame.minY))
        let s = CGFloat(lift.value * press.value)
        arrowLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(tilt.value)).scaledBy(x: s, y: s))
        CATransaction.commit()
    }

    // MARK: Visibility

    public func show() {
        precondition(Thread.isMainThread)
        idleTimer?.invalidate()
        guard !visible else { return }
        visible = true
        for h in hosts { h.panel.orderFrontRegardless() }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = cursorLayer.presentation()?.opacity ?? 0
        a.toValue = 1
        a.duration = 0.22
        a.timingFunction = CAMediaTimingFunction(name: .easeOut)
        cursorLayer.add(a, forKey: "fade")
        cursorLayer.opacity = 1
    }

    public func hide() {
        precondition(Thread.isMainThread)
        guard visible else { return }
        visible = false
        setCaption(nil)
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = cursorLayer.presentation()?.opacity ?? 1
        a.toValue = 0
        a.duration = 0.35
        a.timingFunction = CAMediaTimingFunction(name: .easeIn)
        cursorLayer.add(a, forKey: "fade")
        cursorLayer.opacity = 0
    }

    /// Fade out after a period of inactivity (Codex hides its cursor between turns).
    public func scheduleAutoHide() {
        idleTimer?.invalidate()
        guard autoHideAfter > 0 else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: autoHideAfter, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    // MARK: Caption pill ("Clicking “Search”…")

    public func setCaption(_ text: String?) {
        precondition(Thread.isMainThread)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        if let t = text, !t.isEmpty {
            let clipped = t.count > 48 ? String(t.prefix(48)) + "…" : t
            let font = NSFont.systemFont(ofSize: 12, weight: .medium)
            let size = (clipped as NSString).size(withAttributes: [.font: font])
            captionText.string = clipped
            captionLayer.bounds = CGRect(x: 0, y: 0, width: ceil(size.width) + 16, height: 22)
            captionText.frame = CGRect(x: 8, y: 3, width: ceil(size.width) + 2, height: 16)
            captionLayer.anchorPoint = CGPoint(x: 0, y: 1)
            captionLayer.position = CGPoint(x: 18, y: -20)
            captionLayer.opacity = 1
        } else {
            captionLayer.opacity = 0
        }
        CATransaction.commit()
    }

    // MARK: Motion

    /// Glide to a global (top-left origin) point. `targetWidth` feeds Fitts' law.
    public func glide(to dest: CGPoint, targetWidth: CGFloat = 28, completion: (() -> Void)? = nil) {
        precondition(Thread.isMainThread)
        show()
        let to = CoordinateSpace.clampToScreens(dest)
        let from = position
        let d = hypot(to.x - from.x, to.y - from.y)
        if d < 1.5 {
            position = to
            place(to)
            completion?()
            return
        }
        glide?.completion?()   // a retarget completes the previous request immediately
        let duration = Motion.duration(distance: d, targetWidth: targetWidth, speed: speed)
        glide = Glide(path: CursorMotionPath(from: from, to: to), start: CACurrentMediaTime(), duration: duration, completion: completion)
        lift.target = 1.06
        lastTick = CACurrentMediaTime()
        lastPoint = from
        displayLink?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = max(1.0 / 240, min(now - lastTick, 1.0 / 20))
        lastTick = now

        var finished: (() -> Void)?
        if let g = glide {
            let t = (now - g.start) / g.duration
            let p = g.path.point(atDistanceFraction: Motion.minimumJerk(t))
            let vx = Double(p.x - lastPoint.x) / dt
            // Lean slightly into horizontal travel, like a pointer held by a wrist.
            tilt.target = max(-0.16, min(0.16, -vx / 9000))
            position = p
            lastPoint = p
            if t >= 1 {
                position = g.path.p3
                glide = nil
                tilt.target = 0
                lift.target = 1
                finished = g.completion
            }
        }
        tilt.step(dt); lift.step(dt); press.step(dt)
        place(position)
        if glide == nil && tilt.isSettled && lift.isSettled && press.isSettled {
            link.isPaused = true
        }
        finished?()
    }

    // MARK: Press feedback

    /// Visual press: arrow fills in and dips, then a ripple ring expands from the tip.
    public func pressDown() {
        precondition(Thread.isMainThread)
        show()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        arrowLayer.contents = pressedImage
        CATransaction.commit()
        press.target = 0.84
        displayLink?.isPaused = false
        ripple(at: position)
    }

    public func pressUp() {
        precondition(Thread.isMainThread)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        arrowLayer.contents = normalImage
        CATransaction.commit()
        press.target = 1
        displayLink?.isPaused = false
    }

    public func ripple(at p: CGPoint, color: NSColor = NSColor(white: 0.05, alpha: 1)) {
        guard !hosts.isEmpty else { return }
        let h = hosts[hostIndex(for: p)]
        let local = CGPoint(x: p.x - h.cgFrame.minX, y: h.cgFrame.height - (p.y - h.cgFrame.minY))
        for (i, maxR) in [(0, CGFloat(22)), (1, CGFloat(34))] {
            let ring = CAShapeLayer()
            ring.path = CGPath(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2), transform: nil)
            ring.position = local
            ring.fillColor = nil
            ring.strokeColor = color.withAlphaComponent(i == 0 ? 0.55 : 0.28).cgColor
            ring.lineWidth = 1.0 / maxR * 2.2   // stays ~2.2pt after scaling
            ring.opacity = 0
            if cursorLayer.superlayer === h.root { h.root.insertSublayer(ring, below: cursorLayer) } else { h.root.addSublayer(ring) }

            let group = CAAnimationGroup()
            let s = CABasicAnimation(keyPath: "transform.scale")
            s.fromValue = 2; s.toValue = maxR
            let o = CAKeyframeAnimation(keyPath: "opacity")
            o.values = [0.0, 1.0, 0.0]; o.keyTimes = [0, 0.15, 1]
            group.animations = [s, o]
            group.duration = 0.46 + Double(i) * 0.08
            group.beginTime = CACurrentMediaTime() + Double(i) * 0.05
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.3, 1)
            group.isRemovedOnCompletion = true
            CATransaction.begin()
            CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
            ring.add(group, forKey: "ripple")
            CATransaction.commit()
        }
    }

    // MARK: Blocking helpers for worker threads

    public static func onMain<T>(_ body: @escaping () -> T) -> T {
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
    }

    /// Glide and block the calling (non-main) thread until the cursor arrives.
    public func glideAndWait(to p: CGPoint, targetWidth: CGFloat = 28, timeout: Double = 2.0) {
        if Thread.isMainThread { glide(to: p, targetWidth: targetWidth); return }
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.main.async { self.glide(to: p, targetWidth: targetWidth) { sem.signal() } }
        _ = sem.wait(timeout: .now() + timeout)
    }
}
