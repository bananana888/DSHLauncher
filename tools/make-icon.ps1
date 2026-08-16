<#
.SYNOPSIS
  从 PNG/JPG/BMP/ICO 源图生成多尺寸 ICO 图标（PNG 压缩条目，兼容 Windows Vista+）。

.DESCRIPTION
  dsh-launcher 的图标生成器，可复用：
  · 自动输出 16/24/32/48/64/128/256 共 7 个尺寸，资源管理器小图标也清晰
  · 小尺寸（默认 <64px）自动生成「实心剪影版」：对源图的线条稿做边缘洪泛填充，
    小图标不再是断线，而是一个轮廓清晰的实心鲸鱼；大尺寸保留官方细节版
  · 源图为 ICO 时自动取第一帧；非 32bpp ARGB 时自动转换（保留透明通道）
  · 透明背景保留，输出为 PNG 压缩的现代 ICO

.PARAMETER Source
  源图片路径（.png / .jpg / .bmp / .ico）

.PARAMETER Output
  输出 .ico 路径（相对当前目录或绝对路径均可）

.PARAMETER Sizes
  可选尺寸列表，默认 16,24,32,48,64,128,256

.PARAMETER SolidBelow
  小于该尺寸（含）的条目使用实心剪影版，默认 64

.EXAMPLE
  .\tools\make-icon.ps1 -Source assets\logo-source.png -Output assets\dsh-launcher.ico
  .\tools\make-icon.ps1 -Source logo.png -Output icon.ico -Sizes 32,48,256 -SolidBelow 48
#>
param(
  [Parameter(Mandatory = $true)][string]$Source,
  [Parameter(Mandatory = $true)][string]$Output,
  [int[]]$Sizes = @(16, 24, 32, 48, 64, 128, 256),
  [int]$SolidBelow = 64
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# ---------- 载入源图 ----------
$srcPath = if ([System.IO.Path]::IsPathRooted($Source)) { $Source } else { Join-Path (Get-Location) $Source }
if (-not (Test-Path $srcPath)) { throw "源图不存在: $srcPath" }

if ([System.IO.Path]::GetExtension($srcPath) -eq '.ico') {
  $icon = New-Object System.Drawing.Icon($srcPath)
  $src = $icon.ToBitmap()
  $icon.Dispose()
} else {
  $src = [System.Drawing.Image]::FromFile($srcPath)
}

# 统一为 32bpp ARGB（带透明通道）
if ($src.PixelFormat -ne [System.Drawing.Imaging.PixelFormat]::Format32bppArgb) {
  $conv = New-Object System.Drawing.Bitmap($src.Width, $src.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($conv)
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($src, 0, 0, $src.Width, $src.Height)
  $g.Dispose()
  $src.Dispose()
  $src = $conv
}

function ConvertTo-PngBytes([System.Drawing.Bitmap]$bmp) {
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  # 注意：PowerShell 会把函数输出的 byte[] 枚举成 Object[]，导致 BinaryWriter
  # 错误绑定到 Write(byte) 只写第一个字节；用一元逗号包一层阻止枚举。
  return ,[byte[]]$ms.ToArray()
}

# ---------- 实心剪影版 ----------
# 思路：线稿的内部区域被笔画包围，从图像边缘洪泛填充能到达的透明格，
# 剩下的（笔画 + 未被到达的内部）即完整鲸鱼形状，填充为品牌蓝。
# 全部在内存数组中计算，速度远快于逐像素 GetPixel。
function New-SolidMask([System.Drawing.Bitmap]$img, [int]$radius = 3, [int]$threshold = 100) {
  $W = $img.Width; $H = $img.Height
  $A = New-Object 'int[,]' $W, $H
  for ($y = 0; $y -lt $H; $y++) { for ($x = 0; $x -lt $W; $x++) { $A[$x, $y] = $img.GetPixel($x, $y).A } }

  # 笔画掩码
  $stroke = New-Object 'bool[,]' $W, $H
  for ($y = 0; $y -lt $H; $y++) { for ($x = 0; $x -lt $W; $x++) { if ($A[$x, $y] -ge $threshold) { $stroke[$x, $y] = $true } } }
  # 膨胀（闭合细小缺口，防止填充从缺口泄漏）
  $dil = New-Object 'bool[,]' $W, $H
  for ($y = 0; $y -lt $H; $y++) {
    for ($x = 0; $x -lt $W; $x++) {
      if ($stroke[$x, $y]) { $dil[$x, $y] = $true; continue }
      for ($dy = -$radius; $dy -le $radius -and -not $dil[$x, $y]; $dy++) {
        $yy = $y + $dy; if ($yy -lt 0 -or $yy -ge $H) { continue }
        for ($dx = -$radius; $dx -le $radius; $dx++) {
          $xx = $x + $dx; if ($xx -lt 0 -or $xx -ge $W) { continue }
          if ($stroke[$xx, $yy]) { $dil[$x, $y] = $true; break }
        }
      }
    }
  }
  # 从边缘洪泛
  $vis = New-Object 'bool[,]' $W, $H
  $q = New-Object System.Collections.Queue
  for ($x = 0; $x -lt $W; $x++) {
    if (-not $dil[$x, 0]) { $vis[$x, 0] = $true; $q.Enqueue(@($x, 0)) }
    if (-not $dil[$x, ($H - 1)]) { $vis[$x, ($H - 1)] = $true; $q.Enqueue(@($x, ($H - 1))) }
  }
  for ($y = 0; $y -lt $H; $y++) {
    if (-not $dil[0, $y]) { $vis[0, $y] = $true; $q.Enqueue(@(0, $y)) }
    if (-not $dil[($W - 1), $y]) { $vis[($W - 1), $y] = $true; $q.Enqueue(@(($W - 1), $y)) }
  }
  while ($q.Count -gt 0) {
    $c = $q.Dequeue(); $cx = $c[0]; $cy = $c[1]
    foreach ($n in @(@(($cx + 1), $cy), @(($cx - 1), $cy), @($cx, ($cy + 1)), @($cx, ($cy - 1)))) {
      $nx = $n[0]; $ny = $n[1]
      if ($nx -lt 0 -or $nx -ge $W -or $ny -lt 0 -or $ny -ge $H) { continue }
      if (-not $dil[$nx, $ny] -and -not $vis[$nx, $ny]) { $vis[$nx, $ny] = $true; $q.Enqueue(@($nx, $ny)) }
    }
  }
  # 填充：笔画或未访问（内部）→ 蓝色；其余透明
  $solid = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  for ($y = 0; $y -lt $H; $y++) {
    for ($x = 0; $x -lt $W; $x++) {
      if ($dil[$x, $y] -or -not $vis[$x, $y]) { $solid.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, 77, 107, 254)) }
    }
  }
  return $solid
}

