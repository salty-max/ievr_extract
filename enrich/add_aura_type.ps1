$ErrorActionPreference = "Stop"

$showTable = "$env:IEVR_BIN\show_table.exe"
$auraConfig = "$env:IEVR_EXTRACT\data\common\gamedata\skill\aura_skill_config_1.04.09.00.cfg.bin"
$jsonDir = "$env:IEVR_OUTPUT\json"

# Column 10 of AURA_CMD_INFO. Names come from the string id prefixes, which are
# unambiguous, and are corroborated by the game's own telop banners.
$typeNames = [ordered]@{
    '0' = 'keshin'            # wkd / wkk / wko / wks
    '1' = 'armed'             # wad / wak / wao / was â€” "Armourfy!" in English
    '2' = 'mixi_max'          # wmm
    '3' = 'totem'             # wsd / wsk / wso / wss â€” Wolf Totem, Falcon Totem
    '4' = 'bond_transform'    # wkt, kizuna_trans â€” ã‚­ã‚ºãƒŠãƒˆãƒ©ãƒ³ã‚¹
    '5' = 'awakening_power'   # wap â€” è¦šé†’ãƒ‘ãƒ¯ãƒ¼
    '6' = 'mode_change'       # mode_change_*
    '7' = 'awakening_change'  # awakening_change
}

$typeOf = @{}
foreach ($line in (& $showTable $auraConfig AURA_CMD_INFO_LIST 3000 2>&1)) {
    if ($line -notmatch '^AURA_CMD_INFO\s') { continue }
    $c = [regex]::Matches($line, 'i:(-?\d+)|"([^"]*)"') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
    $typeOf[$c[0]] = @{ type = $typeNames[$c[10]]; string_id = $c[1] }
}
Write-Output "auras typees : $($typeOf.Count)"

foreach ($lang in @('en', 'fr', 'ja')) {
    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    $missing = 0
    foreach ($aura in $bundle.auras) {
        $entry = $typeOf[[string]$aura.id]
        if (-not $entry) { $missing++; continue }
        $aura | Add-Member -NotePropertyName type -NotePropertyValue $entry.type -Force
        $aura | Add-Member -NotePropertyName string_id -NotePropertyValue $entry.string_id -Force
    }

    $legend = [ordered]@{}
    foreach ($k in $typeNames.Keys) { $legend[$k] = $typeNames[$k] }
    $bundle.legend | Add-Member -NotePropertyName aura_type -NotePropertyValue ([pscustomobject]$legend) -Force

    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
    Write-Output ("{0} : {1} auras, {2} sans type" -f $lang, $bundle.auras.Count, $missing)
}

