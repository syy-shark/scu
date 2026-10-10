---
name: scu
description: Operate any macOS app in the background like a human — read its UI, click buttons, type text (incl. Chinese), send chat messages, press shortcuts, scroll, take window screenshots — WITHOUT moving the user's real mouse or stealing focus, with a smooth Codex-style agent cursor overlay. Use whenever the user asks to control/operate/use a Mac app or website on their screen (WeChat/微信, Cursor, Chrome, Safari, Calculator, Notes, Finder, System Settings…), e.g. "帮我在微信发消息", "在 Chrome 打开 B 站点第一个视频", "click the Send button", "computer use", "scu".
---

# SCU (Smooth Computer Use)

Background computer-use for macOS. Everything goes through one command:

```bash
SKILL_DIR/cu <command> [args]
```

`SKILL_DIR` = the directory containing this SKILL.md (use its absolute path).
The first call compiles the native binary (~10 s, needs `swiftc` from Xcode
Command Line Tools) and starts a background daemon; later calls take ~0.1–0.5 s.

## First time only

```bash
SKILL_DIR/cu doctor
```

If Accessibility or Screen Recording is ❌, tell the user to open
**System Settings → Privacy & Security** and enable both for the app *you are
running in* (Antigravity / Cursor / Terminal), then restart that app. Do not
try to grant permissions yourself.

## Core loop (always follow it)

1. **Look** — `cu state "<App>"` prints the window's UI as a numbered list:
   `[12] Button "Send" @(x,y wxh) {press}`. Read it before acting.
2. **Act** — prefer element ids or visible titles over coordinates:
   - `cu click --app "<App>" --id 12`  or  `cu click --app "<App>" --title "Send"`
   - `cu type "text" --app "<App>" --id 7 --enter`  (click-to-focus, type, press Return)
3. **Verify** — run `cu state` again (ids may change after any UI change!) or
   `cu screenshot --app "<App>" --out /tmp/cu.png` and view the PNG.
4. Repeat. Never reuse stale ids after the UI changed — re-run `state`.

## Commands

| Goal | Command |
|---|---|
| Running apps | `cu apps` |
| UI tree | `cu state "<App>"` · only controls: `--interactive` · specific window: `--window "<title part>"` |
| Click element | `cu click --app A --id N` · `cu click --app A --title "text" [--role button]` |
| Right / double click | add `--right` / `--double` |
| Click coordinates | `cu click X Y --app A` (screen points, same space as `@(x,y)` in state) |
| Type text | `cu type "你好 hello" --app A [--id N \| --title T] [--clear] [--enter]` |
| Key / shortcut | `cu key "return" --app A` · `"cmd+a"` · `"cmd+shift+t"` · `"esc"` · `"down" --repeat 3` |
| Set field value | `cu set-value "42" --app A --id N` |
| Other AX action | `cu action ShowMenu --app A --id N` (context menu), `Increment`, `Confirm`… |
| Scroll | `cu scroll --app A --dy -400` (negative = down) · at element `--id N` · at point `X Y` |
| Hover / drag | `cu hover --app A --id N` · `cu drag X1 Y1 X2 Y2 --app A` |
| Open app / URL (background) | `cu open-app "Calculator"` · `cu open-url "https://…" --app "Google Chrome"` |
| Screenshot | `cu screenshot --app A --out /tmp/cu.png` (works even if the window is covered) |
| Stop daemon | `cu stop` |

App names: localized name, English name, bundle id or alias all work
(`微信`/`WeChat`, `Google Chrome`/`chrome`, `Cursor`, `计算器`/`Calculator`).
Global flags: `--no-cursor` (hide overlay), `--speed 1.5`.

## Recipes

**Send a chat message (WeChat / Cursor / Slack / Telegram…)**

*Fast keyboard route (WeChat / Slack, instant & zero-coordinate)*:
```bash
cu key "cmd+f" --app 微信
cu type "文件传输助手" --app 微信 --enter   # opens conversation & focuses message input
cu type "今天的报告写完了" --app 微信 --enter # submits directly
```

*Generic UI route (Cursor / Web / Discord)*:
```bash
cu state "<App>" --interactive             # find the contact or input box
cu click --app "<App>" --title "Contact"
cu state "<App>" --interactive             # find the message input id
cu type "Hello" --app "<App>" --id <input> --enter
```
For Cursor's chat: the input is usually `TextArea "Prompt"` → `cu type "…" --app Cursor --id <id> --enter`.

**Browser**
```bash
cu open-url "https://www.bilibili.com" --app "Google Chrome"
cu state "Google Chrome" --interactive   # links show url=…
cu click --app "Google Chrome" --id <link id>
```

## Rules

- Default mode is fully background: the user's real mouse never moves and the
  frontmost app never changes. Keep it that way. Only use
  `--mode foreground` on click if the user explicitly allows taking over.
- Don't send messages, delete things, pay, or submit forms the user didn't ask for.
  Confirm with the user before irreversible actions.
- Electron/Chromium apps (Cursor, VS Code, Slack, Chrome…) may need a moment to
  expose their UI the first time; if `state` shows only window chrome, run it again.
- If an element isn't in `state` (canvas-drawn UI), take a screenshot, find the
  point, and click by coordinates with `--app`.
- If a command fails with a permission error, run `cu doctor` and report.
