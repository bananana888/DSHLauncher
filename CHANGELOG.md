# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 与 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added

- Git 协作规范与工具链：Conventional Commits hooks、CI、Release 自动化、贡献指南

## [1.1.0] - 2026-08-16

### Added

- Windows Terminal 专属 profile：鲸鱼图标、DS 蓝配色方案（DSH Blue）、亚克力半透明、Cascadia Code 字体
- Codex / Claude Code 风格 UI：无盒子边框、状态徽标、`›` 提示符
- WT 下 emoji 鲸鱼横幅（传统控制台回退 ASCII）

### Fixed

- 小尺寸图标改为实心剪影版（16-48px 清晰可辨，不再糊成字母 Q）
- 快捷方式 IconLocation 引号导致图标加载失败（白色图标）
- WT `opacity` 单位（0-100 百分比）与浮点序列化噪音
- WT profile `guid` 缺少花括号导致设置被拒收

## [1.0.0] - 2026-08-16

### Added

- 一键启动 / 停止 / 重启 DSH Web，就绪后自动打开浏览器
- 智能探测：已运行则直接开浏览器，绝不重复启动
- 启动优先级：全局 `dsh` → npx 缓存直连 → `npx` 兜底
- 官方 DeepSeek 鲸鱼多尺寸图标（16-256px）与生成器 `tools/make-icon.ps1`
- 配置文件驱动（端口 / 超时 / 工作目录 / 配色）
- 日志系统（launcher.log / dsh-web.log，1MB 自动轮转）
- 一次性命令：`-Start` `-Stop` `-Restart` `-Status` `-TestOnly`
