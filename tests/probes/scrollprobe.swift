import Cocoa

// Scroll delivery variant probe. usage: scrollprobe <variant>
let v = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "a"
guard let chrome = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else { exit(1) }
let pid = chrome.processIdentifier
let app = AXUIElementCreateApplication(pid)
var wins: CFTypeRef?
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &wins)
guard let win = (wins as? [AXUIElement])?.first(where: {
    var t: CFTypeRef?; AXUIElementCopyAttributeValue($0, kAXTitleAttribute as CFString, &t)
    let s = (t as? String) ?? ""; return s.contains("HIT") || s.contains("FIELD") || s.contains("SCROLL") || s.contains("CU-READY")
}) else { print("no win"); exit(1) }
let wid = SkyLight.windowID(of: win)!
let wf = AXEngine.frame(of: win)
let target = WindowTarget(pid: pid, windowID: wid, bounds: wf, ownerName: "Chrome")
let pt = CGPoint(x: wf.midX, y: wf.minY + wf.height * 0.6)

func makeScroll(_ dy: Int32) -> CGEvent {
    let units: CGScrollEventUnit = v.contains("l") ? .line : .pixel
    let e = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: units, wheelCount: 1, wheel1: units == .line ? (dy > 0 ? 1 : -1) * 3 : dy, wheel2: 0, wheel3: 0)!
    e.location = pt
    if v.contains("c") { e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1) }
    SkyLight.setField(e, 40, Int64(pid))
    if v.contains("w") {
        SkyLight.setField(e, 51, Int64(wid)); SkyLight.setField(e, 91, Int64(wid)); SkyLight.setField(e, 92, Int64(wid))
    }
    if v.contains("L") { SkyLight.stampWindowLocation(e, target.local(pt)) }
    if v.contains("S") { SkyLight.stampWindowLocation(e, pt) }
    return e
}
func post(_ e: CGEvent) {
    if v.contains("p") { e.postToPid(pid) } else { SkyLight.post(e, to: pid) }
}
let work = {
    if v.contains("m") { BackgroundInput.hover(at: pt, target: target); usleep(15_000) }
    for _ in 0..<12 { post(makeScroll(-30)); usleep(16_000) }
}
if v.contains("f") { BackgroundInput.withSyntheticFocus(target, work) } else { work() }
usleep(300_000)
var t: CFTypeRef?
AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &t)
print(v, "->", (t as? String) ?? "")
