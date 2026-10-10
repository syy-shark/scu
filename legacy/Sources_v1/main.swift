import Cocoa
import Foundation

// Initialize NSApplication for GUI overlay support
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let args = CommandLine.arguments

func printUsage() {
    print("""
    ✨ Smooth Computer Use Engine (Codex CUA Replica) ✨
    Usage:
      smooth-computer-use play                     Run full autonomous multi-app showcase (Calculator + Chrome)
      smooth-computer-use bilibili                 Run continuous Bilibili browsing session (single overlay)
      smooth-computer-use demo                     Run visual cursor physics & animation demo
      smooth-computer-use move <x> <y>             Glide cursor smoothly to (x, y) with Bezier curve
      smooth-computer-use click <x> <y>            Glide to (x, y) and click with ripple animation
      smooth-computer-use apps                     List running GUI applications
      smooth-computer-use tree <AppName>           Inspect app accessibility tree with integer IDs
      smooth-computer-use click-elem <App> <index> Glide to indexed UI element and click it
      smooth-computer-use type "<text>"            Type text into active focus
      smooth-computer-use scroll <dy>              Smooth momentum trackpad scroll
    """)
}

if args.count < 2 {
    printUsage()
    exit(0)
}

let command = args[1].lowercased()

switch command {
case "apps":
    let apps = AccessibilityEngine.shared.listRunningApps()
    print("📱 Running GUI Applications (\(apps.count)):")
    for a in apps {
        print("  • \(a.name) (pid: \(a.pid), id: \(a.bundleId))")
    }
    exit(0)

case "tree":
    guard args.count >= 3 else {
        print("Usage: smooth-computer-use tree <AppName>")
        exit(1)
    }
    let target = args[2]
    if !AccessibilityEngine.shared.checkPermission(promptIfNeeded: true) {
        print("⚠️ Warning: Accessibility permission not granted. Prompting user in System Settings...")
    }
    let elements = AccessibilityEngine.shared.inspectApp(named: target)
    print("🌲 Accessibility Tree for '\(target)' (\(elements.count) elements):")
    for elem in elements {
        print("  \(elem)")
    }
    exit(0)

case "demo":
    print("🚀 Starting Silky-Smooth Virtual Cursor Demo...")
    print("Observe the screen: Bezier curvature, squash & stretch acceleration, dynamic tilt, and click ripple!")
    
    let engine = SmoothCursorEngine.shared
    guard let screen = NSScreen.main else { exit(1) }
    let w = screen.frame.width
    let h = screen.frame.height

    // Trajectory waypoints
    let waypoints = [
        CGPoint(x: w * 0.2, y: h * 0.7),
        CGPoint(x: w * 0.8, y: h * 0.75),
        CGPoint(x: w * 0.65, y: h * 0.3),
        CGPoint(x: w * 0.25, y: h * 0.35),
        CGPoint(x: w * 0.5, y: h * 0.5)
    ]

    var currentStep = 0
    func stepNext() {
        if currentStep >= waypoints.count {
            print("✅ Demo finished. Exiting.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(0)
            }
            return
        }

        let target = waypoints[currentStep]
        print("  -> Gliding smoothly to waypoint \(currentStep + 1): (\(Int(target.x)), \(Int(target.y)))")
        currentStep += 1

        engine.move(to: target) {
            engine.click(at: target, injectCGEvent: false) {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
                    stepNext()
                }
            }
        }
    }

    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
        stepNext()
    }

    app.run()

case "move":
    guard args.count >= 4, let x = Double(args[2]), let y = Double(args[3]) else {
        print("Usage: smooth-computer-use move <x> <y>")
        exit(1)
    }
    let target = CGPoint(x: x, y: y)
    SmoothCursorEngine.shared.move(to: target) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exit(0)
        }
    }
    app.run()

case "click":
    guard args.count >= 4, let x = Double(args[2]), let y = Double(args[3]) else {
        print("Usage: smooth-computer-use click <x> <y>")
        exit(1)
    }
    let target = CGPoint(x: x, y: y)
    SmoothCursorEngine.shared.click(at: target, injectCGEvent: true) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exit(0)
        }
    }
    app.run()

