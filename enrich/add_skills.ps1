$ErrorActionPreference = "Stop"

$showTable = "$env:IEVR_BIN\show_table.exe"
$gamedata  = "$env:IEVR_EXTRACT\data\common\gamedata\character"
$jsonDir   = "$env:IEVR_OUTPUT\json"

function Split-Row([string]$line) {
    [regex]::Matches($line, 'i:(-?\d+)|"([^"]*)"') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
}

# chara_base column 0 is the key chara_param joins on; column 2 is the id the bundles expose
$charaBase = (Get-ChildItem $gamedata -Filter "chara_base_*.cfg.bin" | Select-Object -First 1).FullName
$indexOfBase = @{}
foreach ($line in (& $showTable $charaBase CHARA_BASE_INFO_LIST 20000 2>&1)) {
    if ($line -notmatch '^CHARA_BASE_INFO\s') { continue }
    $c = Split-Row $line
    if (-not $indexOfBase.ContainsKey($c[0])) { $indexOfBase[$c[0]] = [int]$c[2] }
}

# Columns 11..22 are six (skill id, level) pairs; 23..28 are a second, higher-level branch.
$learnColumns = 11, 13, 15, 17, 19, 21
$altColumns   = 23, 25, 27

$charaParam = (Get-ChildItem $gamedata -Filter "chara_param_*.cfg.bin" | Select-Object -First 1).FullName
$byKind = @{ characters = @{}; heroes = @{}; basaras = @{} }

foreach ($line in (& $showTable $charaParam CHARA_PARAM_INFO_LIST 40000 2>&1)) {
    if ($line -notmatch '^CHARA_PARAM_INFO\s') { continue }
    $r = Split-Row $line
    if (-not $indexOfBase.ContainsKey($r[1])) { continue }
    $index = $indexOfBase[$r[1]]

    # Same split the dataminer applies when it fills characters / heroes / basaras
    $rarity = [int]$r[41]
    $fullAlt = -not ($altColumns | Where-Object { $r[$_] -eq '0' })
    $kind = switch ($rarity) {
        0       { if ($fullAlt) { 'characters' } else { $null } }
        8       { if ($fullAlt) { 'basaras' }    else { $null } }
        default { if ($rarity -ge 5 -and $rarity -le 7) { 'heroes' } else { $null } }
    }
    if (-not $kind) { continue }
    if ($byKind[$kind].ContainsKey($index)) { continue }   # first row wins, as upstream

    $learn = @()
    foreach ($col in $learnColumns) {
        if ($r[$col] -eq '0') { continue }
        $learn += , @([int]$r[$col + 1], [int]$r[$col])
    }
    $alt = @()
    foreach ($col in $altColumns) {
        if ($r[$col] -eq '0') { continue }
        $alt += , @([int]$r[$col + 1], [int]$r[$col])
    }

    $entry = @{ learn = $learn }
    if ($alt.Count -gt 0) { $entry.alt = $alt }
    $byKind[$kind][$index] = $entry
}

foreach ($kind in @('characters', 'heroes', 'basaras')) {
    Write-Output ("{0,-11} {1} lignes param retenues" -f $kind, $byKind[$kind].Count)
}

foreach ($lang in @('en', 'fr', 'ja')) {
    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    foreach ($kind in @('characters', 'heroes', 'basaras')) {
        $missing = 0
        foreach ($entity in $bundle.$kind) {
            $entry = $byKind[$kind][[int]$entity.id]
            if (-not $entry) { $missing++; continue }
            $entity | Add-Member -NotePropertyName skills -NotePropertyValue $entry.learn -Force
            if ($entry.alt) { $entity | Add-Member -NotePropertyName skills_alt -NotePropertyValue $entry.alt -Force }
        }
        Write-Output ("{0} / {1,-11} {2} entrees, {3} sans skills" -f $lang, $kind, $bundle.$kind.Count, $missing)
    }

    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
}

