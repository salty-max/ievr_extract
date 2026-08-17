<#
.SYNOPSIS
    Turns an installed copy of Inazuma Eleven: Victory Road into JSON bundles.

.DESCRIPTION
    Five stages, run in order by default:

      unpack   the two archives that matter, out of 5863
      mine     the Rust dataminer, then merge_db and export_json
      enrich   what the dataminer does not emit, and a check that no name placeholder survived
      verify   counts and sanity checks on the finished bundles
      clean    delete the intermediates, keeping the bundles

    Stages are independent. Re-run `enrich` alone after tweaking a step, or `clean` alone when
    the disk is full.

    Disk: unpacking takes about 200 MB, the databases about 60 MB, and a Rust target directory
    grows past 800 MB. `clean` frees all of it and keeps only out/.

.PARAMETER Stage
    all, unpack, mine, enrich, verify or clean.

.PARAMETER Keep
    With -Stage clean, keep the unpacked game files. Useful while investigating a column shift,
    since re-unpacking is the slow part.

.EXAMPLE
    .\run.ps1

.EXAMPLE
    .\run.ps1 -Stage clean
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'unpack', 'mine', 'enrich', 'verify', 'clean')]
    [string]$Stage = 'all',

    [string]$Work = (Join-Path $PSScriptRoot 'work'),
    [string]$Out  = (Join-Path $PSScriptRoot 'out'),
    [string]$Dataminer = "$env:USERPROFILE\Downloads\ievr_build\ievr_dataminer",
    [string]$Toolbox = "$env:USERPROFILE\Downloads\tools\ievr_toolbox-win64.exe",
    [string]$Packs = "${env:ProgramFiles(x86)}\Steam\steamapps\common\INAZUMA ELEVEN Victory Road\data\packs",
    [switch]$Keep
)

$ErrorActionPreference = "Stop"

# The dataminer resolves `extracted` and `output` relative to the current directory, so both
# names are fixed and only their parent is a parameter.
$extracted = Join-Path $Work 'extracted'
$output    = Join-Path $Work 'output'
$bin       = Join-Path $Dataminer 'target\dist'

function Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }

# The two archives worth unpacking, found by scanning every table of contents once. The names
# are hashes and will change with a game patch; assets\find-texture.ps1 rediscovers them.
$WANTED_ARCHIVES = @(
    '672c0647c5ff4adf150dc88695184817.cpk',   # gamedata
    'ef8937b0b455c4978123aab7acccdf13.cpk'    # text, all nine languages
)

if ($Stage -in 'all', 'unpack') {
    Step 'unpack'
    if (-not (Test-Path $Packs)) { throw "archives introuvables : $Packs" }
    if (-not (Test-Path $Toolbox)) { throw "toolbox introuvable : $Toolbox" }

    $stage = Join-Path $Work '_stage'
    $packStage = Join-Path $stage 'data\packs'
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $packStage, $extracted | Out-Null

    foreach ($name in $WANTED_ARCHIVES) {
        $source = Join-Path $Packs $name
        if (-not (Test-Path $source)) {
            throw "archive absente : $name`nUn patch a peut-etre renomme les archives ; relancer assets\find-texture.ps1 pour retrouver les bonnes."
        }
        # hard link rather than copy: these are multi-GB files on the same volume
        New-Item -ItemType HardLink -Path (Join-Path $packStage $name) -Target $source | Out-Null
    }

    & $Toolbox dump -i $stage -o $extracted 2>&1 | Select-Object -Last 3
    Remove-Item $stage -Recurse -Force
}

if ($Stage -in 'all', 'mine') {
    Step 'mine'
    if (-not (Test-Path $bin)) {
        throw "binaires absents : $bin`nConstruire d'abord : cd $Dataminer && cargo build --profile dist"
    }

    # ievr_dataminer wipes its output directory on every run, which is why enrichment comes
    # after and cannot be cached.
    Push-Location $Work
    try {
        & (Join-Path $bin 'ievr_dataminer.exe')
        if ($LASTEXITCODE) { throw "ievr_dataminer a echoue" }
        & (Join-Path $bin 'merge_db.exe') 'output' | Select-Object -Last 1
        & (Join-Path $bin 'export_json.exe') 'output' | Select-Object -Last 3
    } finally { Pop-Location }
}

if ($Stage -in 'all', 'enrich') {
    Step 'enrich'
    & (Join-Path $PSScriptRoot 'enrich.ps1') -Extract $extracted -Output $output -Bin $bin
}

if ($Stage -in 'all', 'verify') {
    Step 'verify'
    New-Item -ItemType Directory -Force -Path $Out | Out-Null
    foreach ($lang in @('en', 'fr', 'ja')) {
        $source = Join-Path $output "json\ievr.$lang.json"
        Copy-Item $source (Join-Path $Out "ievr.$lang.json") -Force

        $bundle = Get-Content $source -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host ("{0} : {1} personnages, {2} techniques, {3} passifs, {4} tactiques, {5} synergies, {6} equipements" -f
            $lang, $bundle.characters.Count, $bundle.hissatsu.Count, $bundle.passives.Count,
            $bundle.tactics.Count, $bundle.synergies.Count, $bundle.equipment.Count)

        # A section falling to zero is how a shifted column shows up: the threads are joined
        # with `let _ = handle.join()`, so a panic inside one is swallowed.
        foreach ($section in @('characters', 'hissatsu', 'passives', 'tactics', 'synergies', 'equipment', 'auras')) {
            if (-not $bundle.$section.Count) { throw "$lang : section $section vide - probablement un indice de colonne decale" }
        }
    }
    Write-Host "`nbundles ecrits dans $Out" -ForegroundColor Green
}

if ($Stage -in 'all', 'clean') {
    Step 'clean'
    $freed = 0
    $targets = @(
        @{ path = $output;                          why = 'sqlite et json de travail' },
        @{ path = (Join-Path $Dataminer 'target');  why = 'artefacts de compilation Rust' }
    )
    if (-not $Keep) {
        $targets += @{ path = $extracted; why = 'fichiers de jeu depaquetes' }
    }

    foreach ($t in $targets) {
        if (-not (Test-Path $t.path)) { continue }
        $size = (Get-ChildItem $t.path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        Remove-Item $t.path -Recurse -Force
        $freed += $size
        Write-Host ("  {0,-12:N0} Mo  {1}" -f ($size / 1MB), $t.why)
    }

    Write-Host ("`n{0:N0} Mo liberes. Les bundles restent dans {1}." -f ($freed / 1MB), $Out) -ForegroundColor Green
    if (-not $Keep) {
        Write-Host "Relancer -Stage unpack pour repartir des archives du jeu."
    }
}
