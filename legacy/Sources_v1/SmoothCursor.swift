import Cocoa
import CoreGraphics
import QuartzCore

// MARK: - Motion Physics Configuration
public struct MotionConfiguration {
    public var baseDuration: Double
    public var arcCurvature: CGFloat
    public var maxStretch: CGFloat
    public var springDamping: Double
    public var frameRate: Double

    public static let silkyDefault = MotionConfiguration(
        baseDuration: 0.42,
        arcCurvature: 0.18,
        maxStretch: 0.28,
        springDamping: 0.82,
        frameRate: 120.0
    )

    public static let snappy = MotionConfiguration(
        baseDuration: 0.28,
        arcCurvature: 0.12,
        maxStretch: 0.20,
        springDamping: 0.88,
        frameRate: 120.0
    )
}

// MARK: - Official Codex Computer Use Vector Assets
private let codexHollowSVGData = """
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M3.10042 6.29005C2.40168 4.30935 4.30916 2.40186 6.28987 3.1006L18.8719 7.54103C20.9168 8.263 21.1141 11.0361 19.2801 12.0693L19.0965 12.1641L14.535 14.293C14.4552 14.3302 14.3867 14.3878 14.3367 14.459L14.2928 14.5352L12.1639 19.0967C11.2172 21.1253 8.2861 20.9829 7.54084 18.8721L3.10042 6.29005ZM5.62483 4.98732C5.22864 4.84749 4.8473 5.22882 4.98713 5.62501L9.42756 18.2061C9.57668 18.6281 10.162 18.6566 10.3514 18.251L12.4803 13.6895L12.5819 13.4942C12.8374 13.0525 13.2237 12.6977 13.6893 12.4805L18.2508 10.3516C18.6564 10.1622 18.6279 9.57686 18.2059 9.42775L5.62483 4.98732Z" fill="#0D0D0D"/></svg>
""".data(using: .utf8)!

private let codexSolidSVGData = """
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M3.10042 6.29005C2.40168 4.30935 4.30916 2.40186 6.28987 3.1006L18.8719 7.54103C20.9168 8.263 21.1141 11.0361 19.2801 12.0693L19.0965 12.1641L14.535 14.293C14.4552 14.3302 14.3867 14.3878 14.3367 14.459L14.2928 14.5352L12.1639 19.0967C11.2172 21.1253 8.2861 20.9829 7.54084 18.8721L3.10042 6.29005Z" fill="#0D0D0D"/></svg>
""".data(using: .utf8)!

// MARK: - Official Codex Virtual Cursor View
final class CursorOverlayView: NSView {
    var position: CGPoint = .zero {
        didSet { needsDisplay = true }
    }
    
    var tangentAngle: CGFloat = CGFloat.pi / 4 { // Default pointing top-left
        didSet { needsDisplay = true }
    }
    
