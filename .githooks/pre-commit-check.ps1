<#
.SYNOPSIS
  pre-commit 检查脚本（由 .githooks/pre-commit 调用）
  校验暂存区中的 .ps1 语法与 .json 合法性，任一不通过则退出码非 0 拒绝提交。

.DESCRIPTION
  · .ps1：用 PowerShell 语言解析器检查语法（顺带拦截 LF/编码导致的解析坑）
  · .json：ConvertFrom-Json 校验合法性
  在仓库根目录执行（git hooks 的工作目录即仓库根）。
#>
$ErrorActionPreference = 'Stop'

$files = @(git diff --cached --name-only --diff-filter=ACM 2>$null)
$bad = New-Object System.Collections.ArrayList

foreach ($f in $files) {
  if ($f -like '*.ps1') {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
      [void]$bad.Add("PS 语法: $f  →  $($errors[0].Message)")
    }
  } elseif ($f -like '*.json') {
    try {
      Get-Content $f -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | Out-Null
    } catch {
      [void]$bad.Add("JSON 无效: $f  →  $($_.Exception.Message)")
    }
  }
}

if ($bad.Count -gt 0) {
  Write-Host '✗ pre-commit 检查未通过，请修复后重新提交：'
  foreach ($b in $bad) { Write-Host ("  • " + $b) }
  exit 1
}

exit 0
