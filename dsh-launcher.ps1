<#
.SYNOPSIS
  dsh-launcher — DeepSeek Harness 一键启动器（DS 蓝鲸主题）

.DESCRIPTION
  · 双击即用：自动探测并启动 `dsh web`，就绪后自动打开浏览器
  · 智能探测：端口已被 DSH 占用时直接开浏览器，绝不重复启动
  · 启动优先级：全局安装的 dsh → npx 缓存直连（秒启、免网络）→ npx 兜底
  · 交互菜单：启动 / 停止 / 重启 / 打开界面 / 查看日志 / 退出
  · 关窗不杀进程：dsh 以分离进程驻留后台；需要停止时用菜单 [2]
  · 全部行为可用 config.json 覆盖（端口、超时、颜色、工作目录等）

.PARAMETER Start
  一次性命令：仅启动 DSH 后退出（供脚本/计划任务复用）
.PARAMETER Stop
  一次性命令：仅停止 DSH 后退出
.PARAMETER Restart
  一次性命令：重启 DSH 后退出
.PARAMETER Status
  一次性命令：打印当前 DSH 运行状态后退出
.PARAMETER TestOnly
  自检模式：检查环境（Node/DSH 发现/端口/配置/日志/图标）后退出，不启动任何进程
.PARAMETER NoBrowser
  启动成功后不自动打开浏览器

.EXAMPLE
  .\dsh-launcher.ps1               # 交互模式（默认）
  .\dsh-launcher.ps1 -Start        # 仅启动
  .\dsh-launcher.ps1 -Stop         # 仅停止
  .\dsh-launcher.ps1 -Restart      # 重启
  .\dsh-launcher.ps1 -Status       # 查看状态
  .\dsh-launcher.ps1 -TestOnly     # 环境自检
