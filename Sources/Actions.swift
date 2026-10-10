import Cocoa
import ApplicationServices

extension ComputerUse {

    // MARK: Click

    public func click(app: String?, id: Int?, query: String?, role: String?, x: Double?, y: Double?,
                      button: MouseButtonKind = .left, count: Int = 1, mode: ClickMode = .auto) -> ActionResult {
        do {
            if id != nil || query != nil {
                guard let appName = app else { return .fail("--app is required when clicking by id/title") }
                let a = try ax.resolveApp(appName)
                let node = try ax.find(app: a, id: id, query: query, role: role)
                return clickElement(node, app: a, button: button, count: count, mode: mode)
            }
            guard let x, let y else { return .fail("give x y, or --app with --id / --title") }
            let preferPid = try app.map { try ax.resolveApp($0).processIdentifier }
            return clickPoint(CGPoint(x: x, y: y), preferPid: preferPid, button: button, count: count, mode: mode)
        } catch {
            return .fail("\(error)")
        }
    }

    /// Bring an element into view and return its fresh frame.
    func reveal(_ node: UIElementNode) -> CGRect {
        var frame = ax.liveFrame(node.element)
        if frame.width < 1 { frame = node.frame }
        let win = windowTarget(for: node.element, pid: ax.pid(of: node.element))?.bounds ?? .zero
        let visible = win.width > 0 ? win.insetBy(dx: 0, dy: 4) : frame
        if !visible.contains(CGPoint(x: frame.midX, y: frame.midY)) {
            if ax.scrollToVisible(node.element) {
                usleep(220_000)
                let f2 = ax.liveFrame(node.element)
                if f2.width >= 1 { frame = f2 }
            }
        }
        return frame
    }

    func clickElement(_ node: UIElementNode, app: NSRunningApplication, button: MouseButtonKind, count: Int, mode: ClickMode) -> ActionResult {
        let pid = app.processIdentifier
        let frame = reveal(node)
        let point = ax.verifiedPoint(for: node.element, frame: frame) ?? CGPoint(x: frame.midX, y: frame.midY)
        let verb = button == .right ? "Right-click" : (count > 1 ? "Double-click" : "Click")
        caption("\(verb) \(label(node))")
        moveCursor(point, width: max(8, min(frame.width, frame.height)))
        pressVisual(true)
        defer { usleep(70_000); pressVisual(false) }

        let titleBefore = ax.windowTitle(pid: pid)
        var method = ""
        let canAX = button == .left && count == 1 && node.actions.contains("AXPress") && node.enabled
        if (mode == .auto || mode == .ax) && canAX && ax.perform("AXPress", on: node.element) {
            method = "ax-press"
        } else if mode == .ax {
            return .fail("element has no AXPress; retry with mode=background")
        } else if mode == .foreground {
            BackgroundInput.foregroundClick(at: point, button: button, count: count)
            method = "foreground"
        } else if let target = windowTarget(for: node.element, pid: pid) {
            BackgroundInput.click(at: point, target: target, button: button, count: count)
            method = "background-pixel"
        } else {
            return .fail("no window found for element")
        }
        usleep(120_000)
        let titleAfter = ax.windowTitle(pid: pid)
        var text = "\(verb)ed [\(node.index)] \(ax.describe(node.element)) at (\(Int(point.x)),\(Int(point.y))) via \(method)"
        if titleAfter != titleBefore && !titleAfter.isEmpty { text += "\nwindow title is now: \(titleAfter)" }
        return ActionResult(ok: true, text: text, data: ["method": method, "x": point.x, "y": point.y])
    }

