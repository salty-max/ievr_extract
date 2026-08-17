$ErrorActionPreference = "Stop"

$showTable = "$env:IEVR_BIN\show_table.exe"
$gamedata  = "$env:IEVR_EXTRACT\data\common\gamedata"
$scratch   = $PSScriptRoot

function ToSigned($u) {
    $v = [uint64]$u
    if ($v -gt 2147483647) { return [int]($v - 4294967296) } else { return [int]$v }
}

# Every table that hands the player a character spirit. The first column of each
# row is a chara_base row id.
$sources = @(
    @{ file = 'soccer\soccer_drop_config_5.01.11.00.cfg.bin'; table = 'm_spiritTableDataList';            label = 'drop en match' },
    @{ file = 'soccer\soccer_fixed_reward_spirit_config_1.02.11.00.cfg.bin'; table = 'm_soccerFixedRewardSpiritDataList'; label = 'recompense fixe' },
    @{ file = 'soccer\soccer_fixed_reward_spirit_config_1.02.11.00.cfg.bin'; table = 'm_victoryBoxEmmitSpiritDataList';   label = 'victory box' }
)

$spiritRows = @{}
foreach ($src in $sources) {
    $path = Join-Path $gamedata $src.file
    $seen = @{}
    foreach ($line in (& $showTable $path $src.table 2000 2>&1)) {
        if ($line -match '^\s+u:(\d+)') { $seen[(ToSigned $Matches[1])] = 1 }
    }
    foreach ($k in $seen.Keys) { $spiritRows[$k] = 1 }
    Write-Output ("{0,-18} {1,4} ids" -f $src.label, $seen.Count)
}
Write-Output "union des lignes chara_base : $($spiritRows.Count)"

# chara_base row id -> the id the bundles expose
$charaBase = (Get-ChildItem "$gamedata\character" -Filter "chara_base_*.cfg.bin" | Select-Object -First 1).FullName
$indexOfRow = @{}
foreach ($line in (& $showTable $charaBase CHARA_BASE_INFO_LIST 20000 2>&1)) {
    if ($line -notmatch '^CHARA_BASE_INFO\s') { continue }
    $c = [regex]::Matches($line, 'i:(-?\d+)|"([^"]*)"') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
    $indexOfRow[[int]$c[0]] = [int]$c[2]
}

$droppable = @{}
$unresolved = 0
foreach ($k in $spiritRows.Keys) {
    if ($indexOfRow.ContainsKey($k)) { $droppable[$indexOfRow[$k]] = 1 } else { $unresolved++ }
}
Write-Output "ids de personnage droppables : $($droppable.Count) (non resolus : $unresolved)"

$droppable.Keys | Sort-Object | Set-Content "$scratch\droppable_ids.txt"

$bundle = Get-Content "$env:IEVR_OUTPUT\json\ievr.en.json" -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($kind in @('characters', 'heroes', 'basaras')) {
    $kept = @($bundle.$kind | Where-Object { $droppable.ContainsKey([int]$_.id) })
    Write-Output ("{0,-11} {1,5} -> {2,4} gardes" -f $kind, $bundle.$kind.Count, $kept.Count)
}


