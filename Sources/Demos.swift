import Cocoa
import Foundation

// MARK: - Demos (client side: every step goes through the real daemon pipeline)

enum Demos {
    struct LinkInfo { let id: Int; let label: String; let url: String; let frame: CGRect }

    static func links(in stateText: String) -> [LinkInfo] {
        let re = try! NSRegularExpression(pattern: #"\[(\d+)\] Link(?:\([^)]*\))? (?:"(.*?)" )?(?:value="[^"]*" )?url=(\S+) @\((-?\d+),(-?\d+) (\d+)x(\d+)\)(.*)$"#,
                                          options: [.anchorsMatchLines])
        let ns = stateText as NSString
        return re.matches(in: stateText, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            func g(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
            if g(8).contains("offscreen") { return nil }
            return LinkInfo(id: Int(g(1)) ?? 0, label: g(2), url: g(3),
                            frame: CGRect(x: Double(g(4)) ?? 0, y: Double(g(5)) ?? 0, width: Double(g(6)) ?? 0, height: Double(g(7)) ?? 0))
        }
    }

    static func text(_ r: [String: Any]) -> String { r["text"] as? String ?? "" }
    static func pause(_ s: Double) { usleep(useconds_t(s * 1_000_000)) }

    static func run(_ name: String) {
        guard Daemon.ensureRunning() else { print("❌ daemon failed to start"); exit(2) }
        switch name {
        case "demo": motionDemo()
        case "play": calculator(); bilibili()
        default: bilibili()
        }
        call(["cmd": "wait", "seconds": 0.1], quiet: true)
        print("✅ demo finished — your mouse and keyboard were never touched.")
        exit(0)
    }

    static func motionDemo() {
        guard let s = NSScreen.screens.first else { return }
        let w = s.frame.width, h = s.frame.height
        let pts = [(0.22, 0.30), (0.78, 0.26), (0.70, 0.72), (0.28, 0.70), (0.50, 0.48), (0.53, 0.50), (0.15, 0.85), (0.85, 0.15), (0.5, 0.5)]
        print("🎯 Motion demo: arcs, minimum-jerk easing, Fitts' law timing, press ripples")
        for (x, y) in pts {
            call(["cmd": "move", "x": w * x, "y": h * y], quiet: true)
            call(["cmd": "pulse"], quiet: true)
            pause(0.12)
        }
    }

    static func calculator() {
        print("🧮 Calculator: 2026 × 42 (pure accessibility presses — zero pointer use)")
        call(["cmd": "open_app", "name": "Calculator", "activate": true])
        pause(0.9)
        _ = call(["cmd": "state", "app": "Calculator", "interactive": true], quiet: true)
        var cleared = false
        for t in ["全部清除", "All Clear", "清除", "Clear", "AC"] where !cleared {
            let r = call(["cmd": "click", "app": "Calculator", "title": t, "role": "button"], quiet: true)
            cleared = (r["ok"] as? Bool) == true
        }
        let keys: [[String]] = [["2"], ["0"], ["2"], ["6"], ["乘", "multiply", "×"], ["4"], ["2"], ["等于", "equals", "="]]
        for alts in keys {
            for t in alts {
                let r = call(["cmd": "click", "app": "Calculator", "title": t, "role": "button"], quiet: true)
                if (r["ok"] as? Bool) == true { print("  • \(text(r).components(separatedBy: "\n").first ?? "")"); break }
            }
            pause(0.08)
        }
        let st = text(call(["cmd": "state", "app": "Calculator"], quiet: true))
        if let line = st.components(separatedBy: "\n").first(where: { $0.contains("85") && $0.contains("092") || $0.contains("85092") || $0.contains("85,092") }) {
            print("  = \(line.trimmingCharacters(in: .whitespaces))")
        }
        pause(1.0)
    }

    static func bilibili() {
        print("🎬 Chrome + bilibili: element-accurate clicks via the page's accessibility tree")
        call(["cmd": "open_url", "url": "https://www.bilibili.com/", "app": "Google Chrome", "activate": true])
        pause(3.5)
        var st = text(call(["cmd": "state", "app": "Google Chrome", "interactive": true], quiet: true))
        var videos = links(in: st).filter { $0.url.contains("/video/BV") && $0.frame.width >= 120 && $0.frame.height >= 40 }
        print("  found \(videos.count) on-screen video cards")
        for v in videos.prefix(3) {
            call(["cmd": "hover", "app": "Google Chrome", "id": v.id], quiet: true)
            pause(0.45)
        }
        call(["cmd": "scroll", "app": "Google Chrome", "dy": -520])
        pause(1.0)
        st = text(call(["cmd": "state", "app": "Google Chrome", "interactive": true], quiet: true))
        videos = links(in: st).filter { $0.url.contains("/video/BV") && $0.frame.width >= 120 && $0.frame.height >= 40 }
        guard let pick = videos.dropFirst(videos.count > 2 ? 1 : 0).first else { print("  no video card visible"); return }
        call(["cmd": "hover", "app": "Google Chrome", "id": pick.id], quiet: true)
        pause(0.35)
        let r = call(["cmd": "click", "app": "Google Chrome", "id": pick.id])
        if (r["ok"] as? Bool) != true { return }
        pause(3.0)
        let after = text(call(["cmd": "state", "app": "Google Chrome", "interactive": true], quiet: true))
        if let w = after.components(separatedBy: "\n").dropFirst().first { print("  now playing → \(w)") }
        call(["cmd": "scroll", "app": "Google Chrome", "dy": -360], quiet: true)
        pause(0.6)
        let related = links(in: after).filter { $0.url.contains("/video/BV") && $0.frame.minX > 900 }
        if let rel = related.first { call(["cmd": "hover", "app": "Google Chrome", "id": rel.id], quiet: true) }
        pause(0.8)
    }
}
