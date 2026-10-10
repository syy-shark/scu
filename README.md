# 🖱️ Smooth Computer Use

**专为 Antigravity 和 Cursor 准备的 macOS Computer Use（电脑操控）MCP 服务。**

让你的 AI 直接操作 Mac 上的任何 App——点按钮、打字、发消息、滚动、截图——
**全程在后台进行：不抢你的鼠标、不切走你的前台窗口**，你可以一边继续干活，一边看着一个 Codex 风格的半透明小箭头在屏幕上丝滑地帮你操作。

> 原生 Swift 编写，单个二进制，无 Python / Node 依赖，所有操作都在本机完成。

---

## ✨ 特点

| | |
|---|---|
| 🙅 **不抢鼠标** | 事件直接投递给目标进程（per-pid），你的真实鼠标指针纹丝不动；目标窗口被挡住也能点 |
| 🎯 **点得准** | 优先走无障碍语义（AXPress），按元素编号点击而不是猜坐标；必须用坐标时先做命中测试校验 |
| 🧈 **够丝滑** | 独立的虚拟光标浮层，跟随屏幕刷新率（CADisplayLink）绘制，最小加加速度轨迹 + 弹簧动画 |
| ⌨️ **能打字发消息** | 对 Cursor / Chrome / 微信等支持中文输入，`submit=true` 一步「输入 + 回车发送」 |
| ⚡ **快** | 读取 Cursor 整个界面约 0.4 秒；每次调用最多 10 秒，绝不卡死 |
| 🔌 **即插即用** | 标准 MCP（stdio），Antigravity / Cursor 填一段配置即可 |

---

## 🚀 最简单的用法：直接告诉你的 AI

### 第 1 步：一句话安装

把下面这段话**原样复制**发给你的 Antigravity 或 Cursor：

```text
请帮我安装 Smooth Computer Use：
1. 把 https://github.com/syy-shark/smooth-computer-use 克隆到 ~/smooth-computer-use
2. 进入目录运行 ./build.sh 编译
3. 运行 ./smooth-computer-use doctor 检查权限，告诉我缺哪些权限
4. 把它作为 MCP 服务器加入你的 MCP 配置，名字叫 computer-use，
   command 是 ~/smooth-computer-use/smooth-computer-use 的绝对路径，args 是 ["mcp"]
完成后告诉我需要怎么重启/刷新 MCP。
```

### 第 2 步：授权（只需一次）

打开「系统设置 → 隐私与安全性」，给**你正在用的那个 App**（Antigravity 或 Cursor）勾上：

- ✅ **辅助功能**（Accessibility）——用于读取界面、点击、打字
- ✅ **屏幕录制**（Screen Recording）——用于截图

勾完后**重启 Antigravity / Cursor**。

### 第 3 步：直接说你想干什么

```text
用 computer-use 打开计算器，帮我算 2026 × 42
```
```text
用 computer-use 在 Chrome 里打开 B 站，往下滑，点开第一个视频
```
```text
用 computer-use 在微信里找到「文件传输助手」，发一句：今天的报告写完了
```
```text
用 computer-use 在 Cursor 的聊天框里发：帮我检查一下 src 目录的类型错误
```
```text
用 computer-use 截一张 Safari 窗口的图，告诉我页面上写了什么
```

AI 会自己先读界面（`get_app_state`）→ 找到元素编号 → 点击 / 输入 / 发送，你在旁边看着就行。

---

## 🔧 手动安装

**要求**：macOS 14+（Apple Silicon 或 Intel），Xcode Command Line Tools（`xcode-select --install`）。

```bash
git clone https://github.com/syy-shark/smooth-computer-use.git ~/smooth-computer-use
cd ~/smooth-computer-use
./build.sh
./smooth-computer-use doctor     # 检查权限，全部 ✅ 即可
```

### 接入 Antigravity

Agent 面板 → `…` → **MCP Servers** → **Manage MCP Servers** → **View raw config**，加入：

```json
{
  "mcpServers": {
    "computer-use": {
      "command": "/Users/你的用户名/smooth-computer-use/smooth-computer-use",
      "args": ["mcp"]
    }
  }
}
```

