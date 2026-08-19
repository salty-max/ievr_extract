<#
.SYNOPSIS
    Cut a .g4tx into sprites, each written under the name the game gives it.

.DESCRIPTION
    A .g4tx header carries the names of what it holds, hashed and then spelled out:

      0x94      sub-rectangles, x y w h as u16, 24 bytes per record, ending at a zero u32
      later     one CRC32 per name, in the same order as the sprites
      later     a u16 offset table, then the names as NUL terminated ASCII

    Two layouts use it. An **atlas** has the rectangle table and one DDS: the first name is the
    atlas itself, the rest line up with the rectangles. A **texture array** has no rectangle
    table and one DDS per name, in fixed size blocks - `icon_item10` is 51 separate 256x256
    textures, one per currency. This script detects which and handles both.

    The pairing is not assumed: the run of hashes is located by searching for the CRC32 of the
    first name, then checked against every following name. A file whose hashes do not line up is
    reported rather than silently mislabelled.

    For content atlases the name is the game's own string id, so nothing needs matching by eye:
    `icon_wht10020` is the tactic, `sf01001` is the synergy, `tk_hr000001` is the currency. For UI
    atlases it is a numbered artwork slot (`icon_teambuff19`) and the number is not the enum the
    data files use.

.PARAMETER G4tx
    The .g4tx to cut. For an atlas, -Png must also be given (the decoded sheet); for a texture
    array the slices are decoded here, which needs -Converter.

.EXAMPLE
    .\cut-rects.ps1 -G4tx icon_synergy.g4tx -Png icon_synergy.png -OutDir .\synergy -Trim

.EXAMPLE
    .\cut-rects.ps1 -G4tx icon_item10.g4tx -OutDir .\currencies -Converter ..\bin\g4tx_to_png.exe
#>
param(
    [Parameter(Mandatory)][string]$G4tx,
    [string]$Png,
    [Parameter(Mandatory)][string]$OutDir,
    [string]$Converter,
    [string]$Include,
    [string]$Prefix = '',
    [switch]$Trim
)
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System; using System.Text;
public static class G4txCrc {
    static uint[] t;
    static G4txCrc(){ t = new uint[256];
        for (uint i=0;i<256;i++){ uint c=i; for(int k=0;k<8;k++) c=((c&1)!=0)?(0xEDB88320u^(c>>1)):(c>>1); t[i]=c; } }
    public static uint Of(string s){ byte[] b=Encoding.ASCII.GetBytes(s); uint c=0xFFFFFFFFu;
        foreach(byte x in b) c=t[(c^x)&0xFF]^(c>>8); return c^0xFFFFFFFFu; }
}
"@ -ErrorAction SilentlyContinue

$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $G4tx).Path)

# Where every DDS payload starts. One means an atlas, several mean a texture array.
$dds = @()
for ($i = 0; $i -lt $bytes.Length - 4; $i++) {
    if ($bytes[$i] -eq 0x44 -and $bytes[$i+1] -eq 0x44 -and $bytes[$i+2] -eq 0x53 -and $bytes[$i+3] -eq 0x20) { $dds += $i }
}
if (-not $dds.Count) { throw "pas de charge DDS dans $G4tx" }
$headerEnd = $dds[0]

# One DDS is an atlas, several are a texture array. Decide on that rather than on whether the
# bytes at 0x94 happen to look like a rectangle - in icon_item10 they do, and they are not one.
$isArray = $dds.Count -gt 1

$rects = @()
for ($o = 0x94; -not $isArray -and $o + 24 -le $headerEnd; $o += 24) {
    $w = [BitConverter]::ToUInt16($bytes, $o + 4)
    $h = [BitConverter]::ToUInt16($bytes, $o + 6)
    if ($w -eq 0 -or $h -eq 0 -or $w -gt 4096 -or $h -gt 4096) { break }
    $rects += [pscustomobject]@{
        x = [BitConverter]::ToUInt16($bytes, $o); y = [BitConverter]::ToUInt16($bytes, $o + 2); w = $w; h = $h
    }
}

# Names, in file order, which is also the order of the hashes and of the sprites.
$names = @()
for ($p = 0x94; $p -lt $headerEnd; $p++) {
    if ($bytes[$p] -lt 0x20 -or $bytes[$p] -gt 0x7e) { continue }
    $s = $p
    while ($p -lt $headerEnd -and $bytes[$p] -ge 0x20 -and $bytes[$p] -le 0x7e) { $p++ }
    if ($p - $s -ge 3 -and $bytes[$p] -eq 0) { $names += [System.Text.Encoding]::ASCII.GetString($bytes, $s, $p - $s) }
}
if (-not $names.Count) { throw "aucun nom lisible dans l'en-tete de $G4tx" }

