$ErrorActionPreference = "Stop"

# Where a spirit can be had, from both routes the game offers:
#   match     SOCCER_GAME_INFO -> REF_DIFFICULTY -> DIFFICULTY col 29/44
#             -> m_spiritCharaTableList -> m_spiritTableDataList
#   universe  m_starSignInfoList -> m_starSignCharaSetDataList
#             -> m_starSignRarityRateInfoList -> m_starSignCharaInfoList
$showTable = "$env:IEVR_BIN\show_table.exe"
$gamedata  = "$env:IEVR_EXTRACT\data\common\gamedata"
$textDir   = "$env:IEVR_EXTRACT\data\common\text"
$jsonDir   = "$env:IEVR_OUTPUT\json"
$db        = "$env:IEVR_OUTPUT\ievr.sqlite"
$dbstat    = "$env:IEVR_BIN\dbstat.exe"


$gameConfig = (Get-ChildItem "$gamedata\soccer" -Filter "soccer_game_config_*.cfg.bin" | Select-Object -First 1).FullName
$dropConfig = (Get-ChildItem "$gamedata\soccer" -Filter "soccer_drop_config_*.cfg.bin" | Select-Object -First 1).FullName
$universe   = (Get-ChildItem $gamedata -Recurse -Filter "players_universe_config_*.cfg.bin" | Select-Object -First 1).FullName
$charaBase  = (Get-ChildItem "$gamedata\character" -Filter "chara_base_*.cfg.bin" | Select-Object -First 1).FullName

function Ints([string]$line) { [regex]::Matches($line, 'i:(-?\d+)') | ForEach-Object { $_.Groups[1].Value } }
function ToSigned($u) { $v = [uint64]$u; if ($v -gt 2147483647) { [int]($v - 4294967296) } else { [int]$v } }

$indexOfRow = @{}
foreach ($line in (& $showTable $charaBase CHARA_BASE_INFO_LIST 20000 2>&1)) {
    if ($line -notmatch '^CHARA_BASE_INFO\s') { continue }
    $c = [regex]::Matches($line, 'i:(-?\d+)|"([^"]*)"') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
    $indexOfRow[[int]$c[0]] = [int]$c[2]
}

# The universe tables key on chara_param row ids, not chara_base ones.
$charaParam = (Get-ChildItem "$gamedata\character" -Filter "chara_param_*.cfg.bin" | Select-Object -First 1).FullName
$indexOfParam = @{}
foreach ($line in (& $showTable $charaParam CHARA_PARAM_INFO_LIST 40000 2>&1)) {
    if ($line -notmatch '^CHARA_PARAM_INFO\s') { continue }
    $c = [regex]::Matches($line, 'i:(-?\d+)') | ForEach-Object { $_.Groups[1].Value }
    $base = [int]$c[1]
    if (-not $indexOfRow.ContainsKey($base)) { continue }
    $indexOfParam[[int]$c[0]] = $indexOfRow[$base]
}

$foundIn = @{}                 # bundle id -> set of location keys
$locations = [ordered]@{}      # location key -> @{ kind; titleId }
function Note($id, $key, $kind, $titleId) {
    if (-not $foundIn.ContainsKey($id)) { $foundIn[$id] = @{} }
    $foundIn[$id][$key] = 1
    if (-not $locations.Contains($key)) { $locations[$key] = @{ kind = $kind; titleId = $titleId } }
}

# --- matches -------------------------------------------------------------
$games = @(); $current = $null
foreach ($line in (& $showTable $gameConfig SOCCER_GAME_INFO_LIST 3000 2>&1)) {
    if ($line -match '^SOCCER_GAME_INFO\s') {
        $c = [regex]::Matches($line, 'i:(-?\d+)|"([^"]*)"') | ForEach-Object {
            if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
        }
        $current = [pscustomobject]@{ StringId = $c[1]; TitleId = $c[4]; Start = 0; Count = 0 }
        $games += $current
    }
    elseif ($line -match '^SOCCER_GAME_INFO_REF_DIFFICULTY\s+i:(-?\d+)\s+i:(-?\d+)') {
        $current.Start = [int]$Matches[1]; $current.Count = [int]$Matches[2]
    }
}
$difficulty = @()
foreach ($line in (& $showTable $gameConfig SOCCER_GAME_DIFFICULTY_LIST 4000 2>&1)) {
    if ($line -match '^SOCCER_GAME_DIFFICULTY\s') { $difficulty += , (Ints $line) }
}
$charaTable = @{}
foreach ($line in (& $showTable $dropConfig m_spiritCharaTableList 200 2>&1)) {
    if ($line -match '^\s+u:(\d+)\s+\((\d+),(\d+)\)') { $charaTable[(ToSigned $Matches[1])] = @([int]$Matches[2], [int]$Matches[3]) }
}
$tableData = @()
foreach ($line in (& $showTable $dropConfig m_spiritTableDataList 2000 2>&1)) {
    if ($line -match '^\s+u:(\d+)\s') { $tableData += (ToSigned $Matches[1]) }
}
foreach ($m in $games) {
    for ($i = $m.Start; $i -lt ($m.Start + $m.Count); $i++) {
        if ($i -ge $difficulty.Count) { continue }
        foreach ($col in 29, 44) {
            $tid = [int]$difficulty[$i][$col]
            if (-not $charaTable.ContainsKey($tid)) { continue }
            $r = $charaTable[$tid]
            for ($k = $r[0]; $k -lt ($r[0] + $r[1]); $k++) {
                if ($k -ge $tableData.Count) { continue }
                if (-not $indexOfRow.ContainsKey($tableData[$k])) { continue }
                Note $indexOfRow[$tableData[$k]] $m.StringId 'match' $m.TitleId
            }
        }
    }
}

