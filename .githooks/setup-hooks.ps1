<#
.SYNOPSIS
  启用 / 停用 dsh-launcher 的 git hooks（commit-msg 格式校验 + pre-commit 语法检查）

.DESCRIPTION
  通过设置仓库级 core.hooksPath 指向 .githooks 目录来启用 hooks，
  无需复制文件到 .git/hooks，clone 后一键生效。

.EXAMPLE
  .\.githooks\setup-hooks.ps1          # 启用
  .\.githooks\setup-hooks.ps1 -Uninstall  # 停用
#>
param(
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$hookDir = $PSScriptRoot
$repoRoot = Split-Path $hookDir -Parent

if ($Uninstall) {
  git -C $repoRoot config --unset core.hooksPath
  Write-Host '✓ 已停用 dsh-launcher git hooks'
  exit 0
}

git -C $repoRoot config core.hooksPath .githooks
Write-Host '✓ 已启用 git hooks（core.hooksPath = .githooks）'
Write-Host '  · commit-msg: Conventional Commits 格式校验（type(scope): 英文主题）'
Write-Host '  · pre-commit: 暂存区 .ps1 语法 + .json 合法性检查'
Write-Host ''
Write-Host '提交格式示例:'
Write-Host '  feat(icon): Add solid silhouette for small sizes'
Write-Host '  fix(install): Correct WT opacity unit'
