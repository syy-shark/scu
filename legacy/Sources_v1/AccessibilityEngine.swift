import Cocoa
import ApplicationServices
import CoreGraphics

// MARK: - Compact Indexed AX Element (Replicating TransformedUIElement)
public struct IndexedAXElement: CustomStringConvertible {
    public let index: Int
    public let role: String
    public let title: String
    public let value: String?
    public let frame: CGRect
    public let axElement: AXUIElement

    public var description: String {
        var str = "[\(index)] \(role)"
        if !title.isEmpty { str += " \"\(title)\"" }
        if let v = value, !v.isEmpty { str += " value=\"\(v)\"" }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        str += " @ (\(Int(center.x)), \(Int(center.y)))"
        return str
    }
}

// MARK: - Accessibility Engine
public final class AccessibilityEngine {
    public static let shared = AccessibilityEngine()
    private var lastElements: [IndexedAXElement] = []

    private init() {}

    // Check if Accessibility permissions are enabled
    public func checkPermission(promptIfNeeded: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // List all discoverable active GUI applications
    public func listRunningApps() -> [(name: String, bundleId: String, pid: pid_t)] {
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let name = app.localizedName, let bid = app.bundleIdentifier else { return nil }
                return (name, bid, app.processIdentifier)
            }
    }

    // Extract UI Accessibility Tree with flat integer indices
    public func inspectApp(named targetName: String) -> [IndexedAXElement] {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.localizedCaseInsensitiveContains(targetName) == true ||
            $0.bundleIdentifier?.localizedCaseInsensitiveContains(targetName) == true
        }) else {
            print("[-] App '\(targetName)' not found.")
            return []
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            print("[-] Could not retrieve windows for app '\(targetName)' (code: \(result.rawValue)).")
            return []
        }

        var collected: [IndexedAXElement] = []
        var currentIndex = 1

        for window in windows {
            collectElements(from: window, indexCounter: &currentIndex, into: &collected)
        }

        self.lastElements = collected
        return collected
    }

    private func collectElements(
        from element: AXUIElement,
        indexCounter: inout Int,
        into list: inout [IndexedAXElement]
    ) {
        // Extract basic attributes
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? "AXUnknown"

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        var title = (titleRef as? String) ?? ""
        if title.isEmpty {
            var descRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
            title = (descRef as? String) ?? ""
        }

        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let value = (valueRef as? String)

        // Extract Frame Coordinates
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        var frame = CGRect.zero
        if let posVal = positionRef, let sizeVal = sizeRef,
           CFGetTypeID(posVal) == AXValueGetTypeID(),
           CFGetTypeID(sizeVal) == AXValueGetTypeID() {
            var pt = CGPoint.zero
            var sz = CGSize.zero
            AXValueGetValue(posVal as! AXValue, .cgPoint, &pt)
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &sz)
            frame = CGRect(origin: pt, size: sz)
        }

        // Filter and retain interactable elements (Buttons, TextFields, Links, Checkboxes, etc.)
        let interactableRoles: Set<String> = [
            kAXButtonRole as String,
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXPopUpButtonRole as String,
            kAXCheckBoxRole as String,
            kAXRadioButtonRole as String,
            "AXLink",
            kAXMenuItemRole as String,
            "AXTabButton",
            kAXSliderRole as String
        ]
        let isInteractable = interactableRoles.contains(role) || !title.isEmpty

        if isInteractable && frame.width > 2 && frame.height > 2 {
            let item = IndexedAXElement(
                index: indexCounter,
                role: role,
                title: title,
                value: value,
                frame: frame,
                axElement: element
            )
            list.append(item)
            indexCounter += 1
        }

        // Recursively traverse children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                collectElements(from: child, indexCounter: &indexCounter, into: &list)
            }
        }
    }

    // Direct semantic click via Accessibility Action
    public func performAXClick(on element: IndexedAXElement) -> Bool {
        let err = AXUIElementPerformAction(element.axElement, kAXPressAction as CFString)
        return err == .success
    }

    // Type text into an element or current focus
    public func typeText(_ text: String, into element: IndexedAXElement? = nil) {
        if let elem = element {
            // Direct semantic value replacement (instant, no typing delay)
            AXUIElementSetAttributeValue(elem.axElement, kAXValueAttribute as CFString, text as CFTypeRef)
        } else {
            // Synthesize key strokes via CGEvent
            for char in text {
                let utf16Chars = Array(String(char).utf16)
                guard let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                      let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { continue }
                
                downEvent.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
                upEvent.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
                
                downEvent.post(tap: .cghidEventTap)
                usleep(8000) // 8ms natural human cadence
                upEvent.post(tap: .cghidEventTap)
                usleep(12000)
            }
        }
    }
}
