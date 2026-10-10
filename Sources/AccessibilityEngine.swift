import Cocoa
import ApplicationServices
import CoreGraphics

// MARK: - UI element snapshot (Codex: TransformedUIElement / get_app_state)

public struct UIElementNode {
    public let index: Int
    public let depth: Int
    public let role: String
    public let subrole: String
    public let label: String          // title / description / help, whichever is meaningful
    public let value: String
    public let url: String
    public let frame: CGRect
    public let actions: [String]
    public let enabled: Bool
    public let focused: Bool
    public let onScreen: Bool
    public let element: AXUIElement

    public var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    public var isPressable: Bool {
        actions.contains("AXPress") || AXEngine.pressableRoles.contains(role)
    }

    public var summary: String {
        var s = "[\(index)] \(role.replacingOccurrences(of: "AX", with: ""))"
        if !subrole.isEmpty && subrole != "AXUnknown" { s += "(\(subrole.replacingOccurrences(of: "AX", with: "")))" }
        if !label.isEmpty { s += " \"\(AXEngine.clip(label, 80))\"" }
        if !value.isEmpty && value != label { s += " value=\"\(AXEngine.clip(value, 60))\"" }
        if !url.isEmpty { s += " url=\(AXEngine.clip(url, 70))" }
        if frame.width > 0 {
            s += " @(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))"
        }
        let acts = actions.filter { $0 != "AXScrollToVisible" && $0 != "AXShowDefaultUI" && $0 != "AXShowAlternateUI" }
            .map { $0.replacingOccurrences(of: "AX", with: "").lowercased() }
        if !acts.isEmpty { s += " {\(acts.joined(separator: ","))}" }
        if !enabled { s += " disabled" }
        if focused { s += " focused" }
        if !onScreen { s += " offscreen" }
        return s
    }
}

public struct AppSnapshot {
    public let appName: String
    public let pid: pid_t
    public let windowTitle: String
    public let windowFrame: CGRect
    public let nodes: [UIElementNode]
    public let truncated: Bool

    public func text(maxLines: Int = 1200) -> String {
        var lines = ["App: \(appName) (pid \(pid))",
                     "Window: \"\(windowTitle)\" @(\(Int(windowFrame.minX)),\(Int(windowFrame.minY)) \(Int(windowFrame.width))x\(Int(windowFrame.height)))",
                     "Elements: \(nodes.count)\(truncated ? " (truncated at \(nodes.count) elements, use interactive/window filter)" : "")  — reference with id=<n>"]
        for n in nodes.prefix(maxLines) {
            lines.append(String(repeating: "  ", count: min(n.depth, 24)) + n.summary)
        }
        if nodes.count > maxLines { lines.append("… \(nodes.count - maxLines) more") }
        return lines.joined(separator: "\n")
    }
}

public enum AXEngineError: Error, CustomStringConvertible {
    case appNotFound(String), noWindow(String), elementNotFound(String), notTrusted
    public var description: String {
        switch self {
        case .appNotFound(let a): return "app not found: \(a)"
        case .noWindow(let a): return "no accessible window for \(a) (is it on this Space / minimized?)"
        case .elementNotFound(let q): return "element not found: \(q) — refresh with `state` and retry"
        case .notTrusted: return "Accessibility permission missing (System Settings › Privacy & Security › Accessibility)"
        }
    }
}

// MARK: - Engine

public final class AXEngine {
    public static let shared = AXEngine()

    static let pressableRoles: Set<String> = [
        "AXButton", "AXLink", "AXMenuItem", "AXMenuBarItem", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
        "AXMenuButton", "AXTab", "AXDisclosureTriangle", "AXCell", "AXRow", "AXSwitch", "AXToolbarButton",
        "AXDockItem", "AXImage",
    ]
    static let interactableRoles: Set<String> = pressableRoles.union([
        "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXSlider", "AXIncrementor", "AXStepper",
        "AXSegmentedControl", "AXColorWell", "AXDateField", "AXScrollBar", "AXTabGroup", "AXOutline", "AXTable",
        "AXList", "AXWebArea", "AXHeading", "AXStaticText", "AXGroup",
    ])
    static let containerOnlyRoles: Set<String> = ["AXGroup", "AXSplitGroup", "AXScrollArea", "AXLayoutArea", "AXGenericElement", "AXUnknown", "AXSection", "AXLandmarkMain", "AXLandmarkNavigation"]

