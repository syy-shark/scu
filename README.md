# 🖱️ Smooth Computer Use

**专为 Antigravity 和 Cursor 准备的 macOS Computer Use（电脑操控）Skill。**

> 整个仓库就是一个 Skill：克隆到 skills 目录即可使用，不用改任何配置。

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
| ⌨️ **能打字发消息** | 对 Cursor / Chrome / 微信等支持中文输入，`--enter` 一步「输入 + 回车发送」 |
| ⚡ **快** | 读取 Cursor 整个界面约 0.4 秒；每次调用最多 10 秒，绝不卡死 |
| 🧩 **即插即用** | 是一个标准 Skill：克隆进 skills 目录就能用，第一次调用自动编译 |

---

## 🚀 最简单的用法：直接告诉你的 AI

### 第 1 步：一句话安装

把下面这段话**原样复制**发给你的 **Antigravity**：

```text
请帮我安装 Smooth Computer Use 这个 Skill：
1. 把 https://github.com/syy-shark/smooth-computer-use 克隆到 ~/.gemini/config/skills/smooth-computer-use
2. 运行 ~/.gemini/config/skills/smooth-computer-use/cu doctor（第一次会自动编译），告诉我缺哪些权限
```

发给 **Cursor** 的版本：

```text
请帮我安装 Smooth Computer Use 这个 Skill：
1. 把 https://github.com/syy-shark/smooth-computer-use 克隆到 ~/.cursor/skills/smooth-computer-use
2. 运行 ~/.cursor/skills/smooth-computer-use/cu doctor（第一次会自动编译），告诉我缺哪些权限
```

> 两个都用？克隆一份，再建个软链接即可：
> `ln -s ~/.gemini/config/skills/smooth-computer-use ~/.cursor/skills/smooth-computer-use`

### 第 2 步：授权（只需一次）

打开「系统设置 → 隐私与安全性」，给**你正在用的那个 App**（Antigravity 或 Cursor）勾上：

- ✅ **辅助功能**（Accessibility）——用于读取界面、点击、打字
- ✅ **屏幕录制**（Screen Recording）——用于截图

勾完后**重启 Antigravity / Cursor**。

> 💡 建议把 `cu` 命令加入终端命令的**自动允许列表**，否则 AI 每操作一步都要你点一次「允许」。

### 第 3 步：直接说你想干什么

```text
打开计算器，帮我算 2026 × 42
```
```text
在 Chrome 里打开 B 站，往下滑，点开第一个视频
```
```text
在微信里找到「文件传输助手」，发一句：今天的报告写完了
```
```text
在 Cursor 的聊天框里发：帮我检查一下 src 目录的类型错误
```
```text
截一张 Safari 窗口的图，告诉我页面上写了什么
```

AI 会自动加载这个 Skill：先读界面（`cu state`）→ 找到元素编号 → 点击 / 输入 / 发送，你在旁边看着就行。
如果它没想起来用，在话前面加一句「用 smooth-computer-use skill」。

---

## 🔧 手动安装

**要求**：macOS 14+（Apple Silicon 或 Intel），Xcode Command Line Tools（`xcode-select --install`）。

```bash
# Antigravity（全局）
git clone https://github.com/syy-shark/smooth-computer-use.git ~/.gemini/config/skills/smooth-computer-use
# Cursor（全局）
git clone https://github.com/syy-shark/smooth-computer-use.git ~/.cursor/skills/smooth-computer-use
# 只给某个项目用：克隆到项目里的 .agents/skills/（Antigravity）或 .cursor/skills/（Cursor）

~/.gemini/config/skills/smooth-computer-use/cu doctor   # 自动编译 + 检查权限，全部 ✅ 即可
```

更新：在 Skill 目录里 `git pull`，下次调用 `cu` 时会自动重新编译。

### Skill 的结构

```
smooth-computer-use/
├── SKILL.md      ← 给 AI 看的说明书：什么时候用、怎么用（看界面 → 按编号操作 → 验证）
├── cu            ← 启动脚本：第一次自动编译，之后直接运行
├── build.sh
└── Sources/      ← Swift 源码
```

---

## 💻 命令一览（AI 用的就是这些，你也可以自己在终端里用）

```bash
cu apps                                         # 运行中的 App
cu state "Google Chrome" --interactive          # 带编号的界面树（只列可操作控件）
cu click --app Calculator --title "7"           # 按文字点击
cu click --app "Google Chrome" --id 18          # 按编号点击（--right 右键 / --double 双击）
cu type "你好" --app 微信 --id 7 --enter         # 输入并回车发送
cu key "cmd+l" --app "Google Chrome"            # 快捷键
cu scroll --app "Google Chrome" --dy -400       # 向下滚动
cu screenshot --app Safari --out /tmp/shot.png  # 截窗口（被挡住也行）
cu open-url "https://www.bilibili.com" --app "Google Chrome"
cu demo                                         # 看光标动画演示
cu --help
```

全局参数：`--speed 1.0`（光标速度）、`--no-cursor`（不显示虚拟光标）。

---

## 🔌 也可以当 MCP 用（可选）

不想用 Skill 的话，同一个程序也是标准 MCP 服务器（stdio）。在 Antigravity 的 MCP 原始配置或 Cursor 的 `~/.cursor/mcp.json` 里加入：

```json
{
  "mcpServers": {
    "computer-use": {
      "command": "/绝对路径/smooth-computer-use/smooth-computer-use",
      "args": ["mcp"]
    }
  }
}
```

（先运行一次 `cu doctor` 生成 `smooth-computer-use` 二进制。）
提供的工具：`list_apps`、`get_app_state`、`click`、`type_text`（`submit=true` 回车发送）、`press_key`、`set_value`、`scroll`、`drag`、`hover`、`perform_secondary_action`、`open_app`、`open_url`、`screenshot`、`wait`。

---

## 🏗️ 工作原理

```
Antigravity / Cursor ──Skill: cu 命令 / 或 MCP──▶ smooth-computer-use
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
