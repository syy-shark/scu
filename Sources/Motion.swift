import Foundation
import CoreGraphics

// MARK: - Motion model
//
// Codex's ComputerUseCursor exposes `MotionConfiguration`, `CursorMotionPath`,
// `CursorMotionPathMeasurement` and `CloseEnoughConfiguration`. Same idea here:
// an arc-length-parameterised curved path driven by a minimum-jerk speed
// profile (the profile human reaching movements follow), with Fitts'-law
// durations so short hops are snappy and long sweeps stay calm.

public enum Motion {
    /// Minimum-jerk position profile: zero velocity AND zero acceleration at both ends.
    @inline(__always)
    public static func minimumJerk(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * x * (10 + x * (-15 + 6 * x))
    }

    @inline(__always)
    public static func easeOutCubic(_ t: Double) -> Double {
        let x = 1 - min(max(t, 0), 1)
        return 1 - x * x * x
    }

    /// Fitts'-law flavoured duration (seconds) for a move of `distance` points
    /// towards a target `width` points wide. Snappy & fluid.
    public static func duration(distance: CGFloat, targetWidth: CGFloat = 28, speed: Double = 1.0) -> Double {
        guard distance > 0.5 else { return 0 }
        let id = log2(1 + Double(distance) / Double(max(targetWidth, 8)))
        let t = 0.08 + 0.035 * id
        return min(max(t / max(speed, 0.1), 0.06), 0.32)
    }
}

/// Cubic Bezier with an arc-length lookup table, so the time-warp is applied to
/// *distance travelled* and the speed profile is exactly minimum-jerk.
public struct CursorMotionPath {
    public let p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint
    private var lut: [Double] = []
    public private(set) var length: Double = 0
    private static let samples = 96

    public init(from start: CGPoint, to end: CGPoint) {
        p0 = start
        p3 = end
        let dx = end.x - start.x, dy = end.y - start.y
        let d = max(hypot(dx, dy), 0.0001)
        let ux = dx / d, uy = dy / d
        // A wrist pivots, so real pointer paths bow gently to one side.
        // Bow ∝ distance (capped), always to the same side relative to the
        // direction of travel -> consistent, calm, non-random arcs.
        let bow = min(d * 0.10, 70)
        let side: CGFloat = dx >= 0 ? -1 : 1
        let px = -uy * bow * side, py = ux * bow * side
        p1 = CGPoint(x: start.x + dx * 0.30 + px, y: start.y + dy * 0.30 + py)
        p2 = CGPoint(x: start.x + dx * 0.78 + px * 0.45, y: start.y + dy * 0.78 + py * 0.45)
        buildLUT()
    }

    private mutating func buildLUT() {
        lut = [0]
        lut.reserveCapacity(Self.samples + 1)
        var prev = p0
        var acc = 0.0
        for i in 1...Self.samples {
            let pt = point(t: Double(i) / Double(Self.samples))
            acc += Double(hypot(pt.x - prev.x, pt.y - prev.y))
            lut.append(acc)
            prev = pt
        }
        length = acc
    }

    public func point(t: Double) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, e = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + e * p3.x,
                       y: a * p0.y + b * p1.y + c * p2.y + e * p3.y)
    }

    /// Point at a fraction (0…1) of the total arc length.
    public func point(atDistanceFraction f: Double) -> CGPoint {
        if f <= 0 { return p0 }
        if f >= 1 { return p3 }
        let target = f * length
        var lo = 0, hi = lut.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if lut[mid] < target { lo = mid + 1 } else { hi = mid }
        }
        let i = max(lo, 1)
        let seg = lut[i] - lut[i - 1]
        let local = seg > 0 ? (target - lut[i - 1]) / seg : 0
        let t = (Double(i - 1) + local) / Double(Self.samples)
        return point(t: t)
    }
}

/// Critically-damped-ish spring used for tilt / press / lift so every visual
/// state change eases in and settles without popping.
public struct Spring {
    public var value: Double
    public var velocity: Double = 0
    public var target: Double
    public var stiffness: Double
    public var damping: Double

    public init(_ v: Double, stiffness: Double = 420, dampingRatio: Double = 0.86) {
        value = v
        target = v
        self.stiffness = stiffness
        damping = 2 * sqrt(stiffness) * dampingRatio
    }

    public mutating func step(_ dt: Double) {
        var remaining = min(dt, 1.0 / 20)
        while remaining > 0 {
            let h = min(remaining, 1.0 / 240)
            let force = -stiffness * (value - target) - damping * velocity
            velocity += force * h
            value += velocity * h
            remaining -= h
        }
    }

    public var isSettled: Bool { abs(value - target) < 0.0005 && abs(velocity) < 0.005 }
}
