Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

# grid_slice.ps1 <atlas.png> <out_dir> <cols> <rows> [prefix]
$atlas  = $args[0]
$outDir = $args[1]
$cols   = [int]$args[2]
$rows   = [int]$args[3]
$prefix = if ($args.Count -gt 4) { $args[4] } else { 'cell' }

if (Test-Path $outDir) { Remove-Item -LiteralPath $outDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$img = [System.Drawing.Bitmap]::FromFile($atlas)
$cw = $img.Width / $cols
$ch = $img.Height / $rows
Write-Output ("atlas {0}x{1}  cellule {2}x{3}" -f $img.Width, $img.Height, [math]::Round($cw,1), [math]::Round($ch,1))

# Read the whole bitmap once
$rect = New-Object System.Drawing.Rectangle(0, 0, $img.Width, $img.Height)
$data = $img.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bytes = New-Object byte[] ($data.Stride * $img.Height)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
$img.UnlockBits($data)
$stride = $data.Stride

$kept = 0; $empty = 0
for ($r = 0; $r -lt $rows; $r++) {
    for ($c = 0; $c -lt $cols; $c++) {
        $x0 = [int]([math]::Round($c * $cw))
        $y0 = [int]([math]::Round($r * $ch))
        $x1 = [int]([math]::Round(($c + 1) * $cw)) - 1
        $y1 = [int]([math]::Round(($r + 1) * $ch)) - 1

        # Tight bounds of the opaque pixels inside this cell
        $minX = $x1; $minY = $y1; $maxX = $x0; $maxY = $y0; $any = $false
        for ($y = $y0; $y -le $y1; $y++) {
            $rowBase = $y * $stride
            for ($x = $x0; $x -le $x1; $x++) {
                if ($bytes[$rowBase + $x * 4 + 3] -ge 16) {
                    $any = $true
                    if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
                    if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
                }
            }
        }

        $index = $r * $cols + $c
        if (-not $any) { $empty++; continue }

        $w = $maxX - $minX + 1
        $h = $maxY - $minY + 1
        $crop = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($crop)
        $g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)),
                     (New-Object System.Drawing.Rectangle($minX, $minY, $w, $h)),
                     [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
        $crop.Save(("{0}\{1}_{2:d3}.png" -f $outDir, $prefix, $index), [System.Drawing.Imaging.ImageFormat]::Png)
        $crop.Dispose()
        $kept++
    }
}

$img.Dispose()
Write-Output "cases pleines : $kept    vides : $empty"
