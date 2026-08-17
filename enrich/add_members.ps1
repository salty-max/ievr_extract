$ErrorActionPreference = "Stop"

$scratch = $PSScriptRoot
$showTable = "$env:IEVR_BIN\show_table.exe"
$gamedata = "$env:IEVR_EXTRACT\data\common\gamedata"
$jsonDir = "$env:IEVR_OUTPUT\json"

function Split-Row([string]$line) {
    [regex]::Matches($line, 'i:(-?\d+)|"([^"]*)"') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
}

# chara_base col 0 is the id the synergy conditions use; col 2 is the id the bundles expose
$charaBase = (Get-ChildItem "$gamedata\character" -Filter "chara_base_*.cfg.bin" | Select-Object -First 1).FullName
$baseToIndex = @{}
foreach ($line in (& $showTable $charaBase CHARA_BASE_INFO_LIST 20000 2>&1)) {
    if ($line -notmatch '^CHARA_BASE_INFO\s') { continue }
    $c = Split-Row $line
    if (-not $baseToIndex.ContainsKey($c[0])) { $baseToIndex[$c[0]] = [int]$c[2] }
}

# Each synergy points at a run of conditions; every condition names one character
$synergyConfig = "$gamedata\skill\synergy_flag_config_6.00.28.00.cfg.bin"
$conditions = @()
foreach ($line in (& $showTable $synergyConfig SYNERGY_FLAG_EXEC_COND_LIST 500 2>&1)) {
    if ($line -match '^SYNERGY_FLAG_EXEC_COND\s') { $conditions += , (Split-Row $line) }
}

$members = @{}
$current = $null
foreach ($line in (& $showTable $synergyConfig SYNERGY_FLAG_INFO_LIST 500 2>&1)) {
    if ($line -match '^SYNERGY_FLAG_INFO\s+i:(-?\d+)') {
        $current = $Matches[1]
    }
    elseif ($line -match '^SYNERGY_FLAG_INFO_REF_EXEC_COND\s+i:(-?\d+)\s+i:(-?\d+)') {
        $start = [int]$Matches[1]
        $count = [int]$Matches[2]
        $ids = @()
        for ($i = $start; $i -lt ($start + $count); $i++) {
            $baseId = $conditions[$i][1]
            if ($baseToIndex.ContainsKey($baseId)) { $ids += $baseToIndex[$baseId] }
        }
        $members[$current] = $ids
    }
}

Write-Output "synergies avec membres : $($members.Count)"

foreach ($lang in @('en', 'fr', 'ja')) {
    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    $nameById = @{}
    foreach ($character in $bundle.characters) { $nameById[[string]$character.id] = $character.name }

    $missing = 0
    foreach ($synergy in $bundle.synergies) {
        $ids = $members[[string]$synergy.id]
        if (-not $ids) { $missing++; $ids = @() }
        $synergy | Add-Member -NotePropertyName members -NotePropertyValue @($ids) -Force
        $synergy | Add-Member -NotePropertyName member_names -NotePropertyValue @($ids | ForEach-Object { $nameById[[string]$_] }) -Force
    }

    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
    Write-Output ("{0} : {1} synergies, {2} sans membres" -f $lang, $bundle.synergies.Count, $missing)
}


