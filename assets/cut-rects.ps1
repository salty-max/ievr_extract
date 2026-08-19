<#
.SYNOPSIS
    Cut an atlas into sprites using the rectangle and name tables inside its own .g4tx header.

.DESCRIPTION
    An atlas is not an undocumented grid. Its header carries, after the DDS-less preamble:

      0x94            sub-rectangles, x y w h as u16, 24 bytes per record, until a zero u32
      then            one CRC32 per name - the atlas's own name first, then one per rectangle
      then            an offset table, then the names themselves as NUL terminated ASCII

    So every sprite has a position *and* a name, and the two are joined by position in the
    parallel tables. The join is self-checking: the stored hash must be the CRC32 of the name,
    which is how this script decides a header parsed correctly.

    That matters because for content atlases the name is the game's own string id -
    `icon_wht10020` is the tactic wht10020, `sf01001` is the synergy sf01001 - so the atlas
    labels itself and nothing has to be matched by eye. For UI atlases the name is a numbered
    artwork slot (`icon_teambuff19`, `icon_build_l02`) and the number is *not* the enum the data
    files use; that mapping lives in the menu code.

    Cutting by rectangles also catches sprites smaller than a grid cell: icon_teambuff packs
    eight 48x32 position badges into what looks like one 128x128 cell.

.EXAMPLE
    .\cut-rects.ps1 -G4tx icon_synergy.g4tx -Png icon_synergy.png -OutDir .\synergy

.EXAMPLE
    .\cut-rects.ps1 -G4tx icon_tactics.g4tx -Png icon_tactics.png -OutDir .\tactics -Trim
#>
param(
    [Parameter(Mandatory)][string]$G4tx,
    [Parameter(Mandatory)][string]$Png,
    [Parameter(Mandatory)][string]$OutDir,
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

$bytes = [System.IO.File]::ReadAllBytes($G4tx)

# The header ends where the DDS payload begins.
$dds = -1
for ($i = 0; $i -lt $bytes.Length - 4; $i++) {
    if ($bytes[$i] -eq 0x44 -and $bytes[$i+1] -eq 0x44 -and $bytes[$i+2] -eq 0x53 -and $bytes[$i+3] -eq 0x20) { $dds = $i; break }
}
if ($dds -lt 0) { throw "pas de charge DDS dans $G4tx" }

$rects = @()
for ($o = 0x94; $o + 24 -le $dds; $o += 24) {
    $w = [BitConverter]::ToUInt16($bytes, $o + 4)
    $h = [BitConverter]::ToUInt16($bytes, $o + 6)
    if ($w -eq 0 -or $h -eq 0 -or $w -gt 4096 -or $h -gt 4096) { break }
    $rects += [pscustomobject]@{
        x = [BitConverter]::ToUInt16($bytes, $o)
        y = [BitConverter]::ToUInt16($bytes, $o + 2)
        w = $w; h = $h
    }
}
$hashes = 0x94 + 24 * $rects.Count + 4

# Every printable run in the tail is a candidate name; index them by hash and let the parallel
# table pick. Anything that does not hash back is left unnamed rather than guessed.
$byHash = @{}
for ($p = $hashes; $p -lt $dds; $p++) {
    if ($bytes[$p] -lt 0x20 -or $bytes[$p] -gt 0x7e) { continue }
    $s = $p
    while ($p -lt $dds -and $bytes[$p] -ge 0x20 -and $bytes[$p] -le 0x7e) { $p++ }
    if ($p - $s -ge 3) {
        $name = [System.Text.Encoding]::ASCII.GetString($bytes, $s, $p - $s)
        $byHash[[G4txCrc]::Of($name)] = $name
    }
}

$img = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Png).Path)
if (Test-Path $OutDir) { Get-ChildItem $OutDir -File | Remove-Item -Force }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$named = 0
for ($k = 0; $k -lt $rects.Count; $k++) {
    $r = $rects[$k]
    $name = $byHash[[BitConverter]::ToUInt32($bytes, $hashes + 4 * ($k + 1))]
    if ($name) { $named++ } else { $name = "sprite_{0:d3}" -f $k }

    $x = $r.x; $y = $r.y; $w = $r.w; $h = $r.h
    if ($Trim) {
        # tighten onto the opaque pixels, which is what a hand cut icon looks like
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

"{0} sprites, {1} nommes par la table de hash du fichier" -f $rects.Count, $named
if ($named -ne $rects.Count) { "  {0} sans nom, ecrits en sprite_NNN" -f ($rects.Count - $named) }
