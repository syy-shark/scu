import Foundation

// MARK: - Command router (shared by CLI daemon and MCP server)

public enum Router {
    static let queue = DispatchQueue(label: "smooth-cu.actions", qos: .userInitiated)

    static func str(_ a: [String: Any], _ k: String) -> String? {
        if let s = a[k] as? String, !s.isEmpty { return s }
        if let n = a[k] as? NSNumber { return n.stringValue }
        return nil
    }
    static func int(_ a: [String: Any], _ k: String) -> Int? {
        if let n = a[k] as? NSNumber { return n.intValue }
        if let s = a[k] as? String { return Int(s) }
        return nil
    }
    static func dbl(_ a: [String: Any], _ k: String) -> Double? {
        if let n = a[k] as? NSNumber { return n.doubleValue }
        if let s = a[k] as? String { return Double(s) }
        return nil
    }
    static func bool(_ a: [String: Any], _ k: String) -> Bool {
        if let b = a[k] as? Bool { return b }
        if let s = a[k] as? String { return ["1", "true", "yes"].contains(s.lowercased()) }
        return false
    }

    /// Execute synchronously on the serial action queue (never on main), with a 10s timeout.
    public static func run(_ cmd: String, _ a: [String: Any], timeout: TimeInterval = 10.0) -> ActionResult {
        var result: ActionResult?
        let sem = DispatchSemaphore(value: 0)
        let item = DispatchWorkItem {
            result = dispatch(cmd, a)
            sem.signal()
        }
        queue.async(execute: item)
        let waitResult = sem.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            item.cancel()
            return .fail("command '\(cmd)' timed out after \(Int(timeout))s")
        }
        return result ?? .fail("no result")
    }

    static func dispatch(_ cmd: String, _ a: [String: Any]) -> ActionResult {
        let cu = ComputerUse.shared
        let app = str(a, "app")
        let id = int(a, "id") ?? int(a, "element_index")
        let query = str(a, "title") ?? str(a, "query") ?? str(a, "element")
        defer { if !["apps", "list_apps", "state", "get_app_state", "doctor", "screenshot", "ping"].contains(cmd) { cu.finishTurn() } }

        switch cmd {
        case "ping": return ActionResult(ok: true, text: "pong")
        case "apps", "list_apps": return cu.listApps()
        case "doctor": return cu.doctor()
        case "state", "get_app_state":
            guard let app else { return .fail("app is required") }
            let interactive = a["interactive"] != nil ? bool(a, "interactive") : nil
            let maxNodes = int(a, "max_nodes") ?? int(a, "max_lines")
            return cu.state(app: app, window: str(a, "window"), interactiveOnly: interactive, maxLines: maxNodes)
        case "click", "right_click", "double_click":
            let button: MouseButtonKind = cmd == "right_click" || str(a, "button") == "right" ? .right : (str(a, "button") == "middle" ? .middle : .left)
            let count = cmd == "double_click" ? 2 : (int(a, "count") ?? 1)
            let mode = ClickMode(rawValue: str(a, "mode") ?? "auto") ?? .auto
            return cu.click(app: app, id: id, query: query, role: str(a, "role"), x: dbl(a, "x"), y: dbl(a, "y"),
                            button: button, count: count, mode: mode)
        case "move", "move_cursor":
            guard let x = dbl(a, "x"), let y = dbl(a, "y") else { return .fail("x and y required") }
            return cu.move(x: x, y: y, app: app)
        case "hover":
            guard let app else { return .fail("app is required") }
            return cu.hover(app: app, id: id, query: query)
        case "scroll":
            var dy = int(a, "dy") ?? 0, dx = int(a, "dx") ?? 0
            if let dir = str(a, "direction") {
                let amount = int(a, "amount") ?? 400
                switch dir { case "down": dy = -amount; case "up": dy = amount; case "left": dx = amount; case "right": dx = -amount; default: break }
            }
            if dx == 0 && dy == 0 { dy = -400 }
            return cu.scroll(app: app, id: id, query: query, x: dbl(a, "x"), y: dbl(a, "y"), dx: dx, dy: dy)
        case "drag":
            guard let x1 = dbl(a, "x1") ?? dbl(a, "from_x"), let y1 = dbl(a, "y1") ?? dbl(a, "from_y"),
                  let x2 = dbl(a, "x2") ?? dbl(a, "to_x"), let y2 = dbl(a, "y2") ?? dbl(a, "to_y") else { return .fail("x1 y1 x2 y2 required") }
            return cu.drag(app: app, x1: x1, y1: y1, x2: x2, y2: y2)
        case "type", "type_text":
            guard let app, let text = str(a, "text") else { return .fail("app and text required") }
            let submit = bool(a, "submit") || bool(a, "press_enter") || bool(a, "enter")
            return cu.type(app: app, text: text, id: id, query: query, clear: bool(a, "clear"), submit: submit)
        case "key", "press_key":
            guard let app, let k = str(a, "key") ?? str(a, "keys") else { return .fail("app and key required") }
            return cu.key(app: app, chord: k, repeatCount: int(a, "repeat") ?? 1)
        case "set_value", "set-value":
            guard let app, let v = str(a, "value") else { return .fail("app and value required") }
            return cu.setValue(app: app, id: id, query: query, value: v)
        case "action", "perform_secondary_action":
            guard let app, let act = str(a, "action") else { return .fail("app and action required") }
            return cu.performAction(app: app, id: id, query: query, action: act)
        case "open_app", "open-app":
            guard let name = str(a, "name") ?? app else { return .fail("name required") }
            return cu.openApp(name, activate: bool(a, "activate"))
        case "open_url", "open-url":
            guard let url = str(a, "url") else { return .fail("url required") }
            return cu.openURL(url, app: app, activate: bool(a, "activate"))
        case "screenshot":
            return cu.screenshot(app: app, outPath: str(a, "out"))
        case "pulse":
            cu.pressVisual(true); usleep(90_000); cu.pressVisual(false)
            return ActionResult(ok: true, text: "pulse")
        case "wait":
            usleep(useconds_t(min(dbl(a, "seconds") ?? 1, 30) * 1_000_000))
            return ActionResult(ok: true, text: "waited")
        default:
            return .fail("unknown command: \(cmd)")
        }
    }
}
