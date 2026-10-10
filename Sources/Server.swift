import Cocoa
import Darwin

// MARK: - Persistent daemon
//
// One long-lived process owns the overlay, so the agent cursor stays where it
// last was between separate CLI invocations (continuous, Codex-like motion)
// and there is no window setup cost per command.

public enum Daemon {
    public static var socketPath: String { "/tmp/smooth-cu-\(getuid()).sock" }
    static var lastActivity = Date()
    static let idleExit: TimeInterval = 30 * 60

    // MARK: Server

    public static func serve() {
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { fatalError("socket() failed") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            socketPath.utf8CString.withUnsafeBytes { src in raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(raw.count))) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0, listen(fd, 16) == 0 else { fatalError("bind/listen failed on \(socketPath)") }
        chmod(socketPath, 0o600)

        Thread.detachNewThread {
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { continue }
                DispatchQueue.global(qos: .userInitiated).async { handle(c) }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            if Date().timeIntervalSince(lastActivity) > idleExit { unlink(socketPath); exit(0) }
        }
    }

    private static func handle(_ c: Int32) {
        defer { close(c) }
        guard let line = readLine(c), let data = line.data(using: .utf8),
              let req = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cmd = req["cmd"] as? String else {
            writeJSON(c, ["ok": false, "text": "bad request"])
            return
        }
        lastActivity = Date()
        if cmd == "stop" {
            writeJSON(c, ["ok": true, "text": "daemon stopped"])
            unlink(socketPath)
            DispatchQueue.main.async { exit(0) }
            return
        }
        if let speed = req["speed"] as? Double { DispatchQueue.main.async { CursorOverlay.shared.speed = speed } }
        if let show = req["cursor"] as? Bool { ComputerUse.shared.showCursor = show }
        let r = Router.run(cmd, req)
        var out: [String: Any] = ["ok": r.ok, "text": r.text]
        if !r.data.isEmpty { out["data"] = r.data.mapValues { v -> Any in (v as? CGFloat).map { Double($0) } ?? v } }
        writeJSON(c, out)
    }

    static func readLine(_ fd: Int32) -> String? {
        var buf = [UInt8]()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 10 { break }
            buf.append(byte)
            if buf.count > 4_000_000 { break }
        }
        return buf.isEmpty ? nil : String(decoding: buf, as: UTF8.self)
    }

    static func writeJSON(_ fd: Int32, _ obj: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        data.append(10)
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress! + off, raw.count - off)
                if n <= 0 { break }
                off += n
            }
        }
    }

    // MARK: Client

    static func connectSocket() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            socketPath.utf8CString.withUnsafeBytes { src in raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: src.prefix(raw.count))) }
        }
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if r != 0 { close(fd); return nil }
        return fd
    }

    public static func request(_ req: [String: Any]) -> [String: Any]? {
        guard let fd = connectSocket() else { return nil }
        defer { close(fd) }
        writeJSON(fd, req)
        guard let line = readLine(fd), let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public static var isRunning: Bool { request(["cmd": "ping"]) != nil }

    /// Start the daemon detached in its own session (survives the caller's shell).
    public static func ensureRunning() -> Bool {
        if isRunning { return true }
        guard let exe = Bundle.main.executablePath else { return false }
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var fa: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fa)
        posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0)
        let log = "/tmp/smooth-cu-\(getuid()).log"
        posix_spawn_file_actions_addopen(&fa, 1, log, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        posix_spawn_file_actions_addopen(&fa, 2, log, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(exe), strdup("daemon"), nil]
        let rc = posix_spawn(&pid, exe, &fa, &attr, argv, environ)
        argv.forEach { free($0) }
        posix_spawn_file_actions_destroy(&fa)
        posix_spawnattr_destroy(&attr)
        guard rc == 0 else { return false }
        for _ in 0..<60 {
            usleep(50_000)
            if isRunning { return true }
        }
        return false
    }
}

// MARK: - MCP server (stdio JSON-RPC 2.0)
//
// `smooth-computer-use mcp` lets any MCP client (Antigravity, Claude Code,
// Codex, Cursor…) drive the computer with the same tools Codex exposes.

public enum MCPServer {
    static let outLock = NSLock()

