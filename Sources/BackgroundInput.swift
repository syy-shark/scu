import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

// MARK: - Background Input
//
// Every primitive here is delivered per-process (SLEventPostToPid), so:
//   • the user's hardware pointer never moves,
//   • the frontmost app / key window the user is typing into never changes,
//   • the target window is never raised.
// Mirrors Codex's `SynthesizedEvent` + `SyntheticAppFocusEnforcer` +
// `SystemFocusStealPreventer` trio.

public enum MouseButtonKind: String {
    case left, right, middle
    var cg: CGMouseButton { self == .left ? .left : (self == .right ? .right : .center) }
    var number: Int64 { self == .left ? 0 : (self == .right ? 1 : 2) }
    var down: CGEventType { self == .left ? .leftMouseDown : (self == .right ? .rightMouseDown : .otherMouseDown) }
    var up: CGEventType { self == .left ? .leftMouseUp : (self == .right ? .rightMouseUp : .otherMouseUp) }
    var dragged: CGEventType { self == .left ? .leftMouseDragged : (self == .right ? .rightMouseDragged : .otherMouseDragged) }
}

public struct WindowTarget {
    public let pid: pid_t
    public let windowID: CGWindowID
    public let bounds: CGRect
    public let ownerName: String

    /// Convert a global (top-left origin) point to this window's local space.
    public func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - bounds.minX, y: p.y - bounds.minY) }
}

public enum BackgroundInput {

    // MARK: Window resolution

