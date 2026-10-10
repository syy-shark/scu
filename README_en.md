<div align="center">

[简体中文](README.md) · **English**

# SCU

### Non-intrusive, display-synchronized computer control engine for macOS agents.

**Engineered as a native Skill for Google Antigravity and Cursor.**

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?style=flat-square&logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/language-Swift%205-F05138?style=flat-square&logo=swift&logoColor=white)](#requirements)
[![Interface](https://img.shields.io/badge/interface-Agent%20Skill-5c4ee5?style=flat-square)](#quick-start)
[![License](https://img.shields.io/badge/license-MIT-f4c430?style=flat-square)](LICENSE)

[Quick start](#quick-start) · [Core characteristics](#core-characteristics) · [Architecture](#architecture) · [Command reference](#command-reference) · [Requirements](#requirements) · [Limitations](#limitations)

</div>

---

Conventional visual Computer Use mechanisms seize the user's hardware pointer, steal frontmost focus, and introduce jarring coordinate snapping. Any user interaction concurrent with an agent invocation results in race conditions and missed clicks.

**SCU (Smooth Computer Use)** decouples the agent's actions from physical hardware input. Built directly against macOS private graphics subsystems (`SkyLight`) and semantic accessibility primitives (`AXUIElement`), it executes complete desktop control workflows entirely in the background while rendering an independent, display-synchronized virtual cursor overlay.

The repository is structured as a self-contained Agent Skill: cloning it into your agent's skill path provides immediate capability without external runtime dependencies.

---

## Core characteristics

| Dimension | Mechanism | Guarantee |
|---|---|---|
| Hardware Pointer Decoupling | Process-isolated input routing (`SLEventPostToPid`) | The physical mouse pointer remains completely undisturbed. |
| Window Focus Isolation | Window-targeted synthetic activation (`SLPSPostEventRecordTo`) | Target windows receive input without window raising or stealing active workspace focus. |
| Hit Precision | Semantic execution first (`AXPress`), validated local coordinates second | Zero coordinate guessing; hits are verified against accessibility frame boundaries. |
| Visual Continuity | `CADisplayLink` hardware v-sync + minimum-jerk trajectory planning | Agent cursor moves along natural cubic paths with inertial tilt and spring physics. |
| Text & Dispatch | Chunked Unicode key events + synthetic focus recovery | Instant Chinese and Latin text input; single-step text entry and submission (`--enter`). |
| Deterministic Latency | Strict per-element messaging timeouts (250 ms) and 10 s call bounds | Immune to Electron / Chromium accessibility tree hangs; UI parsing completes in <0.5 s. |
| Self-bootstrapping | Native Swift architecture with an automated `cu` bootstrap wrapper | Zero Python / Node / pip dependencies; compiles on first invocation automatically. |

---

## Quick start

### 1. Register with your agent

Send the corresponding instruction block directly to your agent in chat.

#### For Google Antigravity

```text
Please install the SCU (Smooth Computer Use) skill:
1. Clone https://github.com/syy-shark/scu to ~/.gemini/config/skills/scu
2. Run ~/.gemini/config/skills/scu/cu doctor to verify permissions.
```

#### For Cursor

```text
Please install the SCU (Smooth Computer Use) skill:
1. Clone https://github.com/syy-shark/scu to ~/.cursor/skills/scu
2. Run ~/.cursor/skills/scu/cu doctor to verify permissions.
```

> **Shared installation**: If using both environments, clone to one path and link to the other:
> ```bash
> ln -s ~/.gemini/config/skills/scu ~/.cursor/skills/scu
> ```

---

### 2. Grant macOS privacy permissions

Open **System Settings -> Privacy & Security** and confirm that the host application running your agent (**Antigravity**, **Cursor**, or your **Terminal**) is enabled under:

- **Accessibility**: Required for accessibility hierarchy inspection, semantic actions, and per-process key injection.
- **Screen Recording**: Required for background window frame captures and coordinate fallbacks.

Restart the host application after modifying permission toggles.

*Tip*: Add the `cu` executable to your agent tool auto-allow list to prevent interactive approval prompts on each execution step.

---

### 3. Usage examples

Once registered, instruct your agent using natural language:

```text
Open Calculator and calculate 2026 * 42.
```

```text
In Google Chrome, navigate to bilibili.com, scroll down, and open the first video.
```

```text
In WeChat, select "File Transfer" and send: "Deployment verification complete."
```

```text
Focus Cursor chat input and submit: "Review src/engine for potential memory leaks."
```

```text
Capture a background screenshot of Safari and describe the content of the active tab.
```

The agent executes the loop defined in `SKILL.md`: `Inspect UI state -> Locate element identifier -> Execute atomic action -> Verify outcome`.

---

## Architecture

```
Agent Environment (Antigravity / Cursor)
      │
      │  Executes skill command
      ▼
   cu wrapper (Auto-builds native binary on first use)
      │
      │  Local domain socket (/tmp/smooth-cu-<uid>.sock)
      ▼
smooth-computer-use daemon (Persistent daemon, idle-terminates after 30 min)
   ├── Accessibility Engine (AXEngine)
   │     ├── Fast tree snapshot with AXManualAccessibility priming
   │     ├── Element search and verified boundary hit-testing
   │     └── Direct semantic action execution (AXPress, AXScrollToVisible)
   ├── Background Input Dispatcher (SkyLight SPIs)
   │     ├── Process-isolated mouse down/up/drag via SLEventPostToPid
   │     ├── Synthetic window focus preservation without z-order changes
   │     └── Chunked Unicode key injection & modifier chord translation
   └── Cursor Overlay Subsystem
         ├── Multi-display click-through overlay windows at .screenSaver level
         ├── CADisplayLink 60/120 Hz render pump
         └── Minimum-jerk motion curves, inertial banking, and spring dynamics
```

### Action delivery ladder

Actions execute down a strict degradation hierarchy to guarantee safety:

1. **Semantic Execution (`AXPress`)**: Resolves the element in the accessibility graph and triggers its action handler directly. Instantaneous, zero coordinate drift.
2. **Background Process-Targeted Synthesized Events**: When an element does not implement semantic actions, the engine locates the target window, verifies coordinates with a hit-test, establishes a synthetic focus frame, and injects window-local events via private SkyLight SPIs.
3. **Foreground Event Fallback**: Available only when explicitly requested (`--mode foreground`). Never invoked by default.

---

## Command reference

The agent communicates with the daemon via the `cu` binary. All commands can also be invoked directly from the terminal:

```bash
# State inspection
cu apps                                         # List running applications and window ownership
cu state "Google Chrome" --interactive          # Numbered UI control tree (compact interactive mode)
cu state Cursor --window "smooth-computer-use"  # Inspect a specific window title
cu screenshot --app Safari --out /tmp/win.png   # Background window screenshot (works when covered)
cu doctor                                       # Permission and display diagnostic audit

# Target interaction
cu click --app Calculator --title "7"           # Semantic or coordinate click by label
cu click --app "Google Chrome" --id 18          # Click element by index from `cu state`
cu click 450 320 --app Slack                    # Click window-relative screen coordinates
cu click --app Finder --id 4 --double           # Double-click target
cu click --app Notes --id 12 --right            # Context click (right click)

# Text & keyboard entry
cu type "Hello world" --app Notes --id 3        # Focus target and type text
cu type "npm test" --app Cursor --id 48 --enter # Type text and dispatch Return key
cu key "cmd+l" --app "Google Chrome"            # Dispatch key combination
cu key "down" --app "Google Chrome" --repeat 5  # Repeated navigation key dispatch
cu set-value "100" --app Settings --id 9        # Direct accessibility value override

# Layout & gestures
cu scroll --app "Google Chrome" --dy -400       # Vertical scroll (-down / +up)
cu drag 200 300 600 300 --app Keynote           # Drag from coordinate A to coordinate B
cu hover --app "Google Chrome" --id 14          # Trigger hover states

# Motion & server lifecycle
cu demo                                         # Trajectory and spring animation visual demonstration
cu stop                                         # Terminate running background daemon
```

**Global flags**:
- `--no-cursor`: Suppress the visual virtual cursor overlay.
- `--speed <float>`: Multiplier for trajectory movement speed (default: `1.0`).

---

## Requirements

- **Operating System**: macOS 14.0 (Sonoma) or later (Apple Silicon & Intel supported).
- **Toolchain**: Xcode Command Line Tools (`xcode-select --install`).
- **Dependencies**: None. Pure Swift utilizing ApplicationServices, CoreGraphics, Cocoa, and ScreenCaptureKit.

---

## Limitations

- Pure Canvas / WebGL surfaces: Applications rendering through raw bitmap canvas without exposing accessibility trees cannot provide semantic node IDs. Interaction must fall back to coordinate clicks derived from screenshots.
- Chromium scroll semantics: Chromium drops background wheel events at the compositor layer on macOS. Scrolling in Chromium targets is fulfilled via background key sequences or `AXScrollToVisible` element traversal.
- Drag & Drop: Drag fidelity across distinct process boundaries is subject to target application synthetic drop recognition.

---

## Acknowledgments

- Architectural concepts inspired by reverse-engineering analysis of modern desktop agent runners.
- Event routing and synthetic focus mechanisms informed by open research in [trycua/cua](https://github.com/trycua/cua) (MIT) and [yabai](https://github.com/koekeishiya/yabai) (MIT).

---

## License

[MIT](LICENSE) © 2026 syy-shark