    func clickPoint(_ p: CGPoint, preferPid: pid_t?, button: MouseButtonKind, count: Int, mode: ClickMode) -> ActionResult {
        guard let target = windowTarget(at: p, preferPid: preferPid) else { return .fail("no window under (\(Int(p.x)),\(Int(p.y)))") }
        let hit = ax.element(at: p, pid: target.pid)
        let hitDesc = hit.map { ax.describe($0) } ?? "?"
        caption("\(button == .right ? "Right-click" : "Click") \(AXEngine.clip(hitDesc, 28))")
        moveCursor(p)
        pressVisual(true)
        defer { usleep(70_000); pressVisual(false) }

        var method = "background-pixel"
        if mode == .foreground {
            BackgroundInput.foregroundClick(at: p, button: button, count: count)
            method = "foreground"
        } else {
            // A precise pressable control under the point -> semantic press (exact & silent).
            var pressed = false
            if (mode == .auto || mode == .ax), button == .left, count == 1, let h = hit,
               let pressable = ax.pressableAncestor(of: h) {
                let f = AXEngine.frame(of: pressable)
                let role = AXEngine.string(AXEngine.attr(pressable, kAXRoleAttribute))
                let small = f.width * f.height < target.bounds.width * target.bounds.height * 0.2
                if f.contains(p) && small && AXEngine.pressableRoles.contains(role) && ax.perform("AXPress", on: pressable) {
                    pressed = true
                    method = "ax-press"
                }
            }
            if !pressed {
                if mode == .ax { return .fail("nothing pressable at point; retry with mode=background") }
                BackgroundInput.click(at: p, target: target, button: button, count: count)
            }
        }
        usleep(100_000)
        return ActionResult(ok: true, text: "Clicked (\(Int(p.x)),\(Int(p.y))) on \(hitDesc) [\(target.ownerName)] via \(method)",
                            data: ["method": method])
    }

    // MARK: Move / hover

    public func move(x: Double, y: Double, app: String?) -> ActionResult {
        let p = CGPoint(x: x, y: y)
        moveCursor(p)
        let preferPid = app.flatMap { try? ax.resolveApp($0).processIdentifier }
        if let t = windowTarget(at: p, preferPid: preferPid) { BackgroundInput.hover(at: p, target: t) }
        return ActionResult(ok: true, text: "Cursor at (\(Int(x)),\(Int(y)))")
    }

    public func hover(app: String, id: Int?, query: String?) -> ActionResult {
        do {
            let a = try ax.resolveApp(app)
            let node = try ax.find(app: a, id: id, query: query)
            let f = reveal(node)
            let p = CGPoint(x: f.midX, y: f.midY)
            caption("Hover \(label(node))")
            moveCursor(p, width: min(f.width, f.height))
            if let t = windowTarget(for: node.element, pid: a.processIdentifier) { BackgroundInput.hover(at: p, target: t) }
            return ActionResult(ok: true, text: "Hovering [\(node.index)] \(ax.describe(node.element))")
        } catch { return .fail("\(error)") }
    }

    // MARK: Scroll

