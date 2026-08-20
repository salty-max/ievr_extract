$ErrorActionPreference = "Stop"

# Which passives drop from a match, from character/team_passive_lot_table_config.
#
# TEAM_PASSIVE_LOT_TABLE_DATA is a list of pools; each points at a run of TEAM_PASSIVE_LOT_DATA
# rows of (passive id, lotWeight, condition, rarityEnableFlag[6]). 132 pools, 653 rows, 114
# distinct passives - all of them base ids, none of the _NN rarity variants, which fits: the
# match drops the passive and its tier follows the match's rarity.
#
# Three of the pools are samples rather than content: they are the only ones carrying real
# weights and rarity flags, and they hold 8 rows between them. The 129 that remain are flat -
# five passives each, weight 1, no rarity gate - and that is what a real opponent offers.
# The rule below is that shape, not a row count, so it survives a patch adding pools.
#
# What is NOT here is which opponent uses which pool. The 132 pool ids appear in exactly one
# file in the extraction, their own - checked as raw u32 across all 5863 configs - and no string
# anywhere in gamedata hashes to any of them. That selector lives in the executable.

$showTable = "$env:IEVR_BIN\show_table.exe"
$gamedata  = "$env:IEVR_EXTRACT\data\common\gamedata"
$jsonDir   = "$env:IEVR_OUTPUT\json"

$config = (Get-ChildItem "$gamedata\character" -Filter 'team_passive_lot_table_config*.cfg.bin' |
    Select-Object -First 1).FullName
if (-not $config) { throw "team_passive_lot_table_config introuvable" }

function ToSigned($text) {
    $n = [int64]$text
    if ($n -gt 2147483647) { $n -= 4294967296 }
    return [int]$n
}

# the pool rows, in file order, so the (offset, count) ranges index straight into them
$rows = @()
foreach ($line in (& $showTable $config m_teamPassiveLotDataList 2000 2>&1)) {
    if ($line -notmatch '^\s+u:(\d+)\s+i:(-?\d+)\s+u:\d+\s+(\S+)') { continue }
    $rows += [pscustomobject]@{
        passive = ToSigned $Matches[1]
        weight  = [int]$Matches[2]
        gated   = $Matches[3] -match 'u8:1'    # a rarity flag set at all
    }
}

$pools = @()
foreach ($line in (& $showTable $config m_teamPassiveLotTableDataList 500 2>&1)) {
    if ($line -notmatch '^\s+u:(\d+)\s+\((\d+),(\d+)\)') { continue }
    $start = [int]$Matches[2]; $count = [int]$Matches[3]
    $slice = if ($count) { $rows[$start..($start + $count - 1)] } else { @() }
    $pools += [pscustomobject]@{
        id      = ToSigned $Matches[1]
        members = @($slice | ForEach-Object { $_.passive })
        sample  = [bool]@($slice | Where-Object { $_.gated -or $_.weight -ne 1 }).Count
    }
}
$real = @($pools | Where-Object { -not $_.sample })
Write-Output ("{0} tables ({1} reelles, {2} d'exemple), {3} lignes" -f $pools.Count, $real.Count, ($pools.Count - $real.Count), $rows.Count)

# how many pools a passive turns up in - the closest thing to "how easy is this to farm"
$poolCount = @{}
foreach ($p in $real) { foreach ($m in ($p.members | Sort-Object -Unique)) { $poolCount[[string]$m] = $poolCount[[string]$m] + 1 } }
Write-Output ("{0} passifs distincts dans les tables reelles" -f $poolCount.Count)

foreach ($lang in @('en', 'fr', 'ja')) {
    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    $marked = 0
    foreach ($p in $bundle.passives) {
        $n = $poolCount[[string]$p.id]
        if ($n) { $marked++ }
        $p | Add-Member -NotePropertyName droppable  -NotePropertyValue ([bool]$n) -Force
        $p | Add-Member -NotePropertyName drop_pools -NotePropertyValue $(if ($n) { $n } else { $null }) -Force
    }
    # the comma keeps each pool an array of its own; without it PowerShell flattens all 129
    $bundle | Add-Member -NotePropertyName passive_drop_pools -NotePropertyValue @($real | ForEach-Object { , @($_.members) }) -Force

    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
    Write-Output ("{0} : {1} passifs marques droppables sur {2}" -f $lang, $marked, $bundle.passives.Count)
}