    /// Top-most normal window (layer 0) under a global point, ignoring our own overlay.
    public static func window(at point: CGPoint) -> WindowTarget? {
        let myPid = getpid()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != myPid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let alpha = info[kCGWindowAlpha as String] as? CGFloat, alpha > 0.01 else { continue }
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if rect.contains(point) {
                return WindowTarget(pid: pid, windowID: wid, bounds: rect, ownerName: info[kCGWindowOwnerName as String] as? String ?? "")
            }
        }
        return nil
    }

    /// Front-most window belonging to pid (optionally containing a point).
    /// Falls back to off-screen windows (other Spaces / fully covered).
    public static func frontWindow(of pid: pid_t, containing point: CGPoint? = nil) -> WindowTarget? {
        for opts: CGWindowListOption in [[.optionOnScreenOnly, .excludeDesktopElements], [.optionAll, .excludeDesktopElements]] {
            if let w = scanWindows(pid: pid, point: point, options: opts) { return w }
        }
        return nil
    }

    private static func scanWindows(pid: pid_t, point: CGPoint?, options: CGWindowListOption) -> WindowTarget? {
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in list {
            guard let p = info[kCGWindowOwnerPID as String] as? pid_t, p == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if rect.width < 40 || rect.height < 40 { continue }
            if let pt = point, !rect.contains(pt) { continue }
            return WindowTarget(pid: p, windowID: wid, bounds: rect, ownerName: info[kCGWindowOwnerName as String] as? String ?? "")
        }
        return nil
    }

    /// The key window of an app (for focus hand-back).
    static func keyWindowID(of pid: pid_t) -> CGWindowID? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var ref: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref) == .success,
           let r = ref, CFGetTypeID(r) == AXUIElementGetTypeID() {
            if let wid = SkyLight.windowID(of: r as! AXUIElement) { return wid }
        }
        return frontWindow(of: pid)?.windowID
    }

    // MARK: Focus enforcement

    /// Run `body` with `target` acting as the key window of its app, then hand
    /// keyboard focus straight back to whatever the user was using.
    public static func withSyntheticFocus<T>(_ target: WindowTarget, _ body: () -> T) -> T {
        let userApp = NSWorkspace.shared.frontmostApplication
        let userPid = userApp?.processIdentifier ?? 0
        if userPid == target.pid {
            return body()   // target already frontmost: nothing to fake
        }
        let userWindow = keyWindowID(of: userPid) ?? 0
        let previous = SkyLight.focusWithoutRaise(pid: target.pid, window: target.windowID)
        usleep(40_000)   // let AppKit/Chromium update their key-window routing
        let result = body()
        usleep(35_000)
        if let prev = previous, userWindow != 0 {
            SkyLight.restoreFocus(previous: prev, previousWindow: userWindow, targetPid: target.pid, targetWindow: target.windowID)
        }
        FocusStealGuard.restoreIfStolen(from: userApp, thief: target.pid)
        return result
    }

    // MARK: Mouse

    private static func makeMouse(_ type: CGEventType, _ point: CGPoint, _ button: MouseButtonKind) -> CGEvent? {
        let src = CGEventSource(stateID: .hidSystemState)
        return CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: point, mouseButton: button.cg)
    }

    private static func stamp(_ e: CGEvent, target: WindowTarget, point: CGPoint, phase: Int64?, clickState: Int64,
                              button: MouseButtonKind, group: Int64, flags: CGEventFlags) {
        if let phase { SkyLight.setField(e, 0, phase) }
        SkyLight.setField(e, 1, clickState)            // kCGMouseEventClickState
        SkyLight.setField(e, 3, button.number)         // kCGMouseEventButtonNumber
        SkyLight.setField(e, 7, 3)                     // kCGMouseEventSubtype = touch
        SkyLight.setField(e, 40, Int64(target.pid))    // kCGEventTargetUnixProcessID
        SkyLight.setField(e, 51, Int64(target.windowID))
        SkyLight.setField(e, 58, group)                // click-group id (gesture coalescing)
        SkyLight.setField(e, 91, Int64(target.windowID)) // window under pointer
        SkyLight.setField(e, 92, Int64(target.windowID)) // ...that can handle this event
        // Window-LOCAL point: verified on macOS 26/27 to be what WindowServer
        // hit-tests for per-pid delivery (screen-space misses background windows).
        SkyLight.stampWindowLocation(e, target.local(point))
        if !flags.isEmpty { e.flags = flags }
    }

    private static func send(_ e: CGEvent, _ target: WindowTarget) {
        // Exactly one transport per event: duplicates (SkyLight + public) make
        // Chromium see down,down,up,up and drop the click.
        SkyLight.post(e, to: target.pid)
    }

    private static func groupID() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds & 0x7fff_ffff)
    }

    /// Background mouse-move so hover states (menus, tooltips, card previews) react.
    public static func hover(at point: CGPoint, target: WindowTarget) {
        guard let mv = makeMouse(.mouseMoved, point, .left) else { return }
        stamp(mv, target: target, point: point, phase: nil, clickState: 0, button: .left, group: groupID(), flags: [])
        send(mv, target)
    }

    /// Pixel-exact click delivered to a background window. Works for AppKit,
    /// Catalyst, WebKit and Chromium (incl. its user-activation gate).
    public static func click(at point: CGPoint, target: WindowTarget, button: MouseButtonKind = .left,
                             count: Int = 1, flags: CGEventFlags = []) {
        let group = groupID()
        let isLeft = button == .left
        withSyntheticFocus(target) {
            // 1. prime cursor-tracking state at the target point
            if let mv = makeMouse(.mouseMoved, point, button) {
                stamp(mv, target: target, point: point, phase: 2, clickState: 0, button: button, group: group, flags: flags)
                send(mv, target)
            }
            usleep(15_000)
            // 2. off-screen primer pair: opens Chromium's user-activation gate without hitting the DOM
            if isLeft {
                let off = CGPoint(x: -1, y: -1)
                if let d = makeMouse(button.down, off, button) {
                    stamp(d, target: target, point: off, phase: 1, clickState: 1, button: button, group: group, flags: flags)
                    send(d, target)
                }
                usleep(1_000)
                if let u = makeMouse(button.up, off, button) {
                    stamp(u, target: target, point: off, phase: 2, clickState: 1, button: button, group: group, flags: flags)
                    send(u, target)
                }
                usleep(90_000)
            }
            // 3. the real click(s)
            for i in 1...max(1, min(count, 3)) {
                if let d = makeMouse(button.down, point, button) {
                    stamp(d, target: target, point: point, phase: 3, clickState: Int64(i), button: button, group: group, flags: flags)
                    send(d, target)
                }
                usleep(isLeft ? 30_000 : 40_000)
                if let u = makeMouse(button.up, point, button) {
                    stamp(u, target: target, point: point, phase: 3, clickState: Int64(i), button: button, group: group, flags: flags)
                    send(u, target)
                }
                if i < count { usleep(70_000) }
            }
        }
    }

    /// Drag inside a background window (sliders, selections, reorder handles).
    public static func drag(from a: CGPoint, to b: CGPoint, target: WindowTarget, duration: Double = 0.45) {
        let group = groupID()
        withSyntheticFocus(target) {
            if let mv = makeMouse(.mouseMoved, a, .left) {
                stamp(mv, target: target, point: a, phase: nil, clickState: 0, button: .left, group: group, flags: [])
                send(mv, target)
            }
            usleep(15_000)
            if let d = makeMouse(.leftMouseDown, a, .left) {
                stamp(d, target: target, point: a, phase: nil, clickState: 1, button: .left, group: group, flags: [])
                send(d, target)
            }
            let steps = max(8, Int(duration * 60))
            for i in 1...steps {
                let t = Motion.minimumJerk(Double(i) / Double(steps))
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                if let e = makeMouse(.leftMouseDragged, p, .left) {
                    stamp(e, target: target, point: p, phase: nil, clickState: 1, button: .left, group: group, flags: [])
                    send(e, target)
                }
                usleep(useconds_t(duration / Double(steps) * 1_000_000))
            }
            if let u = makeMouse(.leftMouseUp, b, .left) {
                stamp(u, target: target, point: b, phase: nil, clickState: 1, button: .left, group: group, flags: [])
                send(u, target)
            }
        }
    }

    /// Pixel-precise trackpad-style scroll delivered to a background window.
    /// `dy` < 0 reveals content below (natural "scroll down").
    public static func scroll(at point: CGPoint, target: WindowTarget, dx: Int = 0, dy: Int, duration: Double = 0.45) {
        hover(at: point, target: target)
        usleep(12_000)
        // Momentum-like profile: ease-out distribution of pixel deltas.
        let frames = max(6, Int(duration * 60))
        var emittedX = 0, emittedY = 0
        for i in 1...frames {
            let t = Motion.easeOutCubic(Double(i) / Double(frames))
            let wantY = Int((Double(dy) * t).rounded()), wantX = Int((Double(dx) * t).rounded())
            let stepY = Int32(wantY - emittedY), stepX = Int32(wantX - emittedX)
            emittedY = wantY; emittedX = wantX
            if stepX == 0 && stepY == 0 { usleep(useconds_t(duration / Double(frames) * 1_000_000)); continue }
            guard let e = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .pixel,
                                  wheelCount: 2, wheel1: stepY, wheel2: stepX, wheel3: 0) else { continue }
            e.location = point
            e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            SkyLight.setField(e, 40, Int64(target.pid))
            SkyLight.setField(e, 51, Int64(target.windowID))
            SkyLight.setField(e, 91, Int64(target.windowID))
            SkyLight.setField(e, 92, Int64(target.windowID))
            SkyLight.stampWindowLocation(e, target.local(point))
            send(e, target)
            usleep(useconds_t(duration / Double(frames) * 1_000_000))
        }
    }

    // MARK: Keyboard

    public static func key(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags, pid: pid_t) {
        guard let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: keyCode, keyDown: down) else { return }
        e.flags = flags
        SkyLight.setField(e, 40, Int64(pid))
        SkyLight.post(e, to: pid, authenticate: true)
    }

    /// Press a key chord (e.g. "cmd+shift+t", "return", "esc") in a background app.
    public static func press(_ chord: String, pid: pid_t, window: WindowTarget? = nil) throws {
        let (code, flags) = try KeyMap.parse(chord)
        let work = {
            key(code, down: true, flags: flags, pid: pid)
            usleep(18_000)
            key(code, down: false, flags: flags, pid: pid)
        }
        if let w = window { withSyntheticFocus(w, work) } else { work() }
    }

    /// Type unicode text into the background app's focused field.
    public static func type(_ text: String, pid: pid_t, window: WindowTarget? = nil, cps: Double = 60) {
        let work = {
            var chunk: [UniChar] = []
            func flushChunk() {
                guard !chunk.isEmpty else { return }
                for down in [true, false] {
                    guard let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: 0, keyDown: down) else { continue }
                    e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                    SkyLight.setField(e, 40, Int64(pid))
                    SkyLight.post(e, to: pid, authenticate: true)
                    usleep(5_000)
                }
                chunk.removeAll(keepingCapacity: true)
                usleep(8_000)
            }

            for ch in text {
                if ch == "\n" {
                    flushChunk()
                    key(36, down: true, flags: [], pid: pid); usleep(8_000); key(36, down: false, flags: [], pid: pid)
                    usleep(8_000)
                    continue
                }
                if ch == "\t" {
                    flushChunk()
                    key(48, down: true, flags: [], pid: pid); usleep(8_000); key(48, down: false, flags: [], pid: pid)
                    usleep(8_000)
                    continue
                }
                let u16 = Array(String(ch).utf16)
                if chunk.count + u16.count > 20 {
                    flushChunk()
                }
                chunk.append(contentsOf: u16)
            }
            flushChunk()
        }
        if let w = window { withSyntheticFocus(w, work) } else { work() }
    }

    // MARK: Legacy foreground path (opt-in only)

    /// Classic HID click for the rare app that rejects every per-process route.
    /// The pointer is hidden-warped and restored within the same frame.
    public static func foregroundClick(at point: CGPoint, button: MouseButtonKind = .left, count: Int = 1) {
        let original = CGEvent(source: nil)?.location ?? point
        CGAssociateMouseAndMouseCursorPosition(0)
        defer {
            CGWarpMouseCursorPosition(original)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        for i in 1...max(1, count) {
            for type in [button.down, button.up] {
                guard let e = makeMouse(type, point, button) else { continue }
                e.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                e.post(tap: .cghidEventTap)
                usleep(type == button.down ? 25_000 : 10_000)
            }
        }
    }
}