#>
[CmdletBinding()]
param(
  [switch]$Start,
  [switch]$Stop,
  [switch]$Restart,
  [switch]$Status,
  [switch]$TestOnly,
  [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

# ============================================================
# 基础路径
# ============================================================
$Script:Version = '1.1.0'
$Script:Root    = $PSScriptRoot
$Script:LogDir  = Join-Path $Root 'logs'
$Script:ConfigPath  = Join-Path $Root 'config.json'
$Script:ExamplePath = Join-Path $Root 'config.example.json'

# ============================================================
# 配置加载（config.json 缺失时自动从 example 复制）
# ============================================================
if (-not (Test-Path $ConfigPath) -and (Test-Path $ExamplePath)) {
  Copy-Item $ExamplePath $ConfigPath
  Write-Host "[dsh-launcher] 已生成默认配置: $ConfigPath"
}
if (Test-Path $ConfigPath) {
  $Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
} else {
  $Config = [pscustomobject]@{
    port             = 3080
    url              = 'http://127.0.0.1:3080'
    timeoutSeconds   = 60
    autoOpenBrowser  = $true
    workingDirectory = ''
    colors           = [pscustomobject]@{ primary = '#4D6BFE'; light = '#8FA3FF'; text = '#E2E8F0'; dim = '#64748B'; background = '#0B1220'; success = '#22C55E'; error = '#EF4444'; warning = '#F59E0B' }
  }
}
$Port       = if ($Config.port)            { [int]$Config.port }            else { 3080 }
$Url        = if ($Config.url)             { [string]$Config.url }          else { "http://127.0.0.1:$Port" }
$TimeoutSec = if ($Config.timeoutSeconds)  { [int]$Config.timeoutSeconds }  else { 60 }
$AutoOpen   = if ($null -ne $Config.autoOpenBrowser) { [bool]$Config.autoOpenBrowser } else { $true }
$WorkDir    = if ($Config.workingDirectory) { [string]$Config.workingDirectory }      else { $env:USERPROFILE }
if (-not (Test-Path $WorkDir)) {
  Write-Host "[dsh-launcher] 警告: 配置的工作目录不存在 ($WorkDir)，回退到用户主目录"
  $WorkDir = $env:USERPROFILE
}
# 颜色（缺省兜底到 DS 品牌蓝 #4D6BFE 系）
$C = [pscustomobject]@{
  primary    = $(if ($Config.colors.primary)    { $Config.colors.primary }    else { '#4D6BFE' })
  light      = $(if ($Config.colors.light)      { $Config.colors.light }      else { '#8FA3FF' })
  text       = $(if ($Config.colors.text)       { $Config.colors.text }       else { '#E2E8F0' })
  dim        = $(if ($Config.colors.dim)        { $Config.colors.dim }        else { '#64748B' })
  background = $(if ($Config.colors.background) { $Config.colors.background } else { '#0B1220' })
  success    = $(if ($Config.colors.success)    { $Config.colors.success }    else { '#22C55E' })
  error      = $(if ($Config.colors.error)      { $Config.colors.error }      else { '#EF4444' })
  warning    = $(if ($Config.colors.warning)    { $Config.colors.warning }    else { '#F59E0B' })
}

# ============================================================
# 控制台准备：UTF-8 输出 + 真彩支持检测
# ============================================================
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { chcp 65001 | Out-Null } catch {}
try { $host.UI.RawUI.WindowTitle = "DSH Launcher v$Version - DeepSeek Harness 一键启动器" } catch {}
# 真彩（24-bit）仅在 Windows Terminal / PowerShell 7 下可用，否则退回 16 色
$Script:VT = ($env:WT_SESSION -ne $null) -or ($PSVersionTable.PSVersion.Major -ge 7)
$Script:ESC = [char]27
if ($VT) {
  # Windows Terminal 下不画背景：让 profile 的亚克力/DS 蓝配色透出来
  if (-not $env:WT_SESSION) {
    try {
      $bg = Get-Rgb $C.background
      [Console]::Write("$ESC[48;2;$($bg.r);$($bg.g);$($bg.b)m$ESC[2J$ESC[H")
    } catch {}
  }
} else {
  try { [Console]::BackgroundColor = [ConsoleColor]::Black } catch {}
}

# ============================================================
# 日志
# ============================================================
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
function Write-Log([string]$msg) {
  $logFile = Join-Path $LogDir 'launcher.log'
  try {
    if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 1MB)) {
      Move-Item $logFile (Join-Path $LogDir 'launcher.log.old') -Force -ErrorAction SilentlyContinue
    }
    Add-Content -Path $logFile -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8
  } catch {}
}

# ============================================================
# 彩色输出
# ============================================================
function Get-Rgb([string]$hex) {
  $h = $hex.TrimStart('#')
  [pscustomobject]@{
    r = [Convert]::ToInt32($h.Substring(0, 2), 16)
    g = [Convert]::ToInt32($h.Substring(2, 2), 16)
    b = [Convert]::ToInt32($h.Substring(4, 2), 16)
  }
}
# 显示宽度：CJK 全角字符按 2 列计（控制台渲染宽度 ≠ 字符串长度）
function Get-DisplayWidth([string]$s) {
  $w = 0
  foreach ($ch in $s.ToCharArray()) { $w += if ([int]$ch -gt 255) { 2 } else { 1 } }
  return $w
}
function Write-C([string]$text, [string]$key = 'text') {
  if ($VT) {
    $rgb = Get-Rgb $C.$key
    [Console]::Write("$ESC[38;2;$($rgb.r);$($rgb.g);$($rgb.b)m$text$ESC[0m")
  } else {
    $map = @{ primary = 'Cyan'; light = 'Cyan'; text = 'White'; dim = 'DarkGray'; background = 'Black'; success = 'Green'; error = 'Red'; warning = 'Yellow' }
    [Console]::ForegroundColor = $map[$key]
    [Console]::Write($text)
    [Console]::ResetColor()
  }
}
function Write-CL([string]$text, [string]$key = 'text') { Write-C "$text`n" $key }
# 右补空格到指定显示宽度（CJK 按 2 列）
function Pad-Right([string]$s, [int]$width) {
  $w = Get-DisplayWidth $s
  if ($w -ge $width) { return $s }
  return $s + (' ' * ($width - $w))
}
# Codex/Claude Code 风格菜单行：编号用主题色、标签用正文色、两列对齐
function Write-MenuRow([string]$n1, [string]$l1, [string]$n2, [string]$l2) {
  Write-C '  ' 'dim'
  Write-C ('[' + $n1 + ']') 'primary'
  Write-C (' ' + $l1) 'text'
  if ($n2) {
    $w = Get-DisplayWidth ('[' + $n1 + '] ' + $l1)
    $pad = [Math]::Max(3, (22 - $w))
    Write-C (' ' * $pad) 'dim'
    Write-C ('[' + $n2 + ']') 'primary'
    Write-C (' ' + $l2) 'text'
  }
  Write-CL '' 'dim'
}
function Write-Separator {
  Write-CL ('  ' + ('─' * 40)) 'dim'
}

