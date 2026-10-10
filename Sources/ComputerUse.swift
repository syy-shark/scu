import Cocoa
import ApplicationServices

// MARK: - High-level Computer Use actions
//
// Delivery ladder for every click (most precise & least intrusive first):
//   1. "ax"         AXPress on the element itself     -> exact, zero pointer/focus impact
//   2. "background" pixel click to the window's process at a hit-test
//                   verified point                    -> exact, pointer/focus untouched
//   3. "foreground" classic HID click, pointer restored -> only when explicitly requested
// The overlay cursor performs the visible motion, so the user sees what the
// agent does while keeping full control of their own mouse and keyboard.

public struct ActionResult {
    public var ok: Bool
    public var text: String
    public var data: [String: Any] = [:]
    public var imagePNG: Data? = nil

    public static func fail(_ msg: String) -> ActionResult { ActionResult(ok: false, text: msg) }
}

public enum ClickMode: String { case auto, ax, background, foreground }

public final class ComputerUse {
    public static let shared = ComputerUse()
    let ax = AXEngine.shared
    let overlay = CursorOverlay.shared
    public var showCursor = true

    // MARK: Overlay helpers

    func caption(_ s: String?) {
        guard showCursor else { return }
        DispatchQueue.main.async { self.overlay.setCaption(s) }
    }

    func moveCursor(_ p: CGPoint, width: CGFloat = 28) {
        guard showCursor else { return }
        overlay.glideAndWait(to: p, targetWidth: width)
    }

    func pressVisual(_ down: Bool) {
        guard showCursor else { return }
        DispatchQueue.main.async { down ? self.overlay.pressDown() : self.overlay.pressUp() }
    }

    public func finishTurn() {
        guard showCursor else { return }
        DispatchQueue.main.async {
            self.overlay.setCaption(nil)
            self.overlay.scheduleAutoHide()
        }
    }

    // MARK: Window resolution

    func windowTarget(for element: AXUIElement, pid: pid_t) -> WindowTarget? {
        if let w = AXEngine.attr(element, kAXWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() {
            let win = w as! AXUIElement
            if let wid = SkyLight.windowID(of: win) {
                return WindowTarget(pid: pid, windowID: wid, bounds: AXEngine.frame(of: win), ownerName: "")
            }
        }
        return BackgroundInput.frontWindow(of: pid)
    }

    func windowTarget(at p: CGPoint, preferPid: pid_t?) -> WindowTarget? {
        if let w = BackgroundInput.window(at: p), preferPid == nil || w.pid == preferPid { return w }
        if let pid = preferPid { return BackgroundInput.frontWindow(of: pid, containing: p) ?? BackgroundInput.frontWindow(of: pid) }
        return nil
    }

    func label(_ n: UIElementNode) -> String {
        n.label.isEmpty ? n.role.replacingOccurrences(of: "AX", with: "") : "“\(AXEngine.clip(n.label, 30))”"
    }

    // MARK: Apps / state

    public func listApps() -> ActionResult {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let lines = ax.runningApps().map { a -> String in
            "\(a.processIdentifier == front ? "*" : " ") \(a.localizedName ?? "?")  [\(a.bundleIdentifier ?? "-")] pid=\(a.processIdentifier)\(a.isHidden ? " hidden" : "")"
        }
        return ActionResult(ok: true, text: "Running apps (* = frontmost):\n" + lines.joined(separator: "\n"))
    }

    public func state(app: String, window: String? = nil, interactiveOnly: Bool? = nil, maxLines: Int? = nil) -> ActionResult {
        do {
            let a = try ax.resolveApp(app)
            let isChrom = AXEngine.isChromiumLike(a)
            let compact = interactiveOnly ?? (isChrom ? true : false)
            let limit = maxLines ?? (isChrom ? 300 : 1200)
            let snap = try ax.snapshot(app: a, windowTitle: window, maxNodes: limit, interactiveOnly: compact)
            return ActionResult(ok: true, text: snap.text(maxLines: limit), data: ["count": snap.nodes.count, "window": snap.windowTitle])
        } catch {
            return .fail("\(error)")
        }
    }
}
