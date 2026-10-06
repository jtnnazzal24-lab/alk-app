# Regenerates all ALK launcher / web / splash icons for the Flutter app from the
# original (React Native/Expo) project assets, using .NET System.Drawing.
# Usage: powershell -ExecutionPolicy Bypass -File generate-icons.ps1

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$srcIcon    = "c:\tabiib\assets\images\icon.png"                     # 1024x1024 master icon
$srcFg      = "c:\tabiib\assets\images\android-icon-foreground.png"  # adaptive foreground (padded)
$srcLogo    = "c:\tabiib\assets\images\alk-logo.png"                 # in-app brand logo
$srcSplash  = "c:\tabiib\assets\images\splash-icon.png"              # splash logo
$srcMono    = "c:\tabiib\assets\images\android-icon-monochrome.png"

$flutter    = "c:\tabiib\alk_flutter"
$res        = "$flutter\android\app\src\main\res"
$assetsDir  = "$flutter\assets\images"
$webDir     = "$flutter\web"

New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null
foreach ($d in "mdpi","hdpi","xhdpi","xxhdpi","xxxhdpi") {
    New-Item -ItemType Directory -Force -Path "$res\mipmap-$d" | Out-Null
}
New-Item -ItemType Directory -Force -Path "$res\mipmap-anydpi-v26" | Out-Null

function Save-Resized([System.Drawing.Image]$img, [int]$size, [string]$path) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($img, 0, 0, $size, $size)
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "  wrote $path ($size x $size)"
}

function Save-Round([System.Drawing.Image]$img, [int]$size, [string]$path) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $path2d = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path2d.AddEllipse(0, 0, $size, $size)
    $g.SetClip($path2d)
    $g.DrawImage($img, 0, 0, $size, $size)
    $g.Dispose(); $path2d.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "  wrote $path ($size x $size, round)"
}

$icon = [System.Drawing.Image]::FromFile($srcIcon)
try {
    # density -> legacy launcher size (48dp)
    $densities = @{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }
    foreach ($d in $densities.Keys) {
        Save-Resized $icon $densities[$d] "$res\mipmap-$d\ic_launcher.png"
        Save-Round   $icon $densities[$d] "$res\mipmap-$d\ic_launcher_round.png"
    }
    # web icons + favicon
    Save-Resized $icon 192 "$webDir\icons\Icon-192.png"
    Save-Resized $icon 512 "$webDir\icons\Icon-512.png"
    Save-Resized $icon 48  "$webDir\favicon.png"
} finally { $icon.Dispose() }

# adaptive icon foreground layers: 108dp canvas (66dp visible safe zone already padded in source)
$fg = [System.Drawing.Image]::FromFile($srcFg)
try {
    foreach ($d in @{ mdpi = 162; hdpi = 243; xhdpi = 324; xxhdpi = 486; xxxhdpi = 648 }.GetEnumerator()) {
        Save-Resized $fg $d.Value "$res\mipmap-$($d.Key)\ic_launcher_foreground.png"
    }
} finally { $fg.Dispose() }

# copy brand assets into the Flutter app for in-app / splash usage
Copy-Item $srcLogo   "$assetsDir\alk-logo.png"   -Force
Copy-Item $srcSplash "$assetsDir\splash-icon.png" -Force
Copy-Item $srcIcon   "$assetsDir\app_icon.png"    -Force
Copy-Item $srcMono   "$assetsDir\android-icon-monochrome.png" -Force
Write-Host "  copied brand assets into $assetsDir"

Write-Host "DONE"