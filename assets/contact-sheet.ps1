Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

# zoom.ps1 <out.png> <file1> <file2> ...
$out = $args[0]
$files = $args[1..($args.Count - 1)]

$cell = 150
$cols = [math]::Min($files.Count, 8)
$rows = [math]::Ceiling($files.Count / $cols)

$bmp = New-Object System.Drawing.Bitmap(($cols * $cell), ($rows * $cell))
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(255, 20, 20, 30))
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$font = New-Object System.Drawing.Font("Consolas", 10)
$brush = [System.Drawing.Brushes]::Yellow

for ($i = 0; $i -lt $files.Count; $i++) {
    $img = [System.Drawing.Image]::FromFile($files[$i])
    $col = $i % $cols
    $row = [math]::Floor($i / $cols)

    $scale = [math]::Min(($cell - 30) / $img.Width, ($cell - 30) / $img.Height)
    $w = [int]($img.Width * $scale)
    $h = [int]($img.Height * $scale)

    $g.DrawImage($img, ($col * $cell + ($cell - $w) / 2), ($row * $cell + 20 + ($cell - 20 - $h) / 2), $w, $h)
    $label = [System.IO.Path]::GetFileNameWithoutExtension($files[$i]) -replace '^icon_', ''
    $g.DrawString($label, $font, $brush, ($col * $cell + 3), ($row * $cell + 2))
    $img.Dispose()
}

$g.Dispose()
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "$out"