    private var enabledPids = Set<pid_t>()
    private var lastSnapshots: [pid_t: AppSnapshot] = [:]
    private let lock = NSLock()

    public var isTrusted: Bool { AXIsProcessTrusted() }

    public func requestTrust() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    // MARK: Apps

    public func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated }
    }

    public func resolveApp(_ query: String) throws -> NSRunningApplication {
        if let pid = pid_t(query), let app = NSRunningApplication(processIdentifier: pid) { return app }
        let apps = runningApps()
        let q = query.lowercased()
        if let a = apps.first(where: { $0.localizedName?.lowercased() == q || $0.bundleIdentifier?.lowercased() == q }) { return a }
        let aliases: [String: String] = ["chrome": "com.google.Chrome", "safari": "com.apple.Safari", "calculator": "com.apple.calculator",
                                         "计算器": "com.apple.calculator", "finder": "com.apple.finder", "wechat": "com.tencent.xinWeChat",
                                         "微信": "com.tencent.xinWeChat", "notes": "com.apple.Notes", "备忘录": "com.apple.Notes"]
        if let bid = aliases[q], let a = apps.first(where: { $0.bundleIdentifier == bid }) { return a }
        if let a = apps.first(where: { ($0.localizedName?.lowercased().contains(q) ?? false) || ($0.bundleIdentifier?.lowercased().contains(q) ?? false) }) { return a }
        throw AXEngineError.appNotFound(query)
    }

    static func isChromiumLike(_ app: NSRunningApplication) -> Bool {
        let bid = app.bundleIdentifier ?? ""
        if ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
            "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.google.Chrome.canary"].contains(bid) { return true }
        if let url = app.bundleURL {
            let electron = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
            if FileManager.default.fileExists(atPath: electron.path) { return true }
        }
        return false
    }

    /// Chromium / Electron only build their accessibility tree when asked.
    /// Codex flips `AXManualAccessibility` (falls back to AXEnhancedUserInterface).
    public func enableAccessibility(for app: NSRunningApplication) {
        let pid = app.processIdentifier
        lock.lock(); let done = enabledPids.contains(pid); lock.unlock()
        if done { return }
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.3)
        let r = AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if r != .success && AXEngine.isChromiumLike(app) {
            AXUIElementSetAttributeValue(el, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        lock.lock(); enabledPids.insert(pid); lock.unlock()
        if AXEngine.isChromiumLike(app) { usleep(350_000) }  // let the renderer build its tree once
    }

    // MARK: Attribute helpers

    static func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }

    static func string(_ v: CFTypeRef?) -> String {
        guard let v else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        if let u = v as? URL { return u.absoluteString }
        if CFGetTypeID(v) == CFURLGetTypeID() { return (v as! CFURL as URL).absoluteString }
        if let a = v as? NSAttributedString { return a.string }
        return ""
    }

    static func frame(of e: AXUIElement) -> CGRect {
        var p = CGPoint.zero, s = CGSize.zero
        if let pv = attr(e, kAXPositionAttribute), CFGetTypeID(pv) == AXValueGetTypeID() { AXValueGetValue(pv as! AXValue, .cgPoint, &p) }
        if let sv = attr(e, kAXSizeAttribute), CFGetTypeID(sv) == AXValueGetTypeID() { AXValueGetValue(sv as! AXValue, .cgSize, &s) }
        return CGRect(origin: p, size: s)
    }

    static func actions(of e: AXUIElement) -> [String] {
        AXUIElementSetMessagingTimeout(e, 0.25)
        var names: CFArray?
        guard AXUIElementCopyActionNames(e, &names) == .success, let arr = names as? [String] else { return [] }
        return arr
    }

    static func clip(_ s: String, _ n: Int) -> String {
        let one = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return one.count > n ? String(one.prefix(n)) + "…" : one
    }

    // MARK: Windows

    public func windows(of app: NSRunningApplication) -> [AXUIElement] {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.3)
        var result: [AXUIElement] = []
        if let focused = AXEngine.attr(el, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let win = focused as! AXUIElement
            AXUIElementSetMessagingTimeout(win, 0.3)
            result.append(win)
        }
        if let ws = AXEngine.attr(el, kAXWindowsAttribute) as? [AXUIElement] {
            for w in ws where !result.contains(where: { CFEqual($0, w) }) {
                AXUIElementSetMessagingTimeout(w, 0.3)
                result.append(w)
            }
        }
        return result
    }

    public func mainWindow(of app: NSRunningApplication, titleContains: String? = nil) throws -> AXUIElement {
        let ws = windows(of: app).filter { AXEngine.frame(of: $0).width > 60 }
        if let t = titleContains?.lowercased(), !t.isEmpty,
           let w = ws.first(where: { AXEngine.string(AXEngine.attr($0, kAXTitleAttribute)).lowercased().contains(t) }) {
            return w
        }
        if let w = ws.first { return w }
        throw AXEngineError.noWindow(app.localizedName ?? "\(app.processIdentifier)")
    }

    // MARK: Snapshot

    private static let fetchAttrs: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
        kAXPositionAttribute, kAXSizeAttribute, kAXEnabledAttribute, kAXFocusedAttribute, kAXChildrenAttribute,
        kAXHelpAttribute, "AXURL", "AXPlaceholderValue",
    ]

    public func snapshot(app: NSRunningApplication, windowTitle: String? = nil, maxNodes: Int = 2500, interactiveOnly: Bool = false) throws -> AppSnapshot {
        guard isTrusted else { throw AXEngineError.notTrusted }
        enableAccessibility(for: app)
        let window = try mainWindow(of: app, titleContains: windowTitle)
        AXUIElementSetMessagingTimeout(window, 0.3)
        let wFrame = AXEngine.frame(of: window)
        var nodes: [UIElementNode] = []
        var truncated = false
        let screens = NSScreen.screens.map { CoordinateSpace.cgRect(fromCocoa: $0.frame) }
        let visibleBounds = wFrame

        func visit(_ e: AXUIElement, depth: Int, printedDepth: Int) {
            if nodes.count >= maxNodes { truncated = true; return }
            if depth > 30 { return }
            AXUIElementSetMessagingTimeout(e, 0.25)
            var values: CFArray?
            let attrs = AXEngine.fetchAttrs as CFArray
            guard AXUIElementCopyMultipleAttributeValues(e, attrs, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
                  let vals = values as? [AnyObject], vals.count == AXEngine.fetchAttrs.count else { return }
            func v(_ i: Int) -> CFTypeRef? {
                let o = vals[i]
                if CFGetTypeID(o) == AXValueGetTypeID(), AXValueGetType(o as! AXValue) == .axError { return nil }
                return o
            }
            let role = AXEngine.string(v(0))
            let subrole = AXEngine.string(v(1))
            let title = AXEngine.string(v(2))
            let desc = AXEngine.string(v(3))
            var value = AXEngine.string(v(4))
            if value.count > 300 { value = String(value.prefix(300)) }
            var origin = CGPoint.zero, size = CGSize.zero
            if let pv = v(5), CFGetTypeID(pv) == AXValueGetTypeID() { AXValueGetValue(pv as! AXValue, .cgPoint, &origin) }
            if let sv = v(6), CFGetTypeID(sv) == AXValueGetTypeID() { AXValueGetValue(sv as! AXValue, .cgSize, &size) }
            let frame = CGRect(origin: origin, size: size)
            let enabled = (v(7) as? Bool) ?? true
            let focused = (v(8) as? Bool) ?? false
            let children = (v(9) as? [AXUIElement]) ?? []
            let help = AXEngine.string(v(10))
            let url = AXEngine.string(v(11))
            let placeholder = AXEngine.string(v(12))

            var label = !title.isEmpty ? title : (!desc.isEmpty ? desc : (!placeholder.isEmpty ? placeholder : help))
            if label.isEmpty && role == "AXStaticText" { label = value; value = "" }

            let onScreen = frame.width > 0 && frame.height > 0 && frame.intersects(visibleBounds) &&
                screens.contains(where: { $0.intersects(frame) })
            let isContainer = AXEngine.containerOnlyRoles.contains(role) && label.isEmpty && value.isEmpty
            let meaningful = !isContainer && (AXEngine.interactableRoles.contains(role) || !label.isEmpty || !value.isEmpty)
            let keep = meaningful && frame.width >= 1 && frame.height >= 1 && (!interactiveOnly || AXEngine.pressableRoles.contains(role) || role.contains("Text") || role == "AXComboBox")
            var nextPrinted = printedDepth
            if keep {
                let acts = AXEngine.actions(of: e)
                nodes.append(UIElementNode(index: nodes.count + 1, depth: printedDepth, role: role, subrole: subrole, label: label,
                                           value: value, url: url, frame: frame, actions: acts, enabled: enabled,
                                           focused: focused, onScreen: onScreen, element: e))
                nextPrinted += 1
            }
            // Text runs inside a labelled link/button repeat the label: skip them.
            if keep && (role == "AXLink" || role == "AXButton") && !label.isEmpty {
                for c in children {
                    let cr = AXEngine.string(AXEngine.attr(c, kAXRoleAttribute))
                    if cr == "AXStaticText" || cr == "AXImage" { continue }
                    visit(c, depth: depth + 1, printedDepth: nextPrinted)
                }
                return
            }
            for c in children { visit(c, depth: depth + 1, printedDepth: nextPrinted) }
        }

        visit(window, depth: 0, printedDepth: 0)
        // If Chromium-like app just enabled accessibility, the renderer might still be populating AXWebArea.
        // If we got very few nodes and no web area, wait briefly and retry once.
        if AXEngine.isChromiumLike(app) && nodes.count <= 5 && !nodes.contains(where: { $0.role == "AXWebArea" }) {
            usleep(250_000)
            nodes.removeAll()
            truncated = false
            visit(window, depth: 0, printedDepth: 0)
        }
        let snap = AppSnapshot(appName: app.localizedName ?? "?", pid: app.processIdentifier,
                               windowTitle: AXEngine.string(AXEngine.attr(window, kAXTitleAttribute)),
                               windowFrame: wFrame, nodes: nodes, truncated: truncated)
        lock.lock(); lastSnapshots[app.processIdentifier] = snap; lock.unlock()
        return snap
    }

    public func cachedSnapshot(pid: pid_t) -> AppSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return lastSnapshots[pid]
    }

    // MARK: Element lookup

    /// Find an element by id (from the last snapshot) or by fuzzy text query.
    public func find(app: NSRunningApplication, id: Int?, query: String?, role: String? = nil, refresh: Bool = false) throws -> UIElementNode {
        var snap = refresh ? nil : cachedSnapshot(pid: app.processIdentifier)
        if snap == nil || (id == nil && query != nil) {
            let isChrom = AXEngine.isChromiumLike(app)
            snap = try snapshot(app: app, maxNodes: isChrom ? 300 : 2500, interactiveOnly: isChrom ? true : false)
        }
        guard let s = snap else { throw AXEngineError.elementNotFound("\(id ?? -1)") }
        if let id {
            guard let n = s.nodes.first(where: { $0.index == id }) else { throw AXEngineError.elementNotFound("id=\(id)") }
            return n
        }
        guard let q = query?.lowercased(), !q.isEmpty else { throw AXEngineError.elementNotFound("(empty query)") }
        let roleFilter = role.map { $0.lowercased().hasPrefix("ax") ? $0.lowercased() : "ax" + $0.lowercased() }
        func score(_ n: UIElementNode) -> Double? {
            if let rf = roleFilter, n.role.lowercased() != rf { return nil }
            let l = n.label.lowercased(), v = n.value.lowercased()
            var sc: Double
            if l == q || v == q { sc = 100 }
            else if l.hasPrefix(q) { sc = 70 }
            else if l.contains(q) || v.contains(q) { sc = 50 }
            else if n.url.lowercased().contains(q) { sc = 30 }
            else { return nil }
            if n.isPressable { sc += 15 }
            if n.onScreen { sc += 20 }
            if !n.enabled { sc -= 30 }
            sc -= min(Double(n.frame.width * n.frame.height) / 40_000, 10)  // prefer specific (smaller) controls
            return sc
        }
        let best = s.nodes.compactMap { n in score(n).map { (n, $0) } }.max { $0.1 < $1.1 }
        guard let found = best?.0 else { throw AXEngineError.elementNotFound("\"\(q)\"") }
        return found
    }

    /// Re-read a live element's frame (pages scroll / reflow between snapshot and action).
    public func liveFrame(_ e: AXUIElement) -> CGRect { AXEngine.frame(of: e) }

    // MARK: Hit testing

    /// Hit-test. With a pid the test is app-scoped, so it works even when the
    /// app's window is covered by other windows (true background operation).
    public func element(at point: CGPoint, pid: pid_t? = nil) -> AXUIElement? {
        let sys = pid.map { AXUIElementCreateApplication($0) } ?? AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(sys, 1.0)
        var e: AXUIElement?
        return AXUIElementCopyElementAtPosition(sys, Float(point.x), Float(point.y), &e) == .success ? e : nil
    }

    public func pid(of e: AXUIElement) -> pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(e, &p)
        return p
    }

    public func parent(of e: AXUIElement) -> AXUIElement? {
        guard let p = AXEngine.attr(e, kAXParentAttribute), CFGetTypeID(p) == AXUIElementGetTypeID() else { return nil }
        return (p as! AXUIElement)
    }

    /// Is `candidate` the same as, or nested inside, `target`?
    public func isSameOrDescendant(_ candidate: AXUIElement, of target: AXUIElement, maxHops: Int = 12) -> Bool {
        var cur: AXUIElement? = candidate
        var hops = 0
        while let c = cur, hops <= maxHops {
            if CFEqual(c, target) { return true }
            cur = parent(of: c)
            hops += 1
        }
        return false
    }

    /// Choose a click point inside `frame` that actually hits `target`
    /// (handles sticky headers, overlays, popovers partially covering it).
    public func verifiedPoint(for target: AXUIElement, frame: CGRect) -> CGPoint? {
        let inset = frame.insetBy(dx: min(frame.width * 0.18, 10), dy: min(frame.height * 0.18, 8))
        let candidates: [CGPoint] = [
            CGPoint(x: frame.midX, y: frame.midY),
            CGPoint(x: inset.minX + inset.width * 0.3, y: frame.midY), CGPoint(x: inset.minX + inset.width * 0.7, y: frame.midY),
            CGPoint(x: frame.midX, y: inset.minY + inset.height * 0.3), CGPoint(x: frame.midX, y: inset.minY + inset.height * 0.7),
            CGPoint(x: inset.minX, y: inset.minY), CGPoint(x: inset.maxX, y: inset.minY),
            CGPoint(x: inset.minX, y: inset.maxY), CGPoint(x: inset.maxX, y: inset.maxY),
        ]
        let owner = pid(of: target)
        for p in candidates {
            if let hit = element(at: p, pid: owner), isSameOrDescendant(hit, of: target) { return p }
        }
        return nil
    }

    /// Nearest ancestor (including self) that supports AXPress.
    public func pressableAncestor(of e: AXUIElement, maxHops: Int = 4) -> AXUIElement? {
        var cur: AXUIElement? = e
        var hops = 0
        while let c = cur, hops <= maxHops {
            let role = AXEngine.string(AXEngine.attr(c, kAXRoleAttribute))
            if role == "AXWebArea" || role == "AXWindow" || role == "AXScrollArea" { return nil }
            if AXEngine.actions(of: c).contains("AXPress") { return c }
            cur = parent(of: c)
            hops += 1
        }
        return nil
    }

    // MARK: Semantic actions

    @discardableResult
    public func perform(_ action: String, on e: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(e, 0.3)
        return AXUIElementPerformAction(e, action as CFString) == .success
    }

    public func scrollToVisible(_ e: AXUIElement) -> Bool { perform("AXScrollToVisible", on: e) }

    public func focus(_ e: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(e, 0.3)
        return AXUIElementSetAttributeValue(e, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    public func setValue(_ e: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetMessagingTimeout(e, 0.3)
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(e, kAXValueAttribute as CFString, &settable)
        guard settable.boolValue else { return false }
        return AXUIElementSetAttributeValue(e, kAXValueAttribute as CFString, text as CFTypeRef) == .success
    }

    /// Insert text at the caret of the focused element of `pid` (no keystrokes).
    public func insertAtCaret(pid: pid_t, _ text: String) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let f = AXEngine.attr(app, kAXFocusedUIElementAttribute), CFGetTypeID(f) == AXUIElementGetTypeID() else { return false }
        let el = f as! AXUIElement
        AXUIElementSetMessagingTimeout(el, 0.3)
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(el, kAXSelectedTextAttribute as CFString, &settable)
        guard settable.boolValue else { return false }
        let before = AXEngine.string(AXEngine.attr(el, kAXValueAttribute))
        guard AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success else { return false }
        let after = AXEngine.string(AXEngine.attr(el, kAXValueAttribute))
        return after != before || before.isEmpty == false && after.contains(text)
    }

    public func windowTitle(pid: pid_t) -> String {
        let app = AXUIElementCreateApplication(pid)
        guard let w = AXEngine.attr(app, kAXFocusedWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() else { return "" }
        return AXEngine.string(AXEngine.attr(w as! AXUIElement, kAXTitleAttribute))
    }

    /// Element description used in action results.
    public func describe(_ e: AXUIElement) -> String {
        let role = AXEngine.string(AXEngine.attr(e, kAXRoleAttribute))
        var label = AXEngine.string(AXEngine.attr(e, kAXTitleAttribute))
        if label.isEmpty { label = AXEngine.string(AXEngine.attr(e, kAXDescriptionAttribute)) }
        if label.isEmpty { label = AXEngine.string(AXEngine.attr(e, kAXValueAttribute)) }
        return label.isEmpty ? role : "\(role) \"\(AXEngine.clip(label, 60))\""
    }
}

// MARK: - Coordinate spaces

public enum CoordinateSpace {
    /// Height of the primary display (the one whose Cocoa origin is (0,0)).
    public static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? CGDisplayBounds(CGMainDisplayID()).height
    }
    /// Cocoa (bottom-left origin, y up) rect -> CG/AX global (top-left origin, y down).
    public static func cgRect(fromCocoa r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    public static func screenRects() -> [CGRect] { NSScreen.screens.map { cgRect(fromCocoa: $0.frame) } }
    public static func clampToScreens(_ p: CGPoint) -> CGPoint {
        let rects = screenRects()
        if rects.contains(where: { $0.contains(p) }) { return p }
        guard let r = rects.min(by: { dist($0, p) < dist($1, p) }) else { return p }
        return CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
    }
    private static func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }
}
