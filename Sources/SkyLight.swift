import Foundation
import CoreGraphics
import ApplicationServices
import Darwin

// MARK: - SkyLight / HIServices private SPI bridge
//
// Codex's SkyComputerUseService resolves its window-server SPIs at runtime via
// dlopen/dlsym (its import table has no CGEventPost* at all). We do the same so
// the binary keeps working (with graceful fallbacks) if Apple removes a symbol.
//
// Techniques (background, pointer-preserving delivery) are documented publicly
// by yabai (MIT) and trycua/cua-driver (MIT); this is an independent Swift port.

enum SkyLight {
    private static let skyLightHandle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_GLOBAL)

    /// RTLD_DEFAULT on Darwin is ((void *)-2)
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    static func symbol<T>(_ names: String..., as type: T.Type) -> T? {
        _ = skyLightHandle
        for name in names {
            if let p = dlsym(rtldDefault, name) {
                return unsafeBitCast(p, to: T.self)
            }
        }
        return nil
    }

    // MARK: Function types
    typealias PostToPidFn = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Void
    typealias SetIntFieldFn = @convention(c) (UnsafeMutableRawPointer, UInt32, Int64) -> Void
    typealias SetWindowLocationFn = @convention(c) (UnsafeMutableRawPointer, CGPoint) -> Void
    typealias SetAuthMessageFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void
    typealias MainConnectionFn = @convention(c) () -> UInt32
    typealias PostEventRecordToFn = @convention(c) (UnsafeRawPointer, UnsafePointer<UInt8>) -> Int32
    typealias GetFrontProcessFn = @convention(c) (UnsafeMutableRawPointer) -> Int32
    typealias GetWindowOwnerFn = @convention(c) (UInt32, UInt32, UnsafeMutablePointer<UInt32>) -> Int32
    typealias GetConnectionPSNFn = @convention(c) (UInt32, UnsafeMutableRawPointer) -> Int32
    typealias GetProcessForPIDFn = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    typealias AuthFactoryFn = @convention(c) (AnyClass, Selector, UnsafeMutableRawPointer, Int32, UInt32) -> Unmanaged<AnyObject>?

    static let postToPid = symbol("SLEventPostToPid", as: PostToPidFn.self)
    static let setIntField = symbol("SLEventSetIntegerValueField", as: SetIntFieldFn.self)
    static let setWindowLocation = symbol("CGEventSetWindowLocation", "SLEventSetWindowLocation", as: SetWindowLocationFn.self)
    static let setAuthMessage = symbol("SLEventSetAuthenticationMessage", as: SetAuthMessageFn.self)
    static let mainConnection = symbol("SLSMainConnectionID", "CGSMainConnectionID", as: MainConnectionFn.self)
    static let postEventRecordTo = symbol("SLPSPostEventRecordTo", as: PostEventRecordToFn.self)
    static let getFrontProcess = symbol("_SLPSGetFrontProcess", as: GetFrontProcessFn.self)
    static let getWindowOwner = symbol("SLSGetWindowOwner", as: GetWindowOwnerFn.self)
    static let getConnectionPSN = symbol("SLSGetConnectionPSN", as: GetConnectionPSNFn.self)
    static let getProcessForPID = symbol("GetProcessForPID", as: GetProcessForPIDFn.self)
    static let axGetWindow = symbol("_AXUIElementGetWindow", as: AXGetWindowFn.self)
    static let objcMsgSend = symbol("objc_msgSend", as: AuthFactoryFn.self)

    static var isAvailable: Bool { postToPid != nil }
    static var canFocusWithoutRaise: Bool {
        postEventRecordTo != nil && getFrontProcess != nil &&
            ((mainConnection != nil && getWindowOwner != nil && getConnectionPSN != nil) || getProcessForPID != nil)
    }

    // MARK: Event helpers

    static func ptr(_ event: CGEvent) -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(event).toOpaque()
    }

    /// Stamp a raw (possibly undocumented) integer field.
    static func setField(_ event: CGEvent, _ field: UInt32, _ value: Int64) {
        if let f = setIntField {
            f(ptr(event), field, value)
        } else if let known = CGEventField(rawValue: field) {
            event.setIntegerValueField(known, value: value)
        }
    }

    static func stampWindowLocation(_ event: CGEvent, _ point: CGPoint) {
        setWindowLocation?(ptr(event), point)
    }

    /// Extract the embedded SLSEventRecord* from a CGEvent (layout: CFRuntimeBase, uint32, record*).
    private static func eventRecord(_ event: CGEvent) -> UnsafeMutableRawPointer? {
        let base = UnsafeRawPointer(ptr(event))
        for offset in [24, 32, 16] {
            if let p = base.load(fromByteOffset: offset, as: UnsafeMutableRawPointer?.self) {
                return p
            }
        }
        return nil
    }

    /// Attach an SLSEventAuthenticationMessage (macOS 15+) so Chromium-class
    /// targets accept a synthetic keyboard event as live input.
    private static func attachAuthentication(_ event: CGEvent, pid: pid_t) {
        guard let cls = NSClassFromString("SLSEventAuthenticationMessage"),
              let msgSend = objcMsgSend, let setAuth = setAuthMessage else { return }
        let sel = NSSelectorFromString("messageWithEventRecord:pid:version:")
        guard class_respondsToSelector(object_getClass(cls), sel),
              let record = eventRecord(event),
              let msg = msgSend(cls, sel, record, Int32(pid), 0) else { return }
        setAuth(ptr(event), msg.toOpaque())
    }

    /// Deliver an event straight into a process's event queue. Never touches the
    /// hardware cursor and never changes the frontmost application.
    static func post(_ event: CGEvent, to pid: pid_t, authenticate: Bool = false, alsoPublic: Bool = false) {
        if let f = postToPid {
            if authenticate { attachAuthentication(event, pid: pid) }
            f(pid, ptr(event))
            if alsoPublic { event.postToPid(pid) }
        } else {
            event.postToPid(pid)
        }
    }

    // MARK: Process serial numbers

    typealias PSN = (UInt32, UInt32)

    static func frontProcess() -> PSN? {
        guard let f = getFrontProcess else { return nil }
        var psn: PSN = (0, 0)
        let ok = withUnsafeMutableBytes(of: &psn) { f($0.baseAddress!) } == 0
        return ok ? psn : nil
    }

    static func psn(forWindow wid: CGWindowID, pid: pid_t) -> PSN? {
        var psn: PSN = (0, 0)
        if let main = mainConnection, let owner = getWindowOwner, let connPSN = getConnectionPSN, wid != 0 {
            var ownerCID: UInt32 = 0
            if owner(main(), wid, &ownerCID) == 0, ownerCID != 0 {
                let ok = withUnsafeMutableBytes(of: &psn) { connPSN(ownerCID, $0.baseAddress!) } == 0
                if ok { return psn }
            }
        }
        if let byPid = getProcessForPID {
            let ok = withUnsafeMutableBytes(of: &psn) { byPid(pid, $0.baseAddress!) } == 0
            if ok { return psn }
        }
        return nil
    }

    private static func focusRecord(window wid: CGWindowID, focus: Bool) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 0xF8)
        buf[0x04] = 0xF8
        buf[0x08] = 0x0D
        withUnsafeBytes(of: wid.littleEndian) { raw in
            for i in 0..<4 { buf[0x3C + i] = raw[i] }
        }
        buf[0x8A] = focus ? 0x01 : 0x02
        return buf
    }

    private static func post(record: [UInt8], to psn: PSN) -> Bool {
        guard let f = postEventRecordTo else { return false }
        var p = psn
        return withUnsafeBytes(of: &p) { psnRaw in
            record.withUnsafeBufferPointer { f(psnRaw.baseAddress!, $0.baseAddress!) }
        } == 0
    }

    /// Make `wid` the key window of its (background) app from AppKit's point of
    /// view, WITHOUT raising it and WITHOUT changing the frontmost app.
    /// Returns the PSN that was defocused so the caller can hand focus back.
    @discardableResult
    static func focusWithoutRaise(pid: pid_t, window wid: CGWindowID) -> PSN? {
        guard canFocusWithoutRaise, let front = frontProcess(),
              let target = psn(forWindow: wid, pid: pid) else { return nil }
        if front == target { return nil }
        _ = post(record: focusRecord(window: wid, focus: false), to: front)
        _ = post(record: focusRecord(window: wid, focus: true), to: target)
        return front
    }

    /// Undo `focusWithoutRaise`: defocus the target window and re-key the user's
    /// own window so their typing focus is exactly where they left it.
    static func restoreFocus(previous: PSN, previousWindow: CGWindowID, targetPid: pid_t, targetWindow: CGWindowID) {
        if let target = psn(forWindow: targetWindow, pid: targetPid) {
            _ = post(record: focusRecord(window: targetWindow, focus: false), to: target)
        }
        _ = post(record: focusRecord(window: previousWindow, focus: true), to: previous)
    }

    // MARK: AX <-> CGWindowID

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let f = axGetWindow else { return nil }
        var wid: CGWindowID = 0
        return f(element, &wid) == .success && wid != 0 ? wid : nil
    }
}
