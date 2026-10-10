<div align="center">

**简体中文** · [English](README_en.md)

# Smooth Computer Use

### 专为 macOS Agent 构建的非侵入式、显示同步计算机操控引擎。

**专为 Google Antigravity 与 Cursor 原生设计的 Agent Skill。**

[![Platform](https://img.shields.io/badge/平台-macOS%2014%2B-black?style=flat-square&logo=apple&logoColor=white)](#系统要求)
[![Swift](https://img.shields.io/badge/语言-Swift%205-F05138?style=flat-square&logo=swift&logoColor=white)](#系统要求)
[![Interface](https://img.shields.io/badge/接口-Agent%20Skill-5c4ee5?style=flat-square)](#快速开始)
[![Protocol](https://img.shields.io/badge/协议-MCP%20stdio-blue?style=flat-square)](#mcp-服务器可选)
[![License](https://img.shields.io/badge/协议-MIT-f4c430?style=flat-square)](LICENSE)

[快速开始](#快速开始) · [核心特性](#核心特性) · [系统架构](#系统架构) · [命令速查](#命令速查) · [MCP 服务器](#mcp-服务器可选) · [局限性说明](#局限性说明)

</div>

---

传统的视觉 Computer Use 机制通常直接抢占用户的硬件鼠标指针、强制前台激活窗口，并产生突兀的坐标瞬移。只要用户在 Agent 执行任务期间操作机器，就会造成输入竞态与点击失准。

Smooth Computer Use 将 Agent 操作与物理硬件输入彻底解耦。本引擎直接基于 macOS 底层私有图形子系统（`SkyLight`）与语义无障碍原语（`AXUIElement`）构建，能够在纯后台环境下完成全套桌面应用控制工作流；同时，独立的半透明虚拟光标层以硬件刷新率同步渲染顺滑的拟人轨迹。

本仓库本身即是一个自包含的标准 Agent Skill：将其克隆至 Agent 的技能目录即可立即生效，无需安装任何额外运行时依赖。

---

## 核心特性

| 维度 | 机制 | 效果保障 |
|---|---|---|
| 物理指针解耦 | 进程隔离事件投递（`SLEventPostToPid`） | 用户的物理鼠标指针完全不受干扰，自由移动。 |
| 窗口焦点隔离 | 目标窗口合成激活（`SLPSPostEventRecordTo`） | 目标窗口在后台直接接收事件，不抬升层级、不剥夺当前前台激活态。 |
| 命中精度保障 | 语义动作优先（`AXPress`），命中测试校验像素点居次 | 告别盲目坐标猜测；操作均基于无障碍边界框架与命中测试实时校验。 |
| 视觉连续性 | `CADisplayLink` 硬件级 V-Sync + 最小加加速度轨迹规划 | 虚拟光标沿三次曲线自然平滑滑动，伴随切向倾角与阻尼弹簧物理响应。 |
| 文本流式输入 | 分块 Unicode 按键事件 + 合成焦点保护 | 极速中英文字符流式输入；支持单步完成键入与回车提交（`--enter`）。 |
| 确定性延迟控制 | 单元素查询严格超时（250 ms）与单次调用硬上限（10 s） | 彻底免疫 Electron / Chromium 复杂的无障碍树挂起，UI 解析耗时低于 0.5 秒。 |
| 零依赖自举 | 原生 Swift 架构与自动化 `cu` 引导外壳 | 无 Python / Node / pip 依赖；首次调用自动检测并完成增量编译。 |

---

## 快速开始

### 1. 向你的 Agent 注册

将对应环境的指令块原样复制并发送给你的 Agent：

#### 适用于 Google Antigravity

```text
请帮我安装 Smooth Computer Use 这个 Skill：
1. 把 https://github.com/syy-shark/smooth-computer-use 克隆到 ~/.gemini/config/skills/smooth-computer-use
2. 运行 ~/.gemini/config/skills/smooth-computer-use/cu doctor 验证环境与权限。
```

#### 适用于 Cursor

```text
请帮我安装 Smooth Computer Use 这个 Skill：
1. 把 https://github.com/syy-shark/smooth-computer-use 克隆到 ~/.cursor/skills/smooth-computer-use
2. 运行 ~/.cursor/skills/smooth-computer-use/cu doctor 验证环境与权限。
```

> **双环境共享安装**：若需在两套环境中同时使用，只需克隆至一处并建立软链接：
> ```bash
> ln -s ~/.gemini/config/skills/smooth-computer-use ~/.cursor/skills/smooth-computer-use
> ```

---

### 2. 授予 macOS 隐私权限

打开「系统设置 -> 隐私与安全性」，确保运行 Agent 的宿主应用（**Antigravity**、**Cursor** 或使用的**终端**）已在以下权限列表中开启授权：

- **辅助功能（Accessibility）**：用于解析应用 UI 结构树、执行语义点击与后台按键流注入。
- **屏幕录制（Screen Recording）**：用于后台窗口画面截取以及无障碍缺失时的坐标兜底。

修改授权状态后，请重启宿主应用。

*建议*：可将 `cu` 命令加入 Agent 终端工具的自动允许列表，避免每一步执行均弹出交互式放行弹窗。

---

### 3. 操作示例

注册完成后，直接通过自然语言下达控制指令：

```text
打开计算器，帮我计算 2026 * 42。
```

```text
在 Google Chrome 中打开 bilibili.com，向下滑动页面，并打开第一个视频。
```

```text
在微信中找到“文件传输助手”，发送：“部署验证已全部通过。”
```

```text
在 Cursor 聊天输入框中输入并提交：“请审查 src/engine 模块中的潜在内存泄露。”
```

```text
在后台截取一张 Safari 窗口的屏幕截图，并概括当前激活标签页的内容。
```

Agent 将自动依据 `SKILL.md` 规范执行操作闭环：`检查界面状态 -> 定位元素索引 -> 执行原子动作 -> 校验执行结果`。

---

## 系统架构

```
Agent 宿主环境 (Antigravity / Cursor)
      │
      │  执行 Skill 命令（或通过 stdio 进行 JSON-RPC 交互）
      ▼
   cu 启动包装器 (首次调用自动编译原生二进制)
      │
      │  本地 Unix 域套接字 (/tmp/smooth-cu-<uid>.sock)
      ▼
smooth-computer-use 常驻守护进程 (空闲 30 分钟自动退出)
   ├── 无障碍语义引擎 (AXEngine)
   │     ├── 带 AXManualAccessibility 预热的高速结构树快照
   │     ├── 元素检索与边界框架命中测试实时校验
   │     └── 直接执行语义动作 (AXPress, AXScrollToVisible)
   ├── 后台输入分发器 (SkyLight SPIs)
   │     ├── 基于 SLEventPostToPid 的进程隔离鼠标动作注入
   │     ├── 不改变窗口 Z 序的合成焦点状态维护
   │     └── 分块 Unicode 按键流注入与组合键转换
   └── 光标浮层子系统 (Cursor Overlay Subsystem)
         ├── 位于 .screenSaver 级别的多屏穿透无干扰浮层窗口
         ├── CADisplayLink 60/120 Hz 刷新率驱动渲染泵
         └── 最小加加速度曲线、惯性倾角与弹簧动力学模型
```

### 动作分发降级阶梯

为确保操作可靠性，动作执行遵循严格的降级阶梯：

1. **语义执行（`AXPress`）**：在无障碍语义树中精确定位元素并直接调用其动作处理程序。速度极快，零坐标偏移。
2. **后台目标进程合成事件**：当控件未暴露标准语义动作时，引擎定位目标窗口，通过命中测试校验坐标，建立合成焦点上下文，并通过私有 `SkyLight` SPI 投递窗口相对坐标事件。
3. **前台事件兜底**：仅在显式传入 `--mode foreground` 参数时启用。默认配置下永不触发。

---

## 命令速查

Agent 统一通过 `cu` 与守护进程通信。用户亦可在终端中直接调用该命令：

```bash
# 状态检查
cu apps                                         # 列出运行中的应用与窗口归属
cu state "Google Chrome" --interactive          # 读取带编号的 UI 控件树 (紧凑交互模式)
cu state Cursor --window "smooth-computer-use"  # 检查指定标题的窗口
cu screenshot --app Safari --out /tmp/win.png   # 后台窗口截图 (被遮挡状态依然有效)
cu doctor                                       # 权限与多显示器环境诊断

# 目标操作
cu click --app Calculator --title "7"           # 按名称进行语义或坐标点击
cu click --app "Google Chrome" --id 18          # 按 `cu state` 中的序号点击元素
cu click 450 320 --app Slack                    # 点击相对于窗口的屏幕物理点
cu click --app Finder --id 4 --double           # 目标双击
cu click --app Notes --id 12 --right            # 目标右键菜单

# 文本与键盘输入
cu type "Hello world" --app Notes --id 3        # 聚焦控件并输入文本
cu type "npm test" --app Cursor --id 48 --enter # 键入文本并派发 Return 回车提交
cu key "cmd+l" --app "Google Chrome"            # 发送组合快捷键
cu key "down" --app "Google Chrome" --repeat 5  # 连续派发导航方向键
cu set-value "100" --app Settings --id 9        # 直接覆写无障碍属性值

# 视口滚动与手势
cu scroll --app "Google Chrome" --dy -400       # 垂直滚动 (-向下 / +向上)
cu drag 200 300 600 300 --app Keynote           # 从点 A 拖拽至点 B
cu hover --app "Google Chrome" --id 14          # 触发悬停状态

# 动效与进程管理
cu demo                                         # 轨迹规划与弹簧物理效果视觉演示
cu stop                                         # 终止后台常驻守护进程
```

**全局参数**：
- `--no-cursor`：关闭可视化的虚拟光标浮层。
- `--speed <float>`：轨迹移动速度倍率（默认值：`1.0`）。

---

## MCP 服务器（可选）

除作为 Agent Skill 外，`smooth-computer-use` 同时支持通过标准 `stdio` 暴露 Model Context Protocol（MCP）服务。

### 配置方式

在你的 MCP 配置文件中（Cursor 对应 `~/.cursor/mcp.json`，或 Antigravity 的 MCP 原生配置项）加入以下声明：

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

*（首次配置前请先运行一次 `./cu doctor` 生成二进制可执行文件）。*

### 支持的 MCP 工具列表

- `list_apps`：枚举当前运行的桌面应用程序。
- `get_app_state`：获取带有顺序 ID 的结构化无障碍树节点。
- `click`：支持通过 ID、文本查询或坐标对目标发起点击。
- `type_text`：具备自动焦点获取机制的 Unicode 文本注入，支持 `submit` 回车提交。
- `press_key`：常用按键与组合快捷键派发（`cmd+c`、`return`、`escape` 等）。
- `set_value`：直接修改控件值。
- `scroll`：自适应视口滚动。
- `drag`：坐标范围拖拽。
- `hover`：光标悬停检查。
- `perform_secondary_action`：调用特定无障碍辅助动作（`AXShowMenu`、`AXIncrement` 等）。
- `open_app` / `open_url`：后台启动应用程序或打开目标 URL。
- `screenshot`：窗口或全屏捕获。
- `wait`：UI 渲染时序等待。

---

## 系统要求

- **操作系统**：macOS 14.0 (Sonoma) 或更高版本（完整支持 Apple Silicon 与 Intel 架构）。
- **工具链**：Xcode Command Line Tools（可通过 `xcode-select --install` 安装）。
- **外部依赖**：无。纯原生 Swift 实现，直接依赖 ApplicationServices、CoreGraphics、Cocoa 及 ScreenCaptureKit 原生框架。

---

## 局限性说明

- **纯 Canvas / WebGL 界面**：直接在 Canvas 上自绘制且未暴露无障碍语义的界面，无法提取语义节点 ID，必须降级为基于截图判读的像素坐标点击。
- **Chromium 滚动语义**：Chromium 在 macOS 的渲染合成层会主动丢弃后台滚轮事件。对 Chromium 系应用，滚动通过后台方向键序列或 `AXScrollToVisible` 遍历显露容器完成。
- **跨进程拖放**：跨越不同进程边界的拖放动作依赖目标应用对合成拖拽生命周期的支持程度。

---

## 致谢

- 架构灵感源于对现代桌面 Agent Runner 运行机制的逆向工程解析。
- 后台事件路由与合成焦点设计参考了 [trycua/cua](https://github.com/trycua/cua)（MIT）与 [yabai](https://github.com/koekeishiya/yabai)（MIT）的公开技术研究。

---

## 开源协议

[MIT](LICENSE) © 2026 syy-shark