    var stretchScale: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }
    
    var isPressed: Bool = false {
        didSet { needsDisplay = true }
    }
    
    var clickRippleRadius: CGFloat = 0.0 {
        didSet { needsDisplay = true }
    }
    
    var clickRippleAlpha: CGFloat = 0.0 {
        didSet { needsDisplay = true }
    }

    private let codexHollowImage: NSImage = NSImage(data: codexHollowSVGData) ?? NSImage()
    private let codexSolidImage: NSImage = NSImage(data: codexSolidSVGData) ?? NSImage()

    // Top-Left standard screen coordinates (Flipped = true)
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()

        // 1. Concentric Click Ripple Rings
        if clickRippleAlpha > 0.01 {
            ctx.saveGState()
            // Outer subtle ripple
            ctx.setStrokeColor(NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: clickRippleAlpha * 0.40).cgColor)
            ctx.setLineWidth(1.8)
            let outerCircle = CGRect(
                x: position.x - clickRippleRadius * 1.25,
                y: position.y - clickRippleRadius * 1.25,
                width: clickRippleRadius * 2.5,
                height: clickRippleRadius * 2.5
            )
            ctx.strokeEllipse(in: outerCircle)

            // Inner crisp ripple
            ctx.setStrokeColor(NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: clickRippleAlpha * 0.85).cgColor)
            ctx.setLineWidth(2.2)
            let innerCircle = CGRect(
                x: position.x - clickRippleRadius,
                y: position.y - clickRippleRadius,
                width: clickRippleRadius * 2,
                height: clickRippleRadius * 2
            )
            ctx.strokeEllipse(in: innerCircle)
            ctx.restoreGState()
        }

        // 2. Transform to Cursor Hotspot
        ctx.translateBy(x: position.x, y: position.y)

        // Dynamic tilt rotation along motion path
        let tilt = (tangentAngle - CGFloat.pi / 4) * 0.20
        ctx.rotate(by: tilt)

        // Squash & Stretch physics
        let sx = isPressed ? 0.85 : stretchScale
        let sy = isPressed ? 0.85 : (1.0 / sqrt(max(0.6, stretchScale)))
        ctx.scaleBy(x: sx, y: sy)

        // 3. Drop Shadow for High Contrast
        ctx.setShadow(
            offset: CGSize(width: 1.5, height: 3.0),
            blur: 6.5,
            color: NSColor.black.withAlphaComponent(0.35).cgColor
        )

        // 4. Draw Official Codex Cursor
        let cursorScale: CGFloat = 1.35
        let drawRect = NSRect(
            x: -3.35 * cursorScale,
            y: -3.35 * cursorScale,
            width: 24.0 * cursorScale,
            height: 24.0 * cursorScale
        )

        // Inner frosted backing for clarity on both dark & light backgrounds
        let innerPath = CGMutablePath()
        innerPath.move(to: CGPoint(x: (5.62483 - 3.35) * cursorScale, y: (4.98732 - 3.35) * cursorScale))
        innerPath.addCurve(to: CGPoint(x: (4.98713 - 3.35) * cursorScale, y: (5.62501 - 3.35) * cursorScale),
                           control1: CGPoint(x: (5.22864 - 3.35) * cursorScale, y: (4.84749 - 3.35) * cursorScale),
                           control2: CGPoint(x: (4.8473 - 3.35) * cursorScale, y: (5.22882 - 3.35) * cursorScale))
        innerPath.addLine(to: CGPoint(x: (9.42756 - 3.35) * cursorScale, y: (18.2061 - 3.35) * cursorScale))
        innerPath.addCurve(to: CGPoint(x: (10.3514 - 3.35) * cursorScale, y: (18.251 - 3.35) * cursorScale),
                           control1: CGPoint(x: (9.57668 - 3.35) * cursorScale, y: (18.6281 - 3.35) * cursorScale),
                           control2: CGPoint(x: (10.162 - 3.35) * cursorScale, y: (18.6566 - 3.35) * cursorScale))
        innerPath.addLine(to: CGPoint(x: (12.4803 - 3.35) * cursorScale, y: (13.6895 - 3.35) * cursorScale))
        innerPath.addLine(to: CGPoint(x: (12.5819 - 3.35) * cursorScale, y: (13.4942 - 3.35) * cursorScale))
        innerPath.addCurve(to: CGPoint(x: (13.6893 - 3.35) * cursorScale, y: (12.4805 - 3.35) * cursorScale),
                           control1: CGPoint(x: (12.8374 - 3.35) * cursorScale, y: (13.0525 - 3.35) * cursorScale),
                           control2: CGPoint(x: (13.2237 - 3.35) * cursorScale, y: (12.6977 - 3.35) * cursorScale))
        innerPath.addLine(to: CGPoint(x: (18.2508 - 3.35) * cursorScale, y: (10.3516 - 3.35) * cursorScale))
        innerPath.addCurve(to: CGPoint(x: (18.2059 - 3.35) * cursorScale, y: (9.42775 - 3.35) * cursorScale),
                           control1: CGPoint(x: (18.6564 - 3.35) * cursorScale, y: (10.1622 - 3.35) * cursorScale),
                           control2: CGPoint(x: (18.6279 - 3.35) * cursorScale, y: (9.57686 - 3.35) * cursorScale))
        innerPath.closeSubpath()

        ctx.addPath(innerPath)
        let innerFill = isPressed ? NSColor(white: 0.08, alpha: 0.98) : NSColor.white.withAlphaComponent(0.92)
        ctx.setFillColor(innerFill.cgColor)
        ctx.fillPath()

        // Draw exact Codex vector arrow
        let cursorImg = isPressed ? codexSolidImage : codexHollowImage
        cursorImg.draw(in: drawRect)

        ctx.restoreGState()
    }
}

// MARK: - Action Step in Continuous Flow
public enum CursorFlowStep {
    case move(to: CGPoint)
    case hover(duration: Double)
    case click(at: CGPoint? = nil, preserveUserMouse: Bool = true)
    case axClick(element: IndexedAXElement)
    case scroll(dy: Int, duration: Double = 0.5)
}

// MARK: - Virtual Cursor Window Manager
public final class SmoothCursorEngine: @unchecked Sendable {
    public static let shared = SmoothCursorEngine()

