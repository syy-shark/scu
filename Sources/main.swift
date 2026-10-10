import Cocoa
import Foundation

// MARK: - CLI entry
//
//   smooth-computer-use <command> [args]   (talks to the auto-started daemon)
//   smooth-computer-use daemon             (overlay + socket server)
//   smooth-computer-use mcp                (MCP stdio server, in-process overlay)

let argv = Array(CommandLine.arguments.dropFirst())

func usage() -> String {
    """
    smooth-computer-use 2.0 — background Computer Use for macOS (Codex-style)

    Inspect
      apps                                   running apps
      state <app> [--window T] [--interactive]   numbered accessibility tree
      screenshot [--app A] [--out file.png]  window capture works even if covered
      doctor                                 permissions & capability check

    Act (never moves your mouse, never steals focus)
      click --app A --id N | --title "text" [--role button]
      click <x> <y> [--app A]                [--right] [--double] [--mode auto|ax|background|foreground]
      hover --app A --id N | --title T
      move <x> <y>
      scroll [--app A] [--id N | <x> <y>] [--dy -400] [--dx 0]
      drag <x1> <y1> <x2> <y2> [--app A]
      type "text" --app A [--id N | --title T] [--clear] [--enter]
      key "cmd+l" --app A [--repeat N]
      set-value "v" --app A --id N
      action ShowMenu --app A --id N
      open-app <Name>        open-url <url> [--app "Google Chrome"]

    Demos
      demo | play | bilibili

    Servers
      daemon | stop | mcp
    Global flags: --speed 1.0  --no-cursor
    """
}

// MARK: Arg parsing

struct Parsed { var positional: [String] = []; var flags: [String: String] = [:] }

func parse(_ args: [String]) -> Parsed {
    var p = Parsed()
    var i = 0
    let boolFlags: Set<String> = ["right", "double", "interactive", "clear", "no-cursor", "middle", "activate", "enter"]
    while i < args.count {
        let a = args[i]
        if a.hasPrefix("--") {
            let key = String(a.dropFirst(2))
            if boolFlags.contains(key) { p.flags[key] = "true"; i += 1; continue }
            if i + 1 < args.count { p.flags[key] = args[i + 1]; i += 2 } else { p.flags[key] = "true"; i += 1 }
        } else {
            p.positional.append(a); i += 1
        }
    }
    return p
}

func buildRequest(_ cmd: String, _ p: Parsed) -> [String: Any]? {
    var r: [String: Any] = [:]
    let pos = p.positional
    for (k, v) in p.flags { r[k] = v }
    if let s = p.flags["speed"], let d = Double(s) { r["speed"] = d }
    if p.flags["no-cursor"] != nil { r["cursor"] = false }
    func num(_ i: Int) -> Double? { i < pos.count ? Double(pos[i]) : nil }
    switch cmd {
    case "apps": r["cmd"] = "apps"
    case "doctor": r["cmd"] = "doctor"
    case "state", "tree":
        r["cmd"] = "state"
        if let a = pos.first { r["app"] = a }
        if p.flags["interactive"] != nil { r["interactive"] = true }
    case "click":
        r["cmd"] = "click"
        if let x = num(0), let y = num(1) { r["x"] = x; r["y"] = y }
        if p.flags["right"] != nil { r["button"] = "right" }
        if p.flags["middle"] != nil { r["button"] = "middle" }
        if p.flags["double"] != nil { r["count"] = 2 }
    case "click-elem":   // v1 compatibility: click-elem <App> <id>
        r["cmd"] = "click"
        if pos.count >= 2 { r["app"] = pos[0]; r["id"] = Int(pos[1]) ?? 0 }
    case "hover": r["cmd"] = "hover"
    case "move":
        r["cmd"] = "move"
        guard let x = num(0), let y = num(1) else { return nil }
        r["x"] = x; r["y"] = y
    case "scroll":
        r["cmd"] = "scroll"
        if let x = num(0), let y = num(1) { r["x"] = x; r["y"] = y }
        else if pos.count == 1, let dy = Int(pos[0]) { r["dy"] = dy }   // v1: scroll <dy>
    case "drag":
        r["cmd"] = "drag"
        guard let a = num(0), let b = num(1), let c = num(2), let d = num(3) else { return nil }
        r["x1"] = a; r["y1"] = b; r["x2"] = c; r["y2"] = d
    case "type":
        r["cmd"] = "type"
        guard let t = pos.first else { return nil }
        r["text"] = t
        if p.flags["clear"] != nil { r["clear"] = true }
        if p.flags["enter"] != nil { r["submit"] = true }
        if r["app"] == nil, let front = NSWorkspace.shared.frontmostApplication?.localizedName { r["app"] = front }
    case "key":
        r["cmd"] = "key"
        guard let k = pos.first else { return nil }
        r["key"] = k
        if r["app"] == nil, let front = NSWorkspace.shared.frontmostApplication?.localizedName { r["app"] = front }
    case "set-value":
        r["cmd"] = "set_value"
        guard let v = pos.first else { return nil }
        r["value"] = v
    case "action":
        r["cmd"] = "action"
        guard let a = pos.first else { return nil }
        r["action"] = a
    case "open-app":
        r["cmd"] = "open_app"
        guard let n = pos.first else { return nil }
        r["name"] = n
    case "open-url":
        r["cmd"] = "open_url"
        guard let u = pos.first else { return nil }
        r["url"] = u
    case "screenshot": r["cmd"] = "screenshot"
    case "wait":
        r["cmd"] = "wait"; r["seconds"] = num(0) ?? 1
    default: return nil
    }
    return r
}

@discardableResult
func call(_ req: [String: Any], quiet: Bool = false) -> [String: Any] {
    guard Daemon.ensureRunning() else {
        print("❌ could not start daemon (see /tmp/smooth-cu-\(getuid()).log)")
        exit(2)
    }
    guard let resp = Daemon.request(req) else {
        print("❌ daemon did not answer")
        exit(2)
    }
    if !quiet, let t = resp["text"] as? String { print(t) }
    return resp
}

// MARK: Dispatch

guard let command = argv.first?.lowercased() else { print(usage()); exit(0) }
let parsed = parse(Array(argv.dropFirst()))

switch command {
case "daemon":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    CursorOverlay.shared.setup()
    Daemon.serve()
    print("smooth-computer-use daemon listening on \(Daemon.socketPath)")
    app.run()

case "mcp":
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    CursorOverlay.shared.setup()
    MCPServer.run()
    app.run()

case "stop":
    if Daemon.isRunning { _ = Daemon.request(["cmd": "stop"]); print("daemon stopped") } else { print("daemon not running") }

case "demo", "play", "bilibili":
    Demos.run(command)

case "help", "-h", "--help":
    print(usage())

default:
    guard let req = buildRequest(command, parsed) else { print(usage()); exit(1) }
    let resp = call(req)
    exit((resp["ok"] as? Bool) == true ? 0 : 1)
}
