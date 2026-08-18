<#
.SYNOPSIS
    Cut an atlas into sprites using the rectangle table inside its own .g4tx header.

.DESCRIPTION
    Prefer this over slice-grid.ps1. A .g4tx is a header followed by a DDS, and the header
    carries an explicit list of sub-rectangles - x, y, w, h as u16, 24 bytes per record,
    starting at 0x94 and running until the DDS magic. So the sprites do not have to be guessed
    from transparent gutters: the game's own rects are right there, including the ones smaller
    than a grid cell that a grid pass silently merges (icon_teambuff packs eight 48x32 position
    badges into what looks like one 128x128 cell).

    Files are named by their index in that table, which is the atlas packer's insertion order -
    an expanding L-shell, not row-major. That index is NOT the id the data uses; see the README.

.EXAMPLE
    .\cut-rects.ps1 -G4tx icon_teambuff.g4tx -Png icon_teambuff.png -OutDir .\sprites
#>
param([string]$G4tx, [string]$Png, [string]$OutDir, [int]$Start = 0x94, [int]$Stride = 24)
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

$b = [System.IO.File]::ReadAllBytes($G4tx)
$dds = -1
for ($i = 0; $i -lt $b.Length - 4; $i++) {
    if ($b[$i] -eq 0x44 -and $b[$i+1] -eq 0x44 -and $b[$i+2] -eq 0x53 -and $b[$i+3] -eq 0x20) { $dds = $i; break }
}

$img = [System.Drawing.Bitmap]::FromFile($Png)
if (Test-Path $OutDir) { Get-ChildItem $OutDir -File | Remove-Item -Force }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$n = 0
for ($o = $Start; $o + $Stride -le $dds; $o += $Stride) {
    $x = [BitConverter]::ToUInt16($b, $o)
    $y = [BitConverter]::ToUInt16($b, $o + 2)
    $w = [BitConverter]::ToUInt16($b, $o + 4)
    $h = [BitConverter]::ToUInt16($b, $o + 6)
    if ($w -eq 0 -or $h -eq 0 -or $x + $w -gt $img.Width -or $y + $h -gt $img.Height) { break }

    $crop = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($crop)
    $g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)),
                 (New-Object System.Drawing.Rectangle($x, $y, $w, $h)), [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    $crop.Save(("{0}\sprite_{1:d3}.png" -f $OutDir, $n), [System.Drawing.Imaging.ImageFormat]::Png)
    $crop.Dispose()
    $n++
}
$img.Dispose()
"$n sprites decoupes d'apres la table de rects"