# Find the hash run by looking for the first name's CRC32, then check the rest follow it.
$first = [G4txCrc]::Of($names[0])
$hashes = -1
for ($o = 0; $o + 4 -le $headerEnd; $o++) {
    if ([BitConverter]::ToUInt32($bytes, $o) -ne $first) { continue }
    $ok = $true
    for ($k = 1; $k -lt [Math]::Min($names.Count, 8); $k++) {
        if ($o + 4 * $k + 4 -gt $headerEnd -or
            [BitConverter]::ToUInt32($bytes, $o + 4 * $k) -ne [G4txCrc]::Of($names[$k])) { $ok = $false; break }
    }
    if ($ok) { $hashes = $o; break }
}
if ($hashes -lt 0) { throw "les hachages ne concordent pas avec les noms dans $G4tx" }
$checked = 0
for ($k = 0; $k -lt $names.Count; $k++) {
    if ($hashes + 4 * $k + 4 -le $headerEnd -and
        [BitConverter]::ToUInt32($bytes, $hashes + 4 * $k) -eq [G4txCrc]::Of($names[$k])) { $checked++ }
}

if (Test-Path $OutDir) { Get-ChildItem $OutDir -File | Remove-Item -Force }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not $isArray) {
    # --- atlas: one sheet, name 0 is the atlas itself ---------------------------------------
    if (-not $Png) { throw "-Png est requis pour un atlas" }
    if ($names.Count -ne $rects.Count + 1) {
        Write-Output ("  attention : {0} noms pour {1} rects" -f $names.Count, $rects.Count)
    }
    $img = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Png).Path)
    for ($k = 0; $k -lt $rects.Count; $k++) {
        $name = if ($k + 1 -lt $names.Count) { $names[$k + 1] } else { "sprite_{0:d3}" -f $k }
        if ($Include -and $name -notmatch $Include) { continue }
        $r = $rects[$k]; $x = $r.x; $y = $r.y; $w = $r.w; $h = $r.h
        if ($Trim) {
            $minX = $x + $w; $minY = $y + $h; $maxX = $x - 1; $maxY = $y - 1
            for ($py = $y; $py -lt $y + $h; $py++) { for ($px = $x; $px -lt $x + $w; $px++) {
                if ($img.GetPixel($px, $py).A -ge 16) {
                    if ($px -lt $minX) { $minX = $px }; if ($px -gt $maxX) { $maxX = $px }
                    if ($py -lt $minY) { $minY = $py }; if ($py -gt $maxY) { $maxY = $py }
                } } }
            if ($maxX -ge $minX) { $x = $minX; $y = $minY; $w = $maxX - $minX + 1; $h = $maxY - $minY + 1 }
        }
        $crop = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($crop)
        $g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)),
                     (New-Object System.Drawing.Rectangle($x, $y, $w, $h)), [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
        $crop.Save((Join-Path $OutDir "$Prefix$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $crop.Dispose()
    }
    $img.Dispose()
    "atlas : {0} sprites, {1}/{2} noms verifies par leur hash" -f $rects.Count, $checked, $names.Count
} else {
    # --- texture array: one fixed size DDS block per name -----------------------------------
    if (-not $Converter) { throw "-Converter (g4tx_to_png.exe) est requis pour un tableau de textures" }
    if ($names.Count -ne $dds.Count) {
        Write-Output ("  attention : {0} noms pour {1} textures" -f $names.Count, $dds.Count)
    }
    $block = if ($dds.Count -gt 1) { $dds[1] - $dds[0] } else { $bytes.Length - $dds[0] }
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("g4tx_slice_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    try {
        $wanted = @()
        for ($k = 0; $k -lt [Math]::Min($names.Count, $dds.Count); $k++) {
            if ($Include -and $names[$k] -notmatch $Include) { continue }
            # a header plus one block is a valid single texture .g4tx
            $slice = New-Object byte[] ($headerEnd + $block)
            [Array]::Copy($bytes, 0, $slice, 0, $headerEnd)
            [Array]::Copy($bytes, $dds[$k], $slice, $headerEnd, [Math]::Min($block, $bytes.Length - $dds[$k]))
            [System.IO.File]::WriteAllBytes((Join-Path $stage "$Prefix$($names[$k]).g4tx"), $slice)
            $wanted += $names[$k]
        }
        & $Converter $stage $OutDir | Out-Null
        Get-ChildItem $OutDir -Filter *.g4tx -ErrorAction SilentlyContinue | Remove-Item -Force
    } finally { Remove-Item $stage -Recurse -Force }
    "tableau : {0} textures, {1} extraites, {2}/{3} noms verifies par leur hash" -f
        $dds.Count, (Get-ChildItem $OutDir -Filter *.png).Count, $checked, $names.Count
}