case "click-elem":
    guard args.count >= 4, let idx = Int(args[3]) else {
        print("Usage: smooth-computer-use click-elem <AppName> <Index>")
        exit(1)
    }
    let appName = args[2]
    let elements = AccessibilityEngine.shared.inspectApp(named: appName)
    guard let element = elements.first(where: { $0.index == idx }) else {
        print("[-] Element with index \(idx) not found in '\(appName)'.")
        exit(1)
    }

    let elementCenter = CGPoint(
        x: element.frame.midX,
        y: element.frame.midY
    )

    print("🎯 Found \(element.role) \"\(element.title)\" at (\(Int(elementCenter.x)), \(Int(elementCenter.y)))")
    print("✈️ Gliding smoothly to element...")
    SmoothCursorEngine.shared.click(at: elementCenter, injectCGEvent: true) {
        print("✅ Clicked element [\(idx)].")
        exit(0)
    }
    app.run()

case "type":
    guard args.count >= 3 else {
        print("Usage: smooth-computer-use type \"<text>\"")
        exit(1)
    }
    let text = args[2]
    print("⌨️ Typing: \"\(text)\"")
    AccessibilityEngine.shared.typeText(text)
    print("✅ Typed.")
    exit(0)

case "scroll":
    let dy = args.count >= 3 ? (Int(args[2]) ?? -300) : -300
    print("📜 Smooth scrolling by \(dy) pixels...")
    SmoothCursorEngine.shared.smoothScroll(dy: dy) {
        print("✅ Scroll complete.")
        exit(0)
    }
    app.run()

case "play":
    print("🎮 Starting Full Autonomous Multi-App Computer Use Demonstration...")
    print("✨ Featuring: Official OpenAI Codex Vector Cursor + Continuous Physics Overlay")
    let engine = SmoothCursorEngine.shared

    // Step 1: Open Calculator
    print("🧮 [Stage 1] Launching and operating macOS Calculator...")
    let openCalc = Process()
    openCalc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    openCalc.arguments = ["-a", "Calculator"]
    try? openCalc.run()
    openCalc.waitUntilExit()
    Thread.sleep(forTimeInterval: 0.8)

    // Dynamically find Calculator buttons via Accessibility Tree
    let calcElements = AccessibilityEngine.shared.inspectApp(named: "Calculator")
    func getCalcElem(_ title: String) -> IndexedAXElement? {
        return calcElements.first(where: { $0.title == title })
    }

    func makeStep(for title: String, fallback: CGPoint) -> CursorFlowStep {
        if let el = getCalcElem(title) {
            return .axClick(element: el)
        }
        return .click(at: fallback, preserveUserMouse: true)
    }

    let stepAC = makeStep(for: "全部清除", fallback: CGPoint(x: 1060, y: 357))
    let step2 = makeStep(for: "2", fallback: CGPoint(x: 1060, y: 519))
    let step0 = makeStep(for: "0", fallback: CGPoint(x: 1060, y: 573))
    let step6 = makeStep(for: "6", fallback: CGPoint(x: 1114, y: 465))
    let stepMul = makeStep(for: "乘", fallback: CGPoint(x: 1168, y: 411))
    let step4 = makeStep(for: "4", fallback: CGPoint(x: 1006, y: 465))
    let stepEq = makeStep(for: "等于", fallback: CGPoint(x: 1168, y: 573))

    let calcSteps: [CursorFlowStep] = [
        .hover(duration: 0.3),
        stepAC,
        .hover(duration: 0.25),
        step2,
        .hover(duration: 0.2),
        step0,
        .hover(duration: 0.2),
        step2,
        .hover(duration: 0.2),
        step6,
        .hover(duration: 0.25),
        stepMul,
        .hover(duration: 0.25),
        step4,
        .hover(duration: 0.2),
        step2,
        .hover(duration: 0.25),
        stepEq,
        .hover(duration: 1.5) // Display result 85092!
    ]

    let chromeSteps: [CursorFlowStep] = [
        .move(to: CGPoint(x: 855, y: 220)),
        .hover(duration: 0.4),
        .move(to: CGPoint(x: 520, y: 500)),
        .hover(duration: 0.45),
        .move(to: CGPoint(x: 860, y: 500)),
        .hover(duration: 0.45),
        .scroll(dy: -420, duration: 0.6),
        .hover(duration: 0.35),
        .move(to: CGPoint(x: 860, y: 520)),
        .hover(duration: 0.3),
        .click(at: CGPoint(x: 860, y: 520)),
        .hover(duration: 2.2),
        .move(to: CGPoint(x: 750, y: 480)),
        .hover(duration: 0.5),
        .scroll(dy: -280, duration: 0.5),
        .move(to: CGPoint(x: 1360, y: 540)),
        .hover(duration: 0.8)
    ]

    print("🚀 Running Stage 1: Calculating 2026 × 42 on Calculator with silky clicks...")
    engine.setPosition(CGPoint(x: 855, y: 500))
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
        engine.executeFlow(steps: calcSteps) {
            print("🌐 [Stage 2] Seamlessly switching to Google Chrome for web exploration...")
            if let script = NSAppleScript(source: "tell application \"Google Chrome\" to activate") {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
            }
            Thread.sleep(forTimeInterval: 0.5)

            engine.executeFlow(steps: chromeSteps) {
                print("🎉 Multi-App Computer Use Demonstration completed flawlessly!")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    exit(0)
                }
            }
        }
    }
    app.run()