    public func scroll(app: String?, id: Int?, query: String?, x: Double?, y: Double?, dx: Int, dy: Int) -> ActionResult {
        do {
            var point: CGPoint
            var target: WindowTarget?
            if id != nil || query != nil, let appName = app {
                let a = try ax.resolveApp(appName)
                let node = try ax.find(app: a, id: id, query: query)
                let f = ax.liveFrame(node.element)
                point = CGPoint(x: f.midX, y: f.midY)
                target = windowTarget(for: node.element, pid: a.processIdentifier)
            } else if let x, let y {
                point = CGPoint(x: x, y: y)
                target = windowTarget(at: point, preferPid: try app.map { try ax.resolveApp($0).processIdentifier })
            } else if let appName = app {
                let a = try ax.resolveApp(appName)
                ax.enableAccessibility(for: a)
                let win = try ax.mainWindow(of: a)
                let f = AXEngine.frame(of: win)
                point = CGPoint(x: f.midX, y: f.minY + f.height * 0.6)
                target = windowTarget(for: win, pid: a.processIdentifier)
            } else {
                return .fail("scroll needs --app, an element, or x y")
            }
            guard let t = target else { return .fail("no window to scroll") }
            if let vis = Optional(t.bounds), vis.width > 0, !vis.contains(point) {
                point = CGPoint(x: min(max(point.x, vis.minX + 20), vis.maxX - 20), y: min(max(point.y, vis.minY + 60), vis.maxY - 20))
            }
            caption(dy < 0 ? "Scroll ↓" : (dy > 0 ? "Scroll ↑" : "Scroll"))
            moveCursor(point)
            let duration = min(0.9, 0.28 + Double(abs(dy) + abs(dx)) / 2000)
            let where_ = t.ownerName.isEmpty ? "window \(t.windowID)" : t.ownerName
            let runApp = NSRunningApplication(processIdentifier: t.pid)
            let chromium = runApp.map { AXEngine.isChromiumLike($0) } ?? false
            if let a = runApp { ax.enableAccessibility(for: a) }

            // Chromium/Electron: background wheel events are dropped -> background arrow keys
            // (Chrome animates them smoothly), unless a text field has focus; AX reveal as fallback.
            if chromium && (dy != 0 || dx != 0) {
                let appEl = AXUIElementCreateApplication(t.pid)
                var editable = false
                if let f = AXEngine.attr(appEl, kAXFocusedUIElementAttribute), CFGetTypeID(f) == AXUIElementGetTypeID() {
                    let role = AXEngine.string(AXEngine.attr(f as! AXUIElement, kAXRoleAttribute))
                    editable = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role)
                }
                if !editable {
                    let steps = { (v: Int) in min(60, max(1, Int((Double(abs(v)) / 40).rounded()))) }
                    BackgroundInput.withSyntheticFocus(t) {
                        if dy != 0 { for _ in 0..<steps(dy) { BackgroundInput.key(dy < 0 ? 125 : 126, down: true, flags: [], pid: t.pid); usleep(8_000)
                            BackgroundInput.key(dy < 0 ? 125 : 126, down: false, flags: [], pid: t.pid); usleep(28_000) } }
                        if dx != 0 { for _ in 0..<steps(dx) { BackgroundInput.key(dx < 0 ? 124 : 123, down: true, flags: [], pid: t.pid); usleep(8_000)
                            BackgroundInput.key(dx < 0 ? 124 : 123, down: false, flags: [], pid: t.pid); usleep(28_000) } }
                    }
                    usleep(200_000)
                    return ActionResult(ok: true, text: "Scrolled dy=\(dy) dx=\(dx) via background keys in \(where_)")
                }
                if dy != 0, let moved = ax.revealScroll(pid: t.pid, at: point, dy: dy, window: t.bounds) {
                    return ActionResult(ok: true, text: "Scrolled \(Int(moved))pt via AX in \(where_)")
                }
            }
            // Native: wheel first, verify via scroll bar, fall back to AX.
            let container = ax.scrollContainer(pid: t.pid, at: point)
            let before = container.flatMap { ax.scrollBarValue(container: $0) }
            BackgroundInput.scroll(at: point, target: t, dx: dx, dy: dy, duration: duration)
            usleep(150_000)
            let after = container.flatMap { ax.scrollBarValue(container: $0) }
            if dy != 0, let b = before, let a = after, abs(a - b) < 0.0001, !chromium {
                if let moved = ax.revealScroll(pid: t.pid, at: point, dy: dy, window: t.bounds) {
                    return ActionResult(ok: true, text: "Scrolled \(Int(moved))pt via AX (wheel ignored) in \(where_)")
                }
            }
            return ActionResult(ok: true, text: "Scrolled dy=\(dy) dx=\(dx) at (\(Int(point.x)),\(Int(point.y))) in \(where_)")
        } catch { return .fail("\(error)") }
    }

    // MARK: Drag

    public func drag(app: String?, x1: Double, y1: Double, x2: Double, y2: Double) -> ActionResult {
        let a = CGPoint(x: x1, y: y1), b = CGPoint(x: x2, y: y2)
        let preferPid = app.flatMap { try? ax.resolveApp($0).processIdentifier }
        guard let t = windowTarget(at: a, preferPid: preferPid) else { return .fail("no window at drag start") }
        caption("Drag")
        moveCursor(a)
        pressVisual(true)
        if showCursor {
            DispatchQueue.main.async { self.overlay.glide(to: b, targetWidth: 40) }
        }
        BackgroundInput.drag(from: a, to: b, target: t, duration: Motion.duration(distance: hypot(b.x - a.x, b.y - a.y), targetWidth: 40))
        pressVisual(false)
        return ActionResult(ok: true, text: "Dragged (\(Int(x1)),\(Int(y1))) → (\(Int(x2)),\(Int(y2)))")
    }
}