# ============================================================
# 鲸鱼横幅（Codex/Claude Code 风格，无盒子边框）
# ============================================================
function Show-Banner {
  if ($env:WT_SESSION) {
    # Windows Terminal：emoji 鲸鱼，彩色、一眼可辨（不再用辨识度低的 ASCII 线稿）
    Write-CL '  🐋  DSH LAUNCHER' 'primary'
    Write-CL ("  DeepSeek Harness · 一键启动器 · v{0}" -f $Version) 'dim'
    Write-CL '' 'dim'
  } else {
    # 传统控制台：ASCII 鲸鱼兜底
    $art = @'
                .-~~~-.
  .- ~ ~-(       )     )
 (                 )   )
  ` _ .-'      )   )
   `-._.-'-(  )  (
              `'--'`
'@ -split "`r?`n" | Where-Object { $_ }
    foreach ($l in $art) { Write-CL ("  " + $l) 'light' }
    Write-CL '' 'dim'
    Write-CL '  DSH LAUNCHER' 'primary'
    Write-CL ("  DeepSeek Harness · 一键启动器 · v{0}" -f $Version) 'dim'
    Write-CL '' 'dim'
  }
}

# ============================================================
# 端口 / 进程探测
# ============================================================
function Get-DshStatus {
  # 优先 Get-NetTCPConnection；拒绝访问/不可用时回退 netstat 解析（两者都只读，安全）
  try {
    $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop | Select-Object -First 1
    if ($conn) { return New-StatusObject $conn.OwningProcess }
  } catch {}
  $pattern = 'TCP\s+.*?(127\.0\.0\.1:' + $Port + '|\[::(1)?\]:' + $Port + '|\*:' + $Port + ')\s+.*LISTENING'
  $line = netstat -ano | Select-String $pattern | Select-Object -First 1
  if ($line) {
    $parts = ($line.ToString().Trim() -split '\s+')
    return New-StatusObject ([int]$parts[$parts.Count - 1])
  }
  return $null
}
function New-StatusObject([int]$procId) {
  $name = ''
  $commandLine = ''
  try {
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction Stop
    $name = $proc.Name
    $commandLine = "$($proc.CommandLine)"
  } catch {
    # CIM 不可用（如权限受限）时退回 Get-Process，仅得进程名
    try { $name = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch {}
  }
  [pscustomobject]@{ Pid = $procId; Name = $name; CommandLine = $commandLine }
}
function Test-DshProcess([object]$st) {
  if (-not $st) { return $false }
  # 有命令行：精确匹配 dsh 特征
  if ($st.CommandLine) {
    $cl = $st.CommandLine
    if (($cl -match '@deepseek-ai') -or ($cl -match '\bdsh\b') -or ($cl -match 'dsh\.(cmd|js)')) { return $true }
    return $false
  }
  # 无命令行（权限受限）：dsh web 是 node 进程，按进程名启发式判断
  return ($st.Name -match '^node(\.exe)?$')
}
function Show-Status {
  $st = Get-DshStatus
  if (-not $st) {
    Write-CL ("  ● DSH 未运行（端口 {0} 空闲）" -f $Port) 'dim'
  } elseif (Test-DshProcess $st) {
    Write-CL ("  ● DSH 运行中   PID {0}   端口 {1}" -f $st.Pid, $Port) 'success'
  } else {
    Write-CL ("  ⚠ 端口 {0} 被其他进程占用：{1} (PID {2})——非 DSH 实例，不会误杀" -f $Port, $st.Name, $st.Pid) 'warning'
  }
}

# ============================================================
# DSH 发现：全局 → npx 缓存直连 → npx 兜底
# ============================================================
function Find-Dsh {
  # 1) 全局安装
  $g = Get-Command dsh -ErrorAction SilentlyContinue
  # 跳过 npx 缓存里的临时 shim（_npx 目录），它应走下方 npx-cache 直连模式
  if ($g -and $g.Source -and ($g.Source -notmatch '\\_npx\\')) {
    $src = $g.Source
    # npm 全局会同时生成 dsh.ps1 与 dsh.cmd，优先可执行文件
    if ($src -match '\.ps1$') {
      $alt = $src -replace '\.ps1$', '.cmd'
      if (Test-Path $alt) { $src = $alt }
    }
    if ($src -match '\.(cmd|exe|bat)$') {
      return [pscustomobject]@{ Mode = 'global'; File = $src; Args = @('web') }
    }
  }
  # 2) npx 缓存直连（免网络、免 npx 解析）
  $cacheRoot = Join-Path $env:LOCALAPPDATA 'npm-cache\_npx'
  if (Test-Path $cacheRoot) {
    $bin = Get-ChildItem $cacheRoot -Recurse -Filter 'bin.js' -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\node_modules\\@deepseek-ai\\dsh\\lib\\bin\.js$' } |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($bin) {
      $node = Get-Command node -ErrorAction SilentlyContinue
      if ($node) { return [pscustomobject]@{ Mode = 'npx-cache'; File = $node.Source; Args = @('"' + $bin.FullName + '"', 'web') } }
    }
  }
  # 3) npx 兜底（需要网络）
  $npx = Get-Command npx -ErrorAction SilentlyContinue
  if ($npx) {
    $src = $npx.Source
    if ($src -match '\.ps1$') {
      $alt = $src -replace '\.ps1$', '.cmd'
      if (Test-Path $alt) { $src = $alt }
    }
    return [pscustomobject]@{ Mode = 'npx'; File = $src; Args = @('--yes', '@deepseek-ai/dsh', 'web') }
  }
  return $null
}