case "bilibili":
    print("🎬 Starting Ultra-Smooth Continuous Bilibili Browsing Session...")
    print("✨ Using VisionOS/Apple-style liquid glass pointer with continuous single-overlay physics.")
    let engine = SmoothCursorEngine.shared

    // Activate Google Chrome
    if let script = NSAppleScript(source: "tell application \"Google Chrome\" to activate") {
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }

    // Set starting position at natural top header
    engine.setPosition(CGPoint(x: 850, y: 220))

    let steps: [CursorFlowStep] = [
        // 1. Smoothly glide to first video recommendation (Row 1, Col 2)
        .move(to: CGPoint(x: 520, y: 500)),
        .hover(duration: 0.5),

        // 2. Smooth arc curve to second video recommendation (Row 1, Col 3)
        .move(to: CGPoint(x: 860, y: 500)),
        .hover(duration: 0.5),

        // 3. Smooth arc curve to third video recommendation (Row 1, Col 4)
        .move(to: CGPoint(x: 1200, y: 500)),
        .hover(duration: 0.4),

        // 4. Momentum trackpad scroll down the feed to reveal fresh content
        .scroll(dy: -420, duration: 0.6),
        .hover(duration: 0.3),

        // 5. Glide onto the newly revealed recommended video card
        .move(to: CGPoint(x: 860, y: 520)),
        .hover(duration: 0.35),

        // 6. Accurate, decisive click with neon shockwave ripple!
        .click(at: CGPoint(x: 860, y: 520)),

        // 7. Watch page loading wait
        .hover(duration: 2.5),

        // 8. Glide to video player area
        .move(to: CGPoint(x: 750, y: 480)),
        .hover(duration: 0.6),

        // 9. Scroll slightly down the video player to view comments/related
        .scroll(dy: -280, duration: 0.5),
        .hover(duration: 0.4),

        // 10. Hover over the next recommended video card on the right
        .move(to: CGPoint(x: 1360, y: 540)),
        .hover(duration: 0.8)
    ]

    print("✈️ Executing \(steps.count) continuous flow steps in a single overlay session...")
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
        engine.executeFlow(steps: steps) {
            print("🎉 Bilibili Smooth Computer Use session finished flawlessly!")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                exit(0)
            }
        }
    }
    app.run()

default:
    printUsage()
    exit(1)
}
