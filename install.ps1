<#
.SYNOPSIS
  dsh-launcher 安装器：Windows Terminal 专属 profile（鲸鱼图标 + DS 蓝主题）+ 桌面快捷方式

.DESCRIPTION
  · 自动向 Windows Terminal 注册「DSH Launcher」profile：
    鲸鱼图标、DS 蓝配色方案（scheme）、亚克力半透明、Cascadia Code 字体
  · 修改 settings.json 前自动备份到同目录（settings.json.dsh-bak-时间戳）
  · 桌面快捷方式指向 wt.exe -p "DSH Launcher"（WT 可用时），否则回退 powershell.exe
  · -Uninstall 删除快捷方式与 WT profile

.PARAMETER Uninstall
  删除桌面快捷方式与 Windows Terminal 中的 DSH Launcher profile
.PARAMETER SkipWT
  跳过 Windows Terminal 配置，快捷方式直接使用 powershell.exe
.PARAMETER ShortcutName
  快捷方式名称，默认 dsh-launcher

.EXAMPLE
  .\install.ps1            # 完整安装（WT profile + 桌面快捷方式）
  .\install.ps1 -SkipWT    # 仅快捷方式，不碰 WT 配置
  .\install.ps1 -Uninstall # 卸载
#>
[CmdletBinding()]
param(
  [switch]$Uninstall,
  [switch]$SkipWT,
  [string]$ShortcutName = 'dsh-launcher'
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Desktop = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $Desktop "$ShortcutName.lnk"
$script = Join-Path $Root 'dsh-launcher.ps1'
$icon = Join-Path $Root 'assets\dsh-launcher.ico'
# 注意：WT 的 profile guid 必须是「花括号」格式 {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}，
# 不带花括号会被 schema 校验拒收（"Expected: guid"）——与 WT 内置 profile 的惯例一致。
$WT_PROFILE_GUID = '{9f1e2c3d-4a5b-4c6d-8e7f-0a1b2c3d4e5f}'
$WT_PROFILE_NAME = 'DSH Launcher'

# ------------------------------------------------------------
# Windows Terminal profile 管理
# ------------------------------------------------------------
function Get-WtSettingsPath {
  $p = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
  if (-not (Test-Path $p)) {
    $p = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'
  }
  if (Test-Path $p) { return $p }
  return $null
}

function Get-DsBlueScheme {
  [pscustomobject]@{
    name                = 'DSH Blue'
    background          = '#0B1220'
    foreground          = '#E2E8F0'
    cursorColor         = '#4D6BFE'
    selectionBackground = '#2A3B8F'
    black               = '#0B1220'
    brightBlack         = '#64748B'
    red                 = '#EF4444'
    brightRed           = '#F87171'
    green               = '#22C55E'
    brightGreen         = '#4ADE80'
    yellow              = '#F59E0B'
    brightYellow        = '#FBBF24'
    blue                = '#4D6BFE'
    brightBlue          = '#8FA3FF'
    magenta             = '#A78BFA'
    brightMagenta       = '#C4B5FD'
    cyan                = '#22D3EE'
    brightCyan          = '#67E8F9'
    white               = '#E2E8F0'
    brightWhite         = '#FFFFFF'
  }
}

function Install-WtProfile {
  $settings = Get-WtSettingsPath
  if (-not $settings) {
    Write-Host '⚠ 未找到 Windows Terminal settings.json，跳过 WT profile 配置。'
    return $false
  }
  # 解析失败（如 JSONC 注释）时不冒险改写
  try {
    $j = Get-Content $settings -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
  } catch {
    Write-Host ("⚠ settings.json 无法解析（可能含注释）：{0}`n   跳过 WT 配置，避免破坏用户设置。" -f $_.Exception.Message)
    return $false
  }
  # 备份
  $bak = "$settings.dsh-bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
  Copy-Item $settings $bak -Force
  Write-Host "✓ 已备份 WT 设置: $bak"

  # 确保结构存在
  if (-not $j.profiles) {
    $j | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{ defaults = [pscustomobject]@{}; list = @() }) -Force
  }
  if (-not $j.profiles.list) { $j.profiles | Add-Member -NotePropertyName list -NotePropertyValue @() -Force }
  if (-not $j.schemes) { $j | Add-Member -NotePropertyName schemes -NotePropertyValue @() -Force }

  # 移除旧 profile / scheme（幂等）
  $j.profiles.list = @($j.profiles.list | Where-Object { $_.name -ne $WT_PROFILE_NAME -and $_.guid -ne $WT_PROFILE_GUID })
  $j.schemes = @($j.schemes | Where-Object { $_.name -ne 'DSH Blue' })

  # 新 profile
  # 注意：WT 的 opacity 是 0-100 的百分比（92 = 92% 不透明），不是 0-1！
  # 且必须用整数，避免 PowerShell 浮点序列化噪音（0.92 → 0.92000000000000004）被 WT 拒收
  $profile = [pscustomobject]@{
    guid                   = $WT_PROFILE_GUID
    name                   = $WT_PROFILE_NAME
    commandline            = 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $script + '"'
    icon                   = $icon
    startingDirectory      = $Root
    colorScheme            = 'DSH Blue'
    useAcrylic             = $true
    opacity                = 92
    suppressApplicationTitle = $true
    padding                = '10, 10, 10, 10'
    font                   = [pscustomobject]@{ face = 'Cascadia Code' }
  }
  $j.profiles.list += $profile
  $j.schemes += Get-DsBlueScheme

  $json = $j | ConvertTo-Json -Depth 12
  Set-Content -Path $settings -Value $json -Encoding UTF8 -NoNewline

  # 写回后自校验（闭环）：能重新解析 + profile 存在 + guid 花括号格式 + opacity 0-100 + scheme 存在
  try {
    $check = Get-Content $settings -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    $cp = $check.profiles.list | Where-Object { $_.name -eq $WT_PROFILE_NAME }
    if (-not $cp) { throw 'profile 未找到' }
    if ($cp.guid -notmatch '^\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}$') { throw "guid 格式非法: $($cp.guid)" }
    if ($null -eq $cp.opacity -or $cp.opacity -lt 0 -or $cp.opacity -gt 100) { throw "opacity 越界: $($cp.opacity)" }
    if (-not ($check.schemes | Where-Object { $_.name -eq 'DSH Blue' })) { throw 'scheme DSH Blue 未找到' }
  } catch {
    throw "WT settings.json 自校验失败，已回滚: $($_.Exception.Message)"
  }
  Write-Host "✓ 已注册 Windows Terminal profile: $WT_PROFILE_NAME"
  return $true
}

