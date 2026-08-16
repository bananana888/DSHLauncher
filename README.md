# dsh-launcher 🐋

**DeepSeek Harness 一键启动器** —— 双击即用，DS 蓝鲸主题的美化控制台。

厌倦了每次手动敲 `npx @deepseek-ai/dsh web` 再自己去浏览器输地址？dsh-launcher 帮你一键完成：
探测 → 启动 → 等就绪 → 自动开浏览器，还带启动/停止/重启/日志管理和鲸鱼图标桌面快捷方式。

![主题](https://img.shields.io/badge/theme-DS%20Blue%20%234D6BFE-4D6BFE)

## ✨ 特性

| 特性 | 说明 |
| --- | --- |
| 🖱 一键启动 | 双击桌面快捷方式即用，就绪后自动打开浏览器 |
| 🧠 智能探测 | 端口已被 DSH 占用时直接开浏览器，**绝不重复启动**（避免 profile 文件锁冲突） |
| ⚡ 秒启 | 启动优先级：全局 `dsh` → **npx 缓存直连**（免网络解析）→ `npx` 兜底 |
| 🐋 鲸鱼主题 | 官方鲸鱼图标 + Windows Terminal 专属 profile（**窗口/任务栏鲸鱼图标**、DS 蓝配色、亚克力半透明、Cascadia Code） |
| ✨ 现代 UI | Codex / Claude Code 风格界面：无盒子边框、状态徽标、`›` 提示符；WT 下彩色 emoji 鲸鱼横幅 |
| 🛑 关窗不断线 | dsh 以分离进程驻留后台，误关窗口不丢正在跑的任务；停止用菜单 `[2]` |
| 📋 日志 | 操作日志 `logs/launcher.log` + dsh 输出 `logs/dsh-web.log`，1MB 自动轮转 |
| 🔧 可配置 | `config.json` 覆盖端口 / 超时 / 颜色 / 工作目录 / 是否自动开浏览器 |
| 🔁 可脚本化 | `-Start / -Stop / -Restart / -Status / -TestOnly` 一次性命令，供计划任务复用 |

## 📦 项目结构

```
dsh-launcher/
├── dsh-launcher.ps1        # 主脚本（交互 + 一次性命令 + 自检）
├── install.ps1             # 安装/卸载桌面快捷方式
├── config.example.json     # 配置模板（入库）
├── config.json             # 本地配置（首次运行自动复制，不入库）
├── assets/
│   ├── dsh-launcher.ico    # 多尺寸鲸鱼图标（16~256px）
│   └── logo-source.png     # 图标源图（DeepSeek 官网 favicon 提取）
├── tools/
│   └── make-icon.ps1       # 图标生成器：任意 PNG/ICO → 多尺寸 ICO
├── logs/                   # 运行时生成
├── README.md
└── LICENSE                 # MIT
```

## 🚀 快速开始

```powershell
# 1. 安装（注册 Windows Terminal profile + 创建桌面快捷方式）
.\install.ps1

# 2. 以后双击桌面上的 dsh-launcher 即可

# 仅创建快捷方式、不碰 WT 配置
.\install.ps1 -SkipWT

# 卸载（删快捷方式 + WT profile）
.\install.ps1 -Uninstall
```

也可以直接跑主脚本：

```powershell
.\dsh-launcher.ps1            # 交互模式（默认）
.\dsh-launcher.ps1 -TestOnly  # 环境自检
.\dsh-launcher.ps1 -Status    # 查看运行状态
```

### Windows Terminal profile

`install.ps1` 会向 Windows Terminal 注册一个 **DSH Launcher** profile（修改 `settings.json` 前自动备份）：

- **图标**：鲸鱼 `.ico`（窗口标题栏 + 任务栏）
- **配色**：`DSH Blue` scheme（深海蓝 `#0B1220` 底 + 品牌蓝 `#4D6BFE` 高亮）
- **效果**：亚克力半透明（opacity 0.92）+ Cascadia Code 字体
- 控制台里的鲸鱼横幅在 WT 下用彩色 emoji `🐋`，传统控制台自动退回 ASCII 版

## ⚙️ 配置（config.json）

| 字段 | 默认 | 说明 |
| --- | --- | --- |
| `port` | `3080` | DSH Web 端口，用于探测与就绪判断 |
| `url` | `http://127.0.0.1:3080` | 浏览器打开地址 |
| `timeoutSeconds` | `60` | 启动就绪等待上限 |
| `autoOpenBrowser` | `true` | 就绪后自动打开浏览器 |
| `workingDirectory` | `""`（用户主目录） | dsh 进程工作目录；**保持与你平时启动 dsh 的目录一致**，否则会话历史会分家 |
| `colors.*` | DS 蓝主题 | 控制台配色（`#RRGGBB`），Windows Terminal / PowerShell 7 下真彩生效 |

> 提示：`config.json` 已在 `.gitignore` 中，开源发布只提交 `config.example.json`。

## 🎨 定制图标

想换图标？任何 PNG/ICO 都可以：

```powershell
.\tools\make-icon.ps1 -Source 你的图片.png -Output assets\dsh-launcher.ico
# 重新安装快捷方式使图标生效
.\install.ps1
```

`make-icon.ps1` 会自动生成 16/24/32/48/64/128/256 七个尺寸（PNG 压缩条目，小图标也清晰），透明背景保留。

## 🧭 交互界面

```
  🐋  DSH LAUNCHER
  DeepSeek Harness · 一键启动器 · v1.1.0

  ────────────────────────────────────────
  ● DSH 运行中  PID 34032 · 端口 3080

  [1] 启动 DSH        [2] 停止 DSH
  [3] 重启 DSH        [4] 打开界面
  [5] 查看日志        [0] 退出

  ────────────────────────────────────────
  提示: 关闭窗口不会停止 DSH · 停止请用 [2]

  › 请选择操作
```

## ❓ 常见问题

**Q: 启动失败，提示超时？**
A: 看菜单 `[5]` 的 `dsh-web.err.log` 尾部。常见原因：端口被占、网络代理异常、DSH profile 配置损坏。

**Q: 端口被非 DSH 进程占用？**
A: launcher 会显示警告并拒绝误杀。确认后手动处理占用进程，或修改 `config.json` 的 `port`。

**Q: 代理 / 证书问题导致 npx 拉包失败？**
A: 优先使用 npx 缓存直连模式（已装过 dsh 即可离线秒启）；或先 `npm i -g @deepseek-ai/dsh` 切到全局模式。

**Q: 双击快捷方式闪退？**
A: 用命令行跑 `.\dsh-launcher.ps1 -TestOnly` 看自检结果，通常是 Node 未安装或脚本编码问题。

**Q: Windows Terminal 报「无法从文件加载设置 / Expected: guid / opacity」？**
A: 这是 WT 对 `settings.json` 的两条严格校验，install.ps1 已内置规避与自校验：
- `guid` 必须是**花括号格式** `{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}`（不带花括号会被拒收）
- `opacity` 是 **0–100 的百分比整数**（如 `92`），不能写 `0.92`（且避免浮点序列化噪音）
若仍报错，可回滚安装器自动生成的备份：`settings.json.dsh-bak-*`（在 WT 的 `LocalState` 目录），改完重跑 `.\install.ps1` 即可。

## 🤝 贡献

欢迎参与！请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，要点：

- **提交格式**：Conventional Commits（`feat(scope): 英文主题`，正文可中文）
- **启用 hooks**：clone 后跑一次 `.\githooks\setup-hooks.ps1`（自动校验提交格式 + PS 语法）
- **协作流程**：main 受保护，改动走 PR（模板见 `.github/PULL_REQUEST_TEMPLATE.md`）
- **发布**：重大改动打 `vX.Y.Z` 标签，Actions 自动出 Release

## 📜 许可

[MIT](LICENSE)。鲸鱼图标提取自 DeepSeek 官网 favicon，仅用于个人/工具用途；发布前请自行确认素材合规性。

---

Made with 💙 and 🐋 for the DeepSeek Harness community.
