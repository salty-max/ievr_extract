$ErrorActionPreference = "Stop"

# The order the game lists synergies in, from column 15 of ITEM_SYNERGY_FLAG_INFO, and whether a
# synergy is in that list at all.
#
# Column 15 runs 1..35 over the 35 synergies the game shows - the sp* family first, then sf* -
# and is left at 1 for sf01000010 and sf01000020, colliding with sp01001, so it cannot be the
# test on its own. Column 4 can: it holds 7601..7635, one per listed synergy in exactly that
# order, and 0 for those same two.
#
# They are the two synergies with no icon, and this is why. Their ids carry the long form the
# launch characters use (c01000010), they sit outside the numbering, and no sprite answers to
# their name in any of the game's 43 icon atlases.

$showTable = "$env:IEVR_BIN\show_table.exe"
$itemConfig = Get-ChildItem "$env:IEVR_EXTRACT\data\common\gamedata\item" -Filter 'item_config*.cfg.bin' |
    Select-Object -First 1
$jsonDir = "$env:IEVR_OUTPUT\json"
if (-not $itemConfig) { throw "item_config introuvable" }

$rank = @{}
foreach ($line in (& $showTable $itemConfig.FullName ITEM_SYNERGY_FLAG_INFO_LIST 200 2>&1)) {
    if ($line -notmatch '^ITEM_SYNERGY_FLAG_INFO\s') { continue }
    $c = [regex]::Matches($line, 'i:(-?\d+)|"([^"]*)"') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
    # 16 is the id synergy_flag_config uses and the one the bundles expose
    $rank[$c[16]] = @{ order = [int]$c[15]; slot = [int]$c[4] }
}
$listed = ($rank.Values | Where-Object { $_.slot -ne 0 }).Count
Write-Output ("{0} synergies lues, {1} listees dans le jeu" -f $rank.Count, $listed)

foreach ($lang in @('en', 'fr', 'ja')) {
    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    $legacy = @()
    foreach ($s in $bundle.synergies) {
        $r = $rank[[string]$s.id]
        $shown = $r -and $r.slot -ne 0
        if (-not $shown) { $legacy += $s.string_id }
        $s | Add-Member -NotePropertyName order  -NotePropertyValue $(if ($shown) { $r.order } else { $null }) -Force
        $s | Add-Member -NotePropertyName listed -NotePropertyValue ([bool]$shown) -Force
    }
    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
    Write-Output ("{0} : {1} synergies, hors liste : {2}" -f $lang, $bundle.synergies.Count, ($legacy -join ' '))
}