# --- player universe -----------------------------------------------------
$signName = @{}
foreach ($line in (& $showTable $universe m_starSignInfoList 60 2>&1)) {
    if ($line -match '^\s+u:(\d+)\s+u:(\d+)\s+u:(\d+)') { $signName[(ToSigned $Matches[1])] = (ToSigned $Matches[2]) }
}
$rarityRate = @()
foreach ($line in (& $showTable $universe m_starSignRarityRateInfoList 200 2>&1)) {
    if ($line -match '\((\d+),(\d+)\)\s*$') { $rarityRate += , @([int]$Matches[1], [int]$Matches[2]) }
}
$signSet = @()
foreach ($line in (& $showTable $universe m_starSignCharaSetDataList 60 2>&1)) {
    if ($line -match '^\s+u:(\d+)\s+\((\d+),(\d+)\)') { $signSet += , @((ToSigned $Matches[1]), [int]$Matches[2], [int]$Matches[3]) }
}
$signChara = @()
foreach ($line in (& $showTable $universe m_starSignCharaInfoList 6000 2>&1)) {
    if ($line -match '^\s+u:(\d+)\s') { $signChara += (ToSigned $Matches[1]) }
}
Write-Output "univers : $($signSet.Count) signes, $($rarityRate.Count) paliers, $($signChara.Count) entrees"

foreach ($set in $signSet) {
    $key = "star_$($set[0])"
    for ($r = $set[1]; $r -lt ($set[1] + $set[2]); $r++) {
        if ($r -ge $rarityRate.Count) { continue }
        $slice = $rarityRate[$r]
        for ($k = $slice[0]; $k -lt ($slice[0] + $slice[1]); $k++) {
            if ($k -ge $signChara.Count) { continue }
            if (-not $indexOfParam.ContainsKey($signChara[$k])) { continue }
            Note $indexOfParam[$signChara[$k]] $key 'universe' $signName[$set[0]]
        }
    }
}
Write-Output "personnages localises : $($foundIn.Count) ; lieux : $($locations.Count)"

foreach ($lang in @('en', 'fr', 'ja')) {
    # Match titles and star sign names, taken from the merged database so that any name
    # placeholder is already filled — soccer_game_title carries <FUL:KOMEI2>.
    $titles = @{}
    foreach ($line in (& $dbstat $db "SELECT id, name FROM location_names WHERE lang='$lang'" | Select-Object -Skip 1)) {
        $p = $line -split ' \| ', 2
        if ($p.Count -eq 2) { $titles[$p[0]] = $p[1] }
    }

    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    $n = 0
    foreach ($kind in @('characters', 'heroes', 'basaras')) {
        foreach ($entity in $bundle.$kind) {
            $hits = $foundIn[[int]$entity.id]
            if (-not $hits) { continue }
            $entity | Add-Member -NotePropertyName found_in -NotePropertyValue @($hits.Keys | Sort-Object) -Force
            $n++
        }
    }

    $named = 0
    $list = foreach ($key in $locations.Keys) {
        $t = $titles[[string]$locations[$key].titleId]
        if ($t) { $named++ }
        [pscustomobject]@{ string_id = $key; name = $t; kind = $locations[$key].kind }
    }
    $bundle | Add-Member -NotePropertyName locations -NotePropertyValue @($list) -Force
    if ($bundle.PSObject.Properties['matches']) { $bundle.PSObject.Properties.Remove('matches') }

    if ($lang -eq 'en') { Write-Output ("entrees enrichies : {0} ; lieux nommes : {1}/{2}" -f $n, $named, $locations.Count) }
    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
}