# ---------- 缩放到各尺寸 ----------
$solidMask = $null
$entries = New-Object System.Collections.ArrayList
foreach ($s in $Sizes) {
  $useSolid = ($s -lt $SolidBelow)
  if ($useSolid -and -not $solidMask) { $solidMask = New-SolidMask $src }
  $from = if ($useSolid) { $solidMask } else { $src }
  $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($from, 0, 0, $s, $s)
  $g.Dispose()
  [void]$entries.Add(@{ size = $s; png = (ConvertTo-PngBytes $bmp); solid = $useSolid })
  $bmp.Dispose()
}
if ($solidMask) { $solidMask.Dispose() }
$src.Dispose()

# ---------- 组装 ICO ----------
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$bw.Write([uint16]0)            # reserved
$bw.Write([uint16]1)            # type: icon
$bw.Write([uint16]$entries.Count)
$offset = 6 + 16 * $entries.Count
foreach ($e in $entries) {
  $dim = if ($e.size -ge 256) { 0 } else { $e.size }   # 0 表示 256
  $bw.Write([byte]$dim)                                 # width
  $bw.Write([byte]$dim)                                 # height
  $bw.Write([byte]0)                                    # color count
  $bw.Write([byte]0)                                    # reserved
  $bw.Write([uint16]1)                                  # planes
  $bw.Write([uint16]32)                                 # bit count
  $bw.Write([uint32]$e.png.Length)                      # bytes in res
  $bw.Write([uint32]$offset)                            # image offset
  $offset += $e.png.Length
}
foreach ($e in $entries) { $bw.Write([byte[]]$e.png) }
$bw.Flush()

$outPath = if ([System.IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path (Get-Location) $Output }
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($outPath)) | Out-Null
[System.IO.File]::WriteAllBytes($outPath, $ms.ToArray())
$bw.Dispose()
$ms.Dispose()

$solidInfo = ($entries | Where-Object { $_.solid } | ForEach-Object { $_.size }) -join ','
Write-Host "OK: $outPath ($($entries.Count) sizes: $($Sizes -join ', '))"
Write-Host "    实心剪影版: ${solidInfo}px（其余为细节版）"
