# 贡献指南（Contributing）

欢迎参与 dsh-launcher 的开发！本指南定义了多人协作的约定，**提交前请通读**。

## 提交规范（Conventional Commits）

所有提交必须符合 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/) 格式：

```
type(scope): 英文主题（祈使句，≤72 字符）

中文说明正文（可选），空行分隔
```

- **type**（必填，小写）：`feat` `fix` `docs` `style` `refactor` `perf` `test` `build` `ci` `chore` `revert`
- **scope**（可选）：影响范围，如 `icon` `install` `wt` `hooks` `cli`
- **主题**：英文；**正文**：可中文
- **破坏性变更**：正文里写 `BREAKING CHANGE: 说明`（自动触发主版本号）

示例：

```
feat(wt): Add acrylic background to profile

Windows Terminal profile 增加亚克力半透明背景（opacity 92）
```

## 启用 Git Hooks（必须）

clone 后执行一次：

```powershell
.\.githooks\setup-hooks.ps1
```

hooks 会强制检查：

| Hook | 检查项 |
| --- | --- |
| `commit-msg` | 提交信息格式（type(scope): 英文主题） |
| `pre-commit` | 暂存区 `.ps1` 语法 + `.json` 合法性 |

> CI 会在 push/PR 时兜底跑同样的语法检查，不依赖本地 hook。

## 分支与 PR 流程

- `main` 受保护：**禁止直接推送**，必须通过 PR 合并（≥1 人批准）
- 分支命名前缀：`feat/` `fix/` `docs/` `chore/`（如 `feat/install-wt-profile`）
- PR 模板见 `.github/PULL_REQUEST_TEMPLATE.md`，按清单自查
- 提交尽量**原子化**：一个提交只做一件事，方便 `git revert` 回滚

## 发布 / 存档流程

日常改动不需要打标签——git 历史本身就是存档（回滚粒度 = 单笔提交）。
**重大改动完成（可交付）时**才发布：

1. 更新 `$Script:Version`（dsh-launcher.ps1 顶部）
2. 更新 `CHANGELOG.md`（把 `[Unreleased]` 改为 `[x.y.z] - 日期`）
3. 合并 PR 到 main
4. 打标签并推送：

```powershell
git tag v1.2.0
git push origin v1.2.0
```

5. GitHub Actions 自动打包 zip 并创建 Release（含发布说明）

## CI 说明

`.github/workflows/ci.yml`：push/PR 自动运行

- PowerShell 语法检查（全部 `.ps1`）
- JSON 配置校验
- `-TestOnly` 自检冒烟

`.github/workflows/release.yml`：推送 `v*` 标签时自动发布。

## 测试要求

- 改动后本地跑 `.\dsh-launcher.ps1 -TestOnly` 确认自检通过
- 涉及启动/停止逻辑的改动，手动验证一次完整流程
- 涉及图标的改动：`.\tools\make-icon.ps1` 重新生成并确认各尺寸可读
