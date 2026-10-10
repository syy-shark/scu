import Cocoa
import ApplicationServices
import ScreenCaptureKit

extension ComputerUse {

    // MARK: Typing

    /// Type text. Optional target element is focused first (AX focus, or a click).
    /// Order: AX caret insertion (instant, silent) -> per-process key events.
    public func type(app: String, text: String, id: Int?, query: String?, clear: Bool = false, submit: Bool = false) -> ActionResult {
        do {
            let a = try ax.resolveApp(app)
            let pid = a.processIdentifier
            ax.enableAccessibility(for: a)
            let isChromium = AXEngine.isChromiumLike(a)
            let window = BackgroundInput.frontWindow(of: pid)
            if id != nil || query != nil {
                let node = try ax.find(app: a, id: id, query: query)
                let f = reveal(node)
                caption("Focus \(label(node))")
                moveCursor(CGPoint(x: f.midX, y: f.midY), width: min(f.width, f.height))
                _ = ax.focus(node.element)
                // Chromium/Electron requires a background click to focus the internal DOM/Monaco editor
                if isChromium || !node.focused {
                    _ = clickElement(node, app: a, button: .left, count: 1, mode: .background)
                }
                usleep(80_000)
                if clear {
                    if !ax.setValue(node.element, "") {
                        try? BackgroundInput.press("cmd+a", pid: pid, window: window)
                        usleep(25_000)
                        try? BackgroundInput.press("delete", pid: pid, window: window)
                        usleep(25_000)
                    }
                }
            } else if clear {
                try? BackgroundInput.press("cmd+a", pid: pid, window: window)
                usleep(25_000)
                try? BackgroundInput.press("delete", pid: pid, window: window)
                usleep(25_000)
            }
            caption("Typing “\(AXEngine.clip(text, 24))”")
            var method = "ax-insert"
            if isChromium {
                // Chromium/Electron: background key events trigger DOM input/React/Monaco listeners
                method = "key-events"
                BackgroundInput.type(text, pid: pid, window: window)
            } else if text.contains("\n") || !ax.insertAtCaret(pid: pid, text) {
                method = "key-events"
                BackgroundInput.type(text, pid: pid, window: window)
            }
            if submit {
                usleep(50_000)
                try? BackgroundInput.press("return", pid: pid, window: window)
            }
            let actionDesc = submit ? " and submitted" : ""
            return ActionResult(ok: true, text: "Typed \(text.count) chars into \(a.localizedName ?? "app") via \(method)\(actionDesc)")
        } catch { return .fail("\(error)") }
    }

    public func key(app: String, chord: String, repeatCount: Int = 1) -> ActionResult {
        do {
            let a = try ax.resolveApp(app)
            caption("⌨ \(chord)")
            let window = BackgroundInput.frontWindow(of: a.processIdentifier)
            for _ in 0..<max(1, min(repeatCount, 50)) {
                try BackgroundInput.press(chord, pid: a.processIdentifier, window: window)
                usleep(30_000)
            }
            return ActionResult(ok: true, text: "Pressed \(chord)\(repeatCount > 1 ? " ×\(repeatCount)" : "") in \(a.localizedName ?? "app")")
        } catch { return .fail("\(error)") }
    }

    public func setValue(app: String, id: Int?, query: String?, value: String) -> ActionResult {
        do {
            let a = try ax.resolveApp(app)
            let node = try ax.find(app: a, id: id, query: query)
            let f = reveal(node)
            caption("Set \(label(node))")
            moveCursor(CGPoint(x: f.midX, y: f.midY), width: min(f.width, f.height))
            if !AXEngine.isChromiumLike(a) && ax.setValue(node.element, value) {
                return ActionResult(ok: true, text: "Set value of [\(node.index)] \(ax.describe(node.element))")
            }
            return type(app: app, text: value, id: node.index, query: nil, clear: true)
        } catch { return .fail("\(error)") }
    }

    /// Any AX action: AXShowMenu, AXIncrement, AXDecrement, AXConfirm, AXCancel, AXRaise, AXPick…
    public func performAction(app: String, id: Int?, query: String?, action: String) -> ActionResult {
        do {
            let a = try ax.resolveApp(app)
            let node = try ax.find(app: a, id: id, query: query)
            let name = action.hasPrefix("AX") ? action : "AX" + action.prefix(1).uppercased() + action.dropFirst()
            let f = reveal(node)
            caption("\(name.dropFirst(2)) \(label(node))")
            moveCursor(CGPoint(x: f.midX, y: f.midY), width: min(f.width, f.height))
            pressVisual(true); usleep(60_000); pressVisual(false)
            guard ax.perform(name, on: node.element) else {
                return .fail("\(name) failed. Available: \(node.actions.joined(separator: ", "))")
            }
            return ActionResult(ok: true, text: "\(name) on [\(node.index)] \(ax.describe(node.element))")
        } catch { return .fail("\(error)") }
    }

    // MARK: Apps & URLs (launched in the background — never steal focus)

