<#
.SYNOPSIS
    Finds which .cpk holds a given texture, and optionally unpacks just that one.

.DESCRIPTION
    The archives carry no index the game ships separately: each .cpk starts with its own
    table of contents, XOR encrypted with a key that is the CRC32 of the archive's own file
    name. Decrypt the first few MB of each and the file names fall out as plain text.

    That is the whole trick behind unpacking 200 MB instead of 56.7 GB - you scan the tables
    of contents, find the two or three archives that matter, and leave the rest alone.

    Texture paths are stored as bare file names, without directories, so search by base name:
    icon_common.g4tx, not data/dx11/menu/.../icon_common.g4tx.

.EXAMPLE
    .\find-texture.ps1 -Pattern 'icon_(common|tactics|synergy)'

.EXAMPLE
    .\find-texture.ps1 -Pattern '^icon_class' -Unpack -Out D:\ievr\work\textures
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Pattern,
    [string]$Packs = "${env:ProgramFiles(x86)}\Steam\steamapps\common\INAZUMA ELEVEN Victory Road\data\packs",
    [string]$Toolbox = "$env:USERPROFILE\Downloads\tools\ievr_toolbox-win64.exe",
    [switch]$Unpack,
    [string]$Out = "$env:USERPROFILE\Downloads\work\textures",
    [int]$ProbeMb = 8
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'cri_lib.ps1')

if (-not (Test-Path $Packs)) { throw "archives introuvables : $Packs" }
$regex = [regex]$Pattern

$hits = @{}
$archives = Get-ChildItem $Packs -Filter *.cpk
Write-Host ("scan de {0} archives..." -f $archives.Count)

foreach ($archive in $archives) {
    $length = [int][Math]::Min($ProbeMb * 1MB, [long]$archive.Length)
    $length = $length - ($length % 4)

    $stream = [System.IO.File]::OpenRead($archive.FullName)
    $buffer = New-Object byte[] $length
    $read = $stream.Read($buffer, 0, $length)
    $stream.Close()

    $plain = [Cri3]::DecryptRange($buffer, 0, $read, [Cri3]::ComputeKey($archive.Name))
    $text = [System.Text.Encoding]::ASCII.GetString($plain)

    foreach ($match in [regex]::Matches($text, '[A-Za-z0-9_\.\-]{4,90}\.g4tx(?=\x00)')) {
        if (-not $regex.IsMatch($match.Value)) { continue }
        if (-not $hits.ContainsKey($match.Value)) { $hits[$match.Value] = $archive }
    }
}

if (-not $hits.Count) { Write-Host "aucune texture ne correspond a $Pattern"; return }

$hits.GetEnumerator() | Sort-Object Key | ForEach-Object {
    "{0,-44} {1}" -f $_.Key, $_.Value.Name
}

if (-not $Unpack) { return }

# Hard link each wanted archive into a staging tree, because the toolbox unpacks a directory
# rather than a single file, and copying multi-GB archives to select two of them is silly.
$stage = Join-Path $Out '_stage'
$packStage = Join-Path $stage 'data\packs'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $packStage | Out-Null

foreach ($archive in ($hits.Values | Sort-Object FullName -Unique)) {
    New-Item -ItemType HardLink -Path (Join-Path $packStage $archive.Name) -Target $archive.FullName | Out-Null
}
Write-Host ("`nextraction de {0} archive(s)..." -f ($hits.Values | Sort-Object FullName -Unique).Count)

& $Toolbox dump -i $stage -o $Out 2>&1 | Select-Object -Last 3
Remove-Item $stage -Recurse -Force

Get-ChildItem $Out -Recurse -File -Filter *.g4tx | ForEach-Object {
    "  {0}" -f $_.FullName.Replace("$Out\", '')
}