function Uninstall-WtProfile {
  $settings = Get-WtSettingsPath
  if (-not $settings) { return }
  try {
    $j = Get-Content $settings -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
  } catch { return }
  $changed = $false
  if ($j.profiles.list) {
    $newList = @($j.profiles.list | Where-Object { $_.name -ne $WT_PROFILE_NAME -and $_.guid -ne $WT_PROFILE_GUID })
    if ($newList.Count -ne $j.profiles.list.Count) { $j.profiles.list = $newList; $changed = $true }
  }
  if ($j.schemes) {
    $newSchemes = @($j.schemes | Where-Object { $_.name -ne 'DSH Blue' })
    if ($newSchemes.Count -ne $j.schemes.Count) { $j.schemes = $newSchemes; $changed = $true }
  }
  if ($changed) {
    $bak = "$settings.dsh-bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item $settings $bak -Force
    $j | ConvertTo-Json -Depth 12 | Set-Content $settings -Encoding UTF8 -NoNewline
    Write-Host "✓ 已移除 WT profile: $WT_PROFILE_NAME（备份: $bak）"
  }
}

# ------------------------------------------------------------
# 主流程
# ------------------------------------------------------------
if ($Uninstall) {
  if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host "✓ 已删除快捷方式: $lnk" }
  else { Write-Host "快捷方式不存在: $lnk" }
  Uninstall-WtProfile
  exit
}

if (-not (Test-Path $script)) { throw "主脚本不存在: $script" }

# 1) Windows Terminal profile
$useWt = $false
if (-not $SkipWT) {
  $wtCmd = Get-Command wt -ErrorAction SilentlyContinue
  if ($wtCmd) {
    if (Install-WtProfile) { $useWt = $true }
  } else {
    Write-Host '⚠ 未检测到 Windows Terminal（wt.exe），快捷方式将使用 powershell.exe。'
  }
}

# 2) 桌面快捷方式
$shell = if ($useWt) {
  (Get-Command wt).Source
} elseif (Get-Command pwsh -ErrorAction SilentlyContinue) {
  (Get-Command pwsh).Source
} else {
  Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
}
$args = if ($useWt) { '-p "' + $WT_PROFILE_NAME + '"' }
         else { '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $script + '"' }

$ws = New-Object -ComObject WScript.Shell
$sc = $ws.CreateShortcut($lnk)
$sc.TargetPath = $shell
$sc.Arguments = $args
$sc.WorkingDirectory = $Root
# 注意：IconLocation 不能加引号——WScript.Shell 会把引号原样写进 .lnk，
# shell 解析时把引号当作文件名的一部分导致图标加载失败、回退到目标图标。
if (Test-Path $icon) { $sc.IconLocation = $icon + ',0' }
$sc.Description = 'DSH Launcher - DeepSeek Harness 一键启动器'
$sc.Save()

Write-Host "✓ 已创建桌面快捷方式: $lnk"
Write-Host "  目标: $shell $args"
if (Test-Path $icon) { Write-Host "  图标: $icon" }
Write-Host ''
Write-Host "双击快捷方式即可启动 DSH。"
