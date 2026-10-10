import Cocoa
import ApplicationServices

// MARK: - Accessibility-driven scrolling
//
// Chromium/Electron drop background wheel events, so for them we scroll the
// way assistive tech does: ask the page to reveal the element sitting just past
// the viewport edge (AXScrollToVisible). Done in small increments it reads as
// a smooth animated scroll, and it never touches pointer or focus.

func dbg(_ s: @autoclosure () -> String) {
    if ProcessInfo.processInfo.environment["SCU_DEBUG"] != nil || FileManager.default.fileExists(atPath: "/tmp/scu-debug") {
        FileHandle.standardError.write((s() + "\n").data(using: .utf8)!)
    }
}

extension AXEngine {

    /// Nearest scroll container (web area / scroll area) at a point of an app.
    func scrollContainer(pid: pid_t, at point: CGPoint) -> AXUIElement? {
        guard var cur = element(at: point, pid: pid) else { return nil }
        for _ in 0..<40 {
            let role = AXEngine.string(AXEngine.attr(cur, kAXRoleAttribute))
            if role == "AXWebArea" || role == "AXScrollArea" { return cur }
            guard let p = parent(of: cur) else { return nil }
            cur = p
        }
        return nil
    }

    private func descendants(of root: AXUIElement, limit: Int = 4000) -> [(AXUIElement, CGRect)] {
        var out: [(AXUIElement, CGRect)] = []
        var queue: [AXUIElement] = [root]
        var i = 0
        while i < queue.count && out.count < limit {
            let e = queue[i]; i += 1
            if let kids = AXEngine.attr(e, kAXChildrenAttribute) as? [AXUIElement] {
                for k in kids {
                    let f = AXEngine.frame(of: k)
                    if f.width >= 2 && f.height >= 2 { out.append((k, f)) }
                    queue.append(k)
                }
            }
        }
        return out
    }

    /// Scroll the container under `point` by roughly `dy` points (dy < 0 = reveal content below).
    /// Returns the distance actually scrolled (positive = content moved up), or nil if it could not scroll.
    func revealScroll(pid: pid_t, at point: CGPoint, dy: Int, window: CGRect) -> CGFloat? {
        guard dy != 0, let container = scrollContainer(pid: pid, at: point) else { dbg("revealScroll: no container at \(point)"); return nil }
        var viewport = AXEngine.frame(of: container).intersection(window)
        dbg("revealScroll: container=\(AXEngine.string(AXEngine.attr(container, kAXRoleAttribute))) frame=\(AXEngine.frame(of: container)) viewport=\(viewport)")
        if viewport.isNull || viewport.height < 20 { viewport = window }
        let wantDown = dy < 0
        let step = CGFloat(min(abs(dy), 160))
        var remaining = CGFloat(abs(dy))
        var moved: CGFloat = 0
        var all = descendants(of: container)
        var stalls = 0
        while remaining > 4 {
            let delta = min(step, remaining)
            // Element whose edge sits `delta` past the viewport edge.
            let pick: (AXUIElement, CGRect)?
            if wantDown {
                let goal = viewport.maxY + delta
                pick = all.filter { $0.1.maxY > viewport.maxY + 2 && $0.1.height < viewport.height * 0.7 }
                    .min { abs($0.1.maxY - goal) < abs($1.1.maxY - goal) }
            } else {
                let goal = viewport.minY - delta
                pick = all.filter { $0.1.minY < viewport.minY - 2 && $0.1.height < viewport.height * 0.7 }
                    .min { abs($0.1.minY - goal) < abs($1.1.minY - goal) }
            }
            guard let (el, before) = pick else { dbg("revealScroll: no candidate (n=\(all.count))"); break }
            _ = perform("AXScrollToVisible", on: el)
            usleep(16_000)
            let after = AXEngine.frame(of: el)
            let shift = before.minY - after.minY      // >0: content moved up (scrolled down)
            dbg("revealScroll: pick \(before) -> \(after) shift=\(shift)")
            if abs(shift) < 1 {
                stalls += 1
                all.removeAll { CFEqual($0.0, el) }
                if stalls > 3 { break }
                continue
            }
            stalls = 0
            moved += shift
            remaining -= abs(shift)
            // Re-base cached frames by the measured shift instead of re-reading the tree.
            all = all.map { ($0.0, $0.1.offsetBy(dx: 0, dy: -shift)) }
            usleep(12_000)
        }
        return abs(moved) >= 1 ? moved : nil
    }

    /// Vertical scroll position (0…1) of a native scroll area, if exposed.
    func scrollBarValue(container: AXUIElement) -> Double? {
        guard let bar = AXEngine.attr(container, kAXVerticalScrollBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        return (AXEngine.attr(bar as! AXUIElement, kAXValueAttribute) as? NSNumber)?.doubleValue
    }
}