    static func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        outLock.lock()
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        outLock.unlock()
    }

    static func prop(_ type: String, _ desc: String) -> [String: Any] { ["type": type, "description": desc] }

    static let target: [String: Any] = [
        "app": prop("string", "App name, bundle id or pid (e.g. \"Google Chrome\", \"Calculator\")"),
        "element_index": prop("integer", "Element id from the latest get_app_state output"),
        "title": prop("string", "Alternative to element_index: visible text/label of the element (fuzzy)"),
    ]

    static func tool(_ name: String, _ desc: String, _ props: [String: Any], _ required: [String] = []) -> [String: Any] {
        ["name": name, "description": desc, "inputSchema": ["type": "object", "properties": props, "required": required]]
    }

    static var tools: [[String: Any]] {
        [
            tool("list_apps", "List running GUI apps.", [:]),
            tool("get_app_state", "Accessibility tree of an app's window with numbered elements and screen frames. Call before acting; ids change after UI changes. Electron/Chromium apps default to compact interactive controls (capped at 300 elements).",
                 ["app": target["app"]!, "window": prop("string", "Window title substring"), "interactive": prop("boolean", "Only controls & text (default true for Electron/Chromium)"), "max_nodes": prop("integer", "Max elements to inspect (default 300 for Electron)")], ["app"]),
            tool("click", "Click an element (preferred: app+element_index or app+title) or screen point x,y. Runs in the background: never moves the user's mouse or steals focus.",
                 target.merging(["x": prop("number", "Screen x (points)"), "y": prop("number", "Screen y (points)"),
                                 "button": prop("string", "left|right|middle"), "count": prop("integer", "2 = double click"),
                                 "mode": prop("string", "auto|ax|background|foreground")]) { a, _ in a }),
            tool("scroll", "Scroll an app window, element or point.",
                 target.merging(["x": prop("number", ""), "y": prop("number", ""), "direction": prop("string", "up|down|left|right"),
                                 "amount": prop("integer", "Pixels (default 400)")]) { a, _ in a }),
            tool("type_text", "Type text into the app. For chat inputs or forms, specify element_index or title to ensure focus before typing, and set submit=true (or press_enter=true) to send Return immediately.",
                 target.merging(["text": prop("string", "Text to type"), "clear": prop("boolean", "Clear field first"),
                                 "submit": prop("boolean", "Press Return after typing (e.g. to send chat messages)"),
                                 "press_enter": prop("boolean", "Alias for submit")]) { a, _ in a }, ["app", "text"]),
            tool("press_key", "Press a key or chord in the app, e.g. return, enter, esc, tab, space, cmd+a, cmd+c, cmd+v, cmd+l, cmd+shift+t.",
                 ["app": target["app"]!, "key": prop("string", "Key chord (e.g. return, esc, cmd+a, cmd+v)"), "repeat": prop("integer", "Repeat count")], ["app", "key"]),
            tool("set_value", "Set the value of a text field / slider directly.", target.merging(["value": prop("string", "")]) { a, _ in a }, ["app", "value"]),
            tool("perform_secondary_action", "Run an accessibility action: ShowMenu, Increment, Decrement, Confirm, Cancel, Raise, Pick.",
                 target.merging(["action": prop("string", "")]) { a, _ in a }, ["app", "action"]),
            tool("drag", "Drag between two screen points.", ["app": target["app"]!, "from_x": prop("number", ""), "from_y": prop("number", ""),
                                                            "to_x": prop("number", ""), "to_y": prop("number", "")], ["from_x", "from_y", "to_x", "to_y"]),
            tool("hover", "Move the agent cursor over an element (fires hover in the app).", target, ["app"]),
            tool("open_app", "Launch/open an app in the background.", ["name": prop("string", "")], ["name"]),
            tool("open_url", "Open a URL (optionally in a specific browser) without activating it.", ["url": prop("string", ""), "app": target["app"]!], ["url"]),
            tool("screenshot", "Screenshot an app window (even if covered) or the main display. 1 image px = 1 screen point.", ["app": target["app"]!]),
            tool("wait", "Wait N seconds for UI to settle.", ["seconds": prop("number", "")]),
        ]
    }

    public static func run() {
        Thread.detachNewThread {
            let pending = DispatchGroup()
            while let line = Swift.readLine(strippingNewline: true) {
                guard let data = line.data(using: .utf8),
                      let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
                DispatchQueue.global(qos: .userInitiated).async(group: pending) { handle(msg) }
            }
            pending.wait()
            exit(0)
        }
    }

    static func handle(_ msg: [String: Any]) {
        let id = msg["id"]
        let method = msg["method"] as? String ?? ""
        func reply(_ result: [String: Any]) { if let id { send(["jsonrpc": "2.0", "id": id, "result": result]) } }
        switch method {
        case "initialize":
            reply(["protocolVersion": (msg["params"] as? [String: Any])?["protocolVersion"] ?? "2024-11-05",
                   "capabilities": ["tools": [:]],
                   "serverInfo": ["name": "smooth-computer-use", "version": "2.0.0"]])
        case "tools/list":
            reply(["tools": tools])
        case "tools/call":
            let params = msg["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            let r = Router.run(name, args)
            var content: [[String: Any]] = [["type": "text", "text": r.text]]
            if let png = r.imagePNG { content.append(["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"]) }
            reply(["content": content, "isError": !r.ok])
        case "ping":
            reply([:])
        default:
            if id != nil { send(["jsonrpc": "2.0", "id": id!, "error": ["code": -32601, "message": "method not found"]]) }
        }
    }
}