    public func openApp(_ name: String, activate: Bool = false) -> ActionResult {
        let ws = NSWorkspace.shared
        var url: URL?
        if let running = try? ax.resolveApp(name) { url = running.bundleURL }
        if url == nil { url = ws.urlForApplication(withBundleIdentifier: name) }
        if url == nil {
            for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"] {
                let p = URL(fileURLWithPath: dir).appendingPathComponent(name.hasSuffix(".app") ? name : name + ".app")
                if FileManager.default.fileExists(atPath: p.path) { url = p; break }
            }
        }
        guard let appURL = url else { return .fail("application not found: \(name)") }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = activate
        let sem = DispatchSemaphore(value: 0)
        var err: Error?
        ws.openApplication(at: appURL, configuration: cfg) { _, e in err = e; sem.signal() }
        _ = sem.wait(timeout: .now() + 10)
        if let err { return .fail("open failed: \(err.localizedDescription)") }
        usleep(600_000)
        return ActionResult(ok: true, text: "Opened \(appURL.deletingPathExtension().lastPathComponent)\(activate ? "" : " in the background")")
    }

    public func openURL(_ urlString: String, app: String?, activate: Bool = false) -> ActionResult {
        guard let url = URL(string: urlString.contains("://") ? urlString : "https://" + urlString) else { return .fail("bad url") }
        let ws = NSWorkspace.shared
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = activate
        let sem = DispatchSemaphore(value: 0)
        var err: Error?
        if let appName = app {
            var appURL = (try? ax.resolveApp(appName))?.bundleURL
            if appURL == nil, appName.lowercased().contains("chrome") { appURL = ws.urlForApplication(withBundleIdentifier: "com.google.Chrome") }
            guard let au = appURL else { return .fail("app not found: \(appName)") }
            ws.open([url], withApplicationAt: au, configuration: cfg) { _, e in err = e; sem.signal() }
        } else {
            ws.open(url, configuration: cfg) { _, e in err = e; sem.signal() }
        }
        _ = sem.wait(timeout: .now() + 10)
        if let err { return .fail("open failed: \(err.localizedDescription)") }
        usleep(400_000)
        return ActionResult(ok: true, text: "Opened \(url.absoluteString)\(activate ? "" : " in the background")")
    }

    // MARK: Screenshot (window capture works even when the window is covered)

    public func screenshot(app: String?, outPath: String?) -> ActionResult {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            return .fail("Screen Recording permission missing for the host app (System Settings › Privacy & Security › Screen Recording). AX `state` works without it.")
        }
        var image: CGImage?
        var errText = ""
        let sem = DispatchSemaphore(value: 0)
        let wantedPid = app.flatMap { try? ax.resolveApp($0).processIdentifier }
        let myPid = getpid()
        var origin = CGPoint.zero
        Task.detached {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let filter: SCContentFilter
                let cfg = SCStreamConfiguration()
                cfg.showsCursor = false
                if let pid = wantedPid {
                    guard let win = content.windows.filter({ $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 60 })
                        .first else { errText = "no capturable window for app"; sem.signal(); return }
                    filter = SCContentFilter(desktopIndependentWindow: win)
                    cfg.width = Int(win.frame.width); cfg.height = Int(win.frame.height); origin = win.frame.origin
                } else {
                    guard let display = content.displays.first else { errText = "no display"; sem.signal(); return }
                    let mine = content.applications.filter { $0.processID == myPid }
                    filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
                    cfg.width = display.width; cfg.height = display.height; origin = display.frame.origin
                }
                image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            } catch { errText = "\(error.localizedDescription)" }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 10)
        guard let img = image else { return .fail("screenshot failed: \(errText)") }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let png = rep.representation(using: .png, properties: [:]) else { return .fail("png encode failed") }
        let path = outPath ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("cu-shot-\(Int(Date().timeIntervalSince1970)).png")
        try? png.write(to: URL(fileURLWithPath: path))
        var r = ActionResult(ok: true, text: "Screenshot \(img.width)x\(img.height) saved to \(path). Image pixel (px,py) = screen point (\(Int(origin.x))+px, \(Int(origin.y))+py)", data: ["path": path, "origin_x": Double(origin.x), "origin_y": Double(origin.y)])
        r.imagePNG = png
        return r
    }

    // MARK: Diagnostics

    public func doctor() -> ActionResult {
        var lines: [String] = []
        lines.append("Accessibility:      \(ax.isTrusted ? "✅ granted" : "❌ missing")")
        lines.append("Screen Recording:   \(CGPreflightScreenCaptureAccess() ? "✅ granted" : "⚠️ missing (only needed for screenshots)")")
        lines.append("SLEventPostToPid:   \(SkyLight.isAvailable ? "✅" : "❌ (falls back to public postToPid)")")
        lines.append("Focus-without-raise:\(SkyLight.canFocusWithoutRaise ? " ✅" : " ❌")")
        lines.append("AX→window id:       \(SkyLight.axGetWindow != nil ? "✅" : "❌")")
        lines.append("Displays:           \(NSScreen.screens.count)  \(CoordinateSpace.screenRects().map { "\(Int($0.width))x\(Int($0.height))@\(Int($0.minX)),\(Int($0.minY))" }.joined(separator: "  "))")
        return ActionResult(ok: ax.isTrusted, text: lines.joined(separator: "\n"))
    }
}