// MARK: - Focus-steal guard (Codex: SystemFocusStealPreventer)

enum FocusStealGuard {
    /// If the agent's target app grabbed activation (e.g. a link that calls
    /// window.focus(), or an app that self-activates on click), give the user's
    /// app its focus back immediately.
    static func restoreIfStolen(from userApp: NSRunningApplication?, thief: pid_t) {
        guard let userApp, userApp.processIdentifier != thief, !userApp.isTerminated else { return }
        for _ in 0..<4 {
            usleep(20_000)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == thief {
                userApp.activate(options: [])
                return
            }
        }
    }
}

// MARK: - Key map

enum KeyMap {
    struct KeyError: Error, CustomStringConvertible { let description: String }

    static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
        "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
        ".": 47, "`": 50,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
        "f10": 109, "f11": 103, "f12": 111,
    ]

    static func parse(_ chord: String) throws -> (CGKeyCode, CGEventFlags) {
        var flags: CGEventFlags = []
        var keyName: String?
        for raw in chord.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch raw {
            case "cmd", "command", "super", "meta": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt", "option", "opt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: keyName = raw
            }
        }
        guard let k = keyName, let code = codes[k] else {
            throw KeyError(description: "unknown key in '\(chord)'. Use names like return, esc, tab, space, up, cmd+l, shift+tab")
        }
        if [123, 124, 125, 126, 115, 119, 116, 121, 117].contains(Int(code)) { flags.insert(.maskSecondaryFn) }
        return (code, flags)
    }
}