# ============================================================
# 启动 / 停止 / 重启
# ============================================================
function Stop-ProcessTree([int]$procId) {
  $children = Get-CimInstance Win32_Process -Filter "ParentProcessId = $procId" -ErrorAction SilentlyContinue
  foreach ($c in $children) { Stop-ProcessTree ([int]$c.ProcessId) }
  Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
}

function Start-Dsh {
  if (Get-DshStatus) {
    Write-CL '  DSH 已在运行，无需重复启动。' 'warning'
    if (-not $NoBrowser -and $AutoOpen) { try { Start-Process $Url } catch {} }
    return $true
  }
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-CL '  ✗ 未找到 Node.js，请先安装: https://nodejs.org' 'error'
    Write-Log '启动失败: 未找到 node'
    return $false
  }
  $d = Find-Dsh
  if (-not $d) {
    Write-CL '  ✗ 未找到 dsh（全局 / npx 缓存均无），请先执行: npm i -g @deepseek-ai/dsh' 'error'
    Write-Log '启动失败: 未找到 dsh'
    return $false
  }
  Write-CL ("  正在以 {0} 模式启动 DSH ..." -f $d.Mode) 'text'
  Write-Log "启动 DSH (mode=$($d.Mode)): $($d.File) $($d.Args -join ' ')"
  $outLog = Join-Path $LogDir 'dsh-web.log'
  $errLog = Join-Path $LogDir 'dsh-web.err.log'
  try {
    $psi = Start-Process -FilePath $d.File -ArgumentList $d.Args -WorkingDirectory $WorkDir `
      -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru -ErrorAction Stop
  } catch {
    Write-CL ("  ✗ 进程启动失败: {0}" -f $_.Exception.Message) 'error'
    Write-Log "启动失败: $($_.Exception.Message)"
    return $false
  }
  Write-Log "DSH 进程 PID=$($psi.Id)"
  # 就绪等待：轮询端口，最多 $TimeoutSec 秒
  $ok = $false
  for ($i = 1; $i -le $TimeoutSec; $i++) {
    Start-Sleep -Seconds 1
    if (Get-DshStatus) { $ok = $true; break }
    if ($psi.HasExited) { break }
    if (($i % 10) -eq 0) { Write-C '.' 'dim' }
  }
  if (-not $ok) {
    Write-CL '' 'dim'
    Write-CL '  ✗ DSH 启动失败或超时。错误日志尾部：' 'error'
    if (Test-Path $errLog) { Get-Content $errLog -Tail 8 | ForEach-Object { Write-CL ("    " + $_) 'dim' } }
    Write-Log '启动失败: 超时或进程提前退出'
    return $false
  }
  Write-CL '' 'dim'
  Write-CL ("  ✓ DSH 已就绪  →  {0}" -f $Url) 'success'
  Write-Log "DSH 就绪: $Url"
  if (-not $NoBrowser -and $AutoOpen) {
    try { Start-Process $Url; Write-Log '已自动打开浏览器' }
    catch { Write-CL '  (无法自动打开浏览器，请手动访问)' 'warning' }
  }
  return $true
}

function Stop-Dsh {
  $st = Get-DshStatus
  if (-not $st) { Write-CL '  DSH 未在运行。' 'dim'; return $true }
  if (-not (Test-DshProcess $st)) {
    Write-CL ("  端口 {0} 被 {1} (PID {2}) 占用，非 DSH 实例，拒绝误杀。" -f $Port, $st.Name, $st.Pid) 'warning'
    Write-Log "停止被拒绝: 端口被非 DSH 进程占用 PID=$($st.Pid)"
    return $false
  }
  Write-CL ("  正在停止 DSH (PID {0}) ..." -f $st.Pid) 'text'
  Write-Log "停止 DSH PID=$($st.Pid)"
  Stop-ProcessTree $st.Pid
  for ($i = 0; $i -lt 10; $i++) {
    if (-not (Get-DshStatus)) { break }
    Start-Sleep -Milliseconds 500
  }
  if (Get-DshStatus) { Write-CL '  ✗ 停止失败（进程仍在监听）' 'error'; return $false }
  Write-CL '  ✓ DSH 已停止' 'success'
  Write-Log 'DSH 已停止'
  return $true
}

# ============================================================
# 菜单 / 日志
# ============================================================
function Show-Logs {
  Write-CL '  ── launcher.log（最近 20 行）' 'primary'
  $lf = Join-Path $LogDir 'launcher.log'
  if (Test-Path $lf) { Get-Content $lf -Tail 20 | ForEach-Object { Write-CL ("  " + $_) 'dim' } } else { Write-CL '  （暂无）' 'dim' }
  Write-CL '  ── dsh-web.err.log（最近 15 行）' 'primary'
  $ef = Join-Path $LogDir 'dsh-web.err.log'
  if (Test-Path $ef) { Get-Content $ef -Tail 15 | ForEach-Object { Write-CL ("  " + $_) 'warning' } } else { Write-CL '  （暂无）' 'dim' }
  Write-CL '  ── dsh-web.log（最近 15 行）' 'primary'
  $of = Join-Path $LogDir 'dsh-web.log'
  if (Test-Path $of) { Get-Content $of -Tail 15 | ForEach-Object { Write-CL ("  " + $_) 'dim' } } else { Write-CL '  （暂无）' 'dim' }
}

function Show-Menu {
  Write-CL '' 'dim'
  Write-Separator
  Show-Status
  Write-CL '' 'dim'
  Write-MenuRow '1' '启动 DSH' '2' '停止 DSH'
  Write-MenuRow '3' '重启 DSH' '4' '打开界面'
  Write-MenuRow '5' '查看日志' '0' '退出'
  Write-CL '' 'dim'
  Write-Separator
  Write-CL '  提示: 关闭窗口不会停止 DSH · 停止请用 [2]' 'dim'
  Write-CL '' 'dim'
  $choice = Read-Host '  › 请选择操作'
  Write-Log "菜单选择: $choice"
  switch ($choice) {
    '1' { $null = Start-Dsh }
    '2' { $null = Stop-Dsh }
    '3' { if (Stop-Dsh) { $null = Start-Dsh } }
    '4' { try { Start-Process $Url } catch { Write-CL '  无法打开浏览器' 'warning' } }
    '5' { Show-Logs }
    '0' { Write-CL '  再见！DSH 仍在后台运行。' 'dim'; Write-Log '退出 launcher'; exit }
    default { Write-CL '  无效选项，请输入 0-5' 'warning' }
  }
}

# ============================================================
# 自检模式
# ============================================================
if ($TestOnly) {
  $script:Pass = 0
  $script:Fail = 0
  function T([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:Pass++; Write-C ("  ✓  $name") 'success' }
    else     { $script:Fail++; Write-C ("  ✗  $name") 'error' }
    if ($detail) { Write-CL ("      └ " + $detail) 'dim' } else { Write-CL '' 'dim' }
  }
  Show-Banner
  Write-CL '  环境自检' 'primary'
  $node = Get-Command node -ErrorAction SilentlyContinue
  T 'Node.js' ($null -ne $node) $(if ($node) { "$($node.Source)  ($(& node --version))" } else { '未找到，请安装 https://nodejs.org' })
  $d = Find-Dsh
  T 'DSH 发现' ($null -ne $d) $(if ($d) { "模式: $($d.Mode)`n        └ $($d.File) $($d.Args -join ' ')" } else { '未找到（全局 / npx 缓存 / npx 均无）' })
  $st = Get-DshStatus
  if ($st) { T '端口探测' $true ("端口 {0} 被占用: PID={1} {2}  是否 DSH={3}" -f $Port, $st.Pid, $st.Name, (Test-DshProcess $st)) }
  else     { T '端口探测' $true ("端口 {0} 空闲" -f $Port) }
  T '配置读取' ($null -ne $Config) "port=$Port  timeout=$TimeoutSec  workDir=$WorkDir  autoOpen=$AutoOpen"
  $probe = Join-Path $LogDir '_selfcheck.tmp'
  try { Add-Content $probe 'ok' -Encoding UTF8; Remove-Item $probe -Force; T '日志写入' $true $LogDir }
  catch { T '日志写入' $false $_.Exception.Message }
  T '图标文件' (Test-Path (Join-Path $Root 'assets\dsh-launcher.ico')) (Join-Path $Root 'assets\dsh-launcher.ico')
  Write-CL '' 'dim'
  $okAll = ($script:Fail -eq 0)
  Write-C ("  结果: {0} 项通过 / {1} 项失败" -f $script:Pass, $script:Fail) $(if ($okAll) { 'success' } else { 'error' })
  Write-CL '' 'dim'
  exit $(if ($okAll) { 0 } else { 1 })
}

# ============================================================
# 一次性命令模式
# ============================================================
if ($Status)  { Show-Status;  exit 0 }
if ($Stop)    { if (Stop-Dsh) { exit 0 } else { exit 1 } }
if ($Start)   { if (Start-Dsh) { exit 0 } else { exit 1 } }
if ($Restart) {
  $null = Stop-Dsh
  if (Start-Dsh) { exit 0 } else { exit 1 }
}

# ============================================================
# 交互模式（默认）
# ============================================================
Show-Banner
Write-CL '' 'dim'
Write-Log "启动 launcher v$Version（交互模式）"
if (Get-DshStatus) {
  Write-CL '  DSH 已在运行，直接打开界面。' 'success'
  if (-not $NoBrowser -and $AutoOpen) { try { Start-Process $Url } catch {} }
} else {
  Start-Dsh
}
while ($true) { Show-Menu }
