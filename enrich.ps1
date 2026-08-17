<#
.SYNOPSIS
    Adds everything the Kizuna bundles need that the dataminer does not emit itself.

.DESCRIPTION
    The Rust dataminer writes the databases and a first cut of the JSON bundles. These steps
    read game configs it does not touch - skill learn tables, the drop and Player Universe
    pools, the aura lottery - and fold the result into the bundles in place.

    Order matters: spirit_pool writes the list add_drop_flag reads, and add_legend_tail adds
    the furigana-free variants of fields the steps before it create.

    Every step is idempotent. Re-running the whole chain on already enriched bundles is safe;
    re-running it after a fresh export is what you actually want.

.PARAMETER Bin
    Where the dataminer binaries are. Note that Smart App Control can block a freshly built
    unsigned binary - if a step dies with "An Application Control policy has blocked this
    file", point this at a build Windows has already accepted.

.EXAMPLE
    .\enrich.ps1 -Extract D:\ievr\extracted -Output D:\ievr\output -Bin D:\ievr\bin
#>
[CmdletBinding()]
param(
    [string]$Extract = "$env:USERPROFILE\Downloads\extracted",
    [string]$Output  = "$env:USERPROFILE\Downloads\output",
    [string]$Bin     = "$env:USERPROFILE\Downloads\ievr_build\ievr_dataminer\target\release"
)

$ErrorActionPreference = "Stop"

foreach ($path in @($Extract, $Output, $Bin)) {
    if (-not (Test-Path $path)) { throw "chemin introuvable : $path" }
}
if (-not (Test-Path "$Output\json\ievr.en.json")) {
    throw "pas de bundles dans $Output\json - lancer ievr_dataminer, merge_db puis export_json d'abord"
}

$env:IEVR_EXTRACT = $Extract
$env:IEVR_OUTPUT  = $Output
$env:IEVR_BIN     = $Bin

# spirit_pool first: it writes droppable_ids.txt, which add_drop_flag consumes.
$steps = @(
    @('spirit_pool.ps1',      'quels personnages tombent en esprit'),
    @('add_skills.ps1',       'techniques apprises et niveau'),
    @('add_members.ps1',      'membres de chaque synergie'),
    @('add_aura_type.ps1',    'keshin, armed, mixi max, totem...'),
    @('add_gender.ps1',       'genre'),
    @('add_names.ps1',        'nom de famille et prenom'),
    @('add_nickname.ps1',     'nom court affiche sur le terrain'),
    @('add_drop_flag.ps1',    'drapeau spirit_drop'),
    @('add_locations.ps1',    'ou trouver chaque esprit'),
    @('add_legends.ps1',      'legendes position et style'),
    @('add_legend_tail.ps1',  'legende des categories, variantes sans furigana')
)

$index = 0
foreach ($step in $steps) {
    $index++
    Write-Host ("[{0}/{1}] {2} - {3}" -f $index, $steps.Count, $step[0], $step[1]) -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "enrich\$($step[0])")
    if ($LASTEXITCODE) { throw "$($step[0]) a echoue" }
}

# The bundles must come out with no unresolved placeholder left. <VALUE> is the passive
# magnitude and is meant to survive; anything else means a step read a raw config instead of
# the resolved database.
Write-Host ""
$leaks = 0
foreach ($lang in @('en', 'fr', 'ja')) {
    $raw = (Get-Content "$Output\json\ievr.$lang.json" -Raw -Encoding UTF8) -replace '\\u003c', '<' -replace '\\u003e', '>'
    $found = [regex]::Matches($raw, '<[^>\\"]{1,40}>') | Where-Object { $_.Value -ne '<VALUE>' }
    $leaks += $found.Count
    Write-Host ("{0} : {1} substituant(s) non resolu(s)" -f $lang, $found.Count) `
        -ForegroundColor $(if ($found.Count) { 'Red' } else { 'Green' })
    $found | ForEach-Object { $_.Value } | Group-Object | ForEach-Object {
        Write-Host ("    {0} x{1}" -f $_.Name, $_.Count) -ForegroundColor Red
    }
}
if ($leaks) { throw "$leaks substituant(s) non resolu(s) - voir tools/dataminer/README.md" }

