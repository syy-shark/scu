import Cocoa
import ApplicationServices

// Probe: background pixel click into Chrome, verifying pointer/focus untouched.
// usage: probe <targetNumber> [mode: bg|ax]

func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ name: String) -> String { (attr(e, name) as? String) ?? "" }
func frame(_ e: AXUIElement) -> CGRect {
    var p = CGPoint.zero, s = CGSize.zero
    if let pv = attr(e, kAXPositionAttribute) { AXValueGetValue(pv as! AXValue, .cgPoint, &p) }
    if let sv = attr(e, kAXSizeAttribute) { AXValueGetValue(sv as! AXValue, .cgSize, &s) }
    return CGRect(origin: p, size: s)
}
func find(_ e: AXUIElement, depth: Int = 0, _ pred: (AXUIElement) -> Bool) -> AXUIElement? {
    if pred(e) { return e }
    if depth > 40 { return nil }
    guard let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
    for k in kids { if let f = find(k, depth: depth + 1, pred) { return f } }
    return nil
}

let args = CommandLine.arguments
let n = args.count > 1 ? args[1] : "5"
let mode = args.count > 2 ? args[2] : "bg"
guard let chrome = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else { print("no chrome"); exit(1) }
let pid = chrome.processIdentifier
let app = AXUIElementCreateApplication(pid)
AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
usleep(300_000)

guard let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement],
      let win = windows.first(where: { let t = str($0, kAXTitleAttribute); return t.contains("CU-READY") || t.contains("HIT") || t.contains("FIELD") || t.contains("SCROLL") || t.contains("CONTEXT") }) else {
    print("test window not found"); exit(1)
}
var btn: AXUIElement?
for _ in 0..<10 {
    btn = find(win) { str($0, kAXRoleAttribute) == "AXButton" && (str($0, kAXDescriptionAttribute) == "Target \(n)" || str($0, kAXTitleAttribute) == "Target \(n)") }
    if btn != nil { break }
    usleep(200_000)
}
guard let b = btn else { print("button not found"); exit(1) }
let f = frame(b)
let center = CGPoint(x: f.midX, y: f.midY)
let wid = SkyLight.windowID(of: win) ?? 0
print("target frame \(f) center \(center) wid \(wid) skylight=\(SkyLight.isAvailable) fwr=\(SkyLight.canFocusWithoutRaise)")

let mouseBefore = CGEvent(source: nil)!.location
let frontBefore = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
let t0 = Date()
if mode == "ax" {
    let r = AXUIElementPerformAction(b, kAXPressAction as CFString)
    print("AXPress ->", r.rawValue)
} else {
    let wb = BackgroundInput.frontWindow(of: pid)?.bounds ?? .zero
    let target = WindowTarget(pid: pid, windowID: wid, bounds: wb, ownerName: "Chrome")
    BackgroundInput.click(at: center, target: target)
}
let dt = Date().timeIntervalSince(t0)
usleep(250_000)
let mouseAfter = CGEvent(source: nil)!.location
let frontAfter = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
print(String(format: "took %.0f ms", dt * 1000))
print("mouse \(mouseBefore) -> \(mouseAfter) moved=\(mouseBefore != mouseAfter)")
print("front \(frontBefore) -> \(frontAfter)")
print("title:", str(win, kAXTitleAttribute))