### 接入 Cursor

写入 `~/.cursor/mcp.json`（全局）或项目里的 `.cursor/mcp.json`，内容同上。
然后在 **Settings → MCP** 里确认 `computer-use` 亮绿灯。

> ⚠️ `command` 必须是**绝对路径**。更新代码重新 `./build.sh` 后，记得在 MCP 设置里把它关掉再打开一次。

---

## 🧰 提供给 AI 的工具（MCP Tools）

| 工具 | 作用 |
|---|---|
| `list_apps` | 列出正在运行的 App |
| `get_app_state` | 读取某个 App 窗口的界面结构，每个元素带编号 `[id]` |
| `click` | 按元素编号 / 文字 / 坐标点击（支持右键、双击） |
| `type_text` | 输入文字（支持中文），`submit=true` 输入后自动回车发送 |
| `press_key` | 按键 / 快捷键，如 `return`、`cmd+a`、`cmd+shift+t` |
| `set_value` | 直接设置输入框、滑块等的值 |
| `scroll` | 滚动（Chromium/Electron 走后台按键，原生 App 走滚轮） |
| `drag` | 拖拽 |
| `hover` | 悬停 |
| `perform_secondary_action` | 其他无障碍动作，如 `ShowMenu`（右键菜单） |
| `open_app` / `open_url` | 在后台打开 App / 网址，不抢前台 |
| `screenshot` | 截取 App 窗口（被挡住也能截）或整个屏幕 |
| `wait` | 等待界面加载 |

---

## 💻 命令行（可选）

不通过 AI 也可以直接用：

```bash
./smooth-computer-use apps                                   # 运行中的 App
./smooth-computer-use state "Google Chrome"                  # 带编号的界面树
./smooth-computer-use click --app Calculator --title "7"     # 按文字点击
./smooth-computer-use click --app "Google Chrome" --id 18    # 按编号点击
./smooth-computer-use type "你好" --app 微信 --enter          # 输入并回车
./smooth-computer-use key "cmd+l" --app "Google Chrome"
./smooth-computer-use scroll --app "Google Chrome" --dy -400
./smooth-computer-use screenshot --app Safari --out shot.png
./smooth-computer-use demo                                   # 看光标动画演示
./smooth-computer-use --help
```

全局参数：`--speed 1.0`（光标速度）、`--no-cursor`（不显示虚拟光标）。

---

## 🏗️ 工作原理

```
Antigravity / Cursor ──MCP(stdio)──▶ smooth-computer-use mcp
                                          │  Unix socket
                                          ▼
                                   常驻 daemon（空闲 30 分钟自动退出）
              ┌──────────────────────────┼──────────────────────────┐
              ▼                          ▼                          ▼
     无障碍引擎 (AXEngine)        后台输入 (SkyLight)          光标浮层 (Overlay)
  读界面树 / AXPress / 填值     按进程投递鼠标键盘事件         CALayer + DisplayLink
  命中测试校验点击位置           假聚焦：不抬窗口不抢焦点        最小加加速度 + 弹簧
```

点击的投递顺序（逐级降级，默认永不抢前台）：

1. **AXPress**：语义点击，最稳最准
2. **后台像素点击**：按进程投递 + 窗口内坐标 + 假聚焦，真实鼠标不动
3. **前台点击**：仅在显式指定 `--mode foreground` 时使用

---

## ⚠️ 已知限制

- 仅支持 **macOS**。
- 完全用 Canvas / WebGL 自绘、不暴露无障碍信息的界面，只能按坐标操作。
- Chromium 系应用会丢弃后台滚轮事件，因此用后台方向键滚动；若焦点在输入框里，改用无障碍方式滚动，精度略低。
- 拖拽为尽力而为。
- 使用了 macOS 私有框架 SkyLight 的接口，未来系统更新可能需要适配。

---

## 🙏 致谢

- 灵感来自 OpenAI Codex 桌面端的 Computer Use 体验。
- 后台事件投递与焦点处理参考了 [trycua/cua](https://github.com/trycua/cua)（cua-driver，MIT）与 [yabai](https://github.com/koekeishiya/yabai)（MIT）的公开技术。

## 📄 License

MIT