    private var overlayWindow: NSPanel?
    private var cursorView: CursorOverlayView?
    private var currentPosition: CGPoint = .zero
    private let queue = DispatchQueue(label: "com.antigravity.smoothcursor", qos: .userInteractive)

    private init() {
        if Thread.isMainThread {
            self.setupOverlayWindow()
        } else {
            DispatchQueue.main.sync {
                self.setupOverlayWindow()
            }
        }
    }

    private func setupOverlayWindow() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        // Start from center of the screen
        currentPosition = CGPoint(x: frame.midX, y: frame.midY)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu // Floating on top of all windows
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let view = CursorOverlayView(frame: frame)
        view.position = currentPosition
        panel.contentView = view

        self.overlayWindow = panel
        self.cursorView = view
        panel.orderFrontRegardless()
    }

    public func setPosition(_ pt: CGPoint) {
        currentPosition = pt
        DispatchQueue.main.async {
            self.cursorView?.position = pt
        }
    }

    public func getCurrentPosition() -> CGPoint {
        return currentPosition
    }

    // MARK: - Silky Smooth Motion
    public func move(
        to destination: CGPoint,
        config: MotionConfiguration = .silkyDefault,
        completion: (@Sendable () -> Void)? = nil
    ) {
        let start = self.currentPosition
        let deltaX = destination.x - start.x
        let deltaY = destination.y - start.y
        let distance = hypot(deltaX, deltaY)

        if distance < 2.0 {
            DispatchQueue.main.async {
                self.currentPosition = destination
                self.cursorView?.position = destination
                self.cursorView?.stretchScale = 1.0
                completion?()
            }
            return
        }

        // Adaptive duration: fast for short hops, smooth for long sweeps
        let duration = max(0.22, min(0.65, config.baseDuration * sqrt(distance / 500.0)))

        // Natural Bezier arc: perpendicular deflection
        let perpX = -deltaY / distance
        let perpY = deltaX / distance
        let arcMagnitude = min(distance * config.arcCurvature, 120.0)
        let arcSign: CGFloat = (deltaX > 0) ? 1.0 : -1.0

        let p1 = CGPoint(
            x: start.x + deltaX * 0.35 + perpX * arcMagnitude * arcSign,
            y: start.y + deltaY * 0.35 + perpY * arcMagnitude * arcSign
        )
        let p2 = CGPoint(
            x: start.x + deltaX * 0.70 + perpX * arcMagnitude * 0.5 * arcSign,
            y: start.y + deltaY * 0.70 + perpY * arcMagnitude * 0.5 * arcSign
        )

        let totalFrames = max(18, Int(duration * config.frameRate))
        let frameInterval = duration / Double(totalFrames)

        var frameIndex = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: frameInterval)

        timer.setEventHandler { [weak self] in
            guard let self = self else {
                timer.cancel()
                return
            }

            if frameIndex > totalFrames {
                timer.cancel()
                DispatchQueue.main.async {
                    self.currentPosition = destination
                    self.cursorView?.position = destination
                    self.cursorView?.stretchScale = 1.0
                    completion?()
                }
                return
            }

            let rawT = CGFloat(frameIndex) / CGFloat(totalFrames)
            let easedT = self.cubicEaseInOut(rawT)

            let invT = 1.0 - easedT
            let currentPt = CGPoint(
                x: pow(invT, 3) * start.x + 3 * pow(invT, 2) * easedT * p1.x + 3 * invT * pow(easedT, 2) * p2.x + pow(easedT, 3) * destination.x,
                y: pow(invT, 3) * start.y + 3 * pow(invT, 2) * easedT * p1.y + 3 * invT * pow(easedT, 2) * p2.y + pow(easedT, 3) * destination.y
            )

            let tangent = CGPoint(
                x: 3 * pow(invT, 2) * (p1.x - start.x) + 6 * invT * easedT * (p2.x - p1.x) + 3 * pow(easedT, 2) * (destination.x - p2.x),
                y: 3 * pow(invT, 2) * (p1.y - start.y) + 6 * invT * easedT * (p2.y - p1.y) + 3 * pow(easedT, 2) * (destination.y - p2.y)
            )
            let speed = hypot(tangent.x, tangent.y)
            let angle = atan2(tangent.y, tangent.x)

            let normalizedSpeed = min(1.0, speed / (distance * 1.8))
            let stretch = 1.0 + (config.maxStretch * sin(rawT * CGFloat.pi) * normalizedSpeed)

            DispatchQueue.main.async {
                self.currentPosition = currentPt
                self.cursorView?.position = currentPt
                self.cursorView?.tangentAngle = angle
                self.cursorView?.stretchScale = stretch
            }

            frameIndex += 1
        }

        timer.resume()
    }

    // MARK: - Accurate Click with Ripple Feedback (Preserving User's Physical Mouse)
    public func click(
        at point: CGPoint? = nil,
        injectCGEvent: Bool = true,
        preserveUserMouse: Bool = true,
        completion: (@Sendable () -> Void)? = nil
    ) {
        let clickTarget = point ?? self.currentPosition

        let doClick: @Sendable () -> Void = { [weak self] in
            guard let self = self else { return }

            // 1. Squash & Snap down
            DispatchQueue.main.async {
                self.cursorView?.isPressed = true
                self.cursorView?.clickRippleRadius = 8.0
                self.cursorView?.clickRippleAlpha = 0.95
            }

            // Standard CoreGraphics event injection with hardware mouse preservation
            if injectCGEvent {
                self.injectMouseEvent(type: .leftMouseDown, at: clickTarget, restoreUserMouse: preserveUserMouse)
            }

            // 2. Animate ripple outwards
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.09) {
                if injectCGEvent {
                    self.injectMouseEvent(type: .leftMouseUp, at: clickTarget, restoreUserMouse: preserveUserMouse)
                }

                for step in 1...12 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.018) {
                        self.cursorView?.clickRippleRadius = 8.0 + CGFloat(step) * 3.2
                        self.cursorView?.clickRippleAlpha = max(0, 0.95 - CGFloat(step) * 0.08)
                        if step == 4 {
                            self.cursorView?.isPressed = false
                        }
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                    completion?()
                }
            }
        }

        if let dest = point, dest != self.currentPosition {
            self.move(to: dest, completion: doClick)
        } else {
            doClick()
        }
    }

    // MARK: - Smooth Momentum Scroll
    public func smoothScroll(dy: Int, duration: Double = 0.5, completion: (@Sendable () -> Void)? = nil) {
        let steps = 24
        let stepInterval = duration / Double(steps)
        var stepIndex = 0
        let totalDy = CGFloat(dy)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: stepInterval)

        timer.setEventHandler { [weak self] in
            guard let self = self else {
                timer.cancel()
                return
            }

            if stepIndex >= steps {
                timer.cancel()
                completion?()
                return
            }

            let t = CGFloat(stepIndex) / CGFloat(steps)
            let factor = sin(t * CGFloat.pi) * 1.8
            let stepDelta = Int32((totalDy / CGFloat(steps)) * factor)

            if let scrollEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: stepDelta,
                wheel2: 0,
                wheel3: 0
            ) {
                scrollEvent.location = self.currentPosition
                scrollEvent.post(tap: .cghidEventTap)
            }
            stepIndex += 1
        }
        timer.resume()
    }

    // MARK: - Continuous Session Flow Execution
    public func executeFlow(steps: [CursorFlowStep], completion: (@Sendable () -> Void)? = nil) {
        guard let current = steps.first else {
            completion?()
            return
        }

        let remaining = Array(steps.dropFirst())
        let next: @Sendable () -> Void = { [weak self] in
            self?.executeFlow(steps: remaining, completion: completion)
        }

        switch current {
        case .move(let pt):
            self.move(to: pt, completion: next)
        case .hover(let dur):
            DispatchQueue.global().asyncAfter(deadline: .now() + dur, execute: next)
        case .click(let pt, let preserve):
            self.click(at: pt, injectCGEvent: true, preserveUserMouse: preserve, completion: next)
        case .axClick(let elem):
            let pt = CGPoint(x: elem.frame.midX, y: elem.frame.midY)
            self.move(to: pt) {
                self.click(at: pt, injectCGEvent: false) {
                    _ = AccessibilityEngine.shared.performAXClick(on: elem)
                    next()
                }
            }
        case .scroll(let dy, let dur):
            self.smoothScroll(dy: dy, duration: dur, completion: next)
        }
    }

    private func injectMouseEvent(type: CGEventType, at point: CGPoint, restoreUserMouse: Bool = true) {
        // Record user's actual physical hardware mouse location before injecting
        let userPos = restoreUserMouse ? CGEvent(source: nil)?.location : nil

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }

        event.post(tap: .cghidEventTap)

        // Instantly restore user's physical mouse cursor back to where they were working!
        if let originalPos = userPos {
            CGWarpMouseCursorPosition(originalPos)
        }
    }

    private func cubicEaseInOut(_ t: CGFloat) -> CGFloat {
        if t < 0.5 {
            return 4.0 * t * t * t
        } else {
            let f = ((2.0 * t) - 2.0)
            return 0.5 * f * f * f + 1.0
        }
    }
}
