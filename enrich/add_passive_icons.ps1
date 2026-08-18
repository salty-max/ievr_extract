$ErrorActionPreference = "Stop"

# Which icon the game shows for a passive, and which team build it belongs to.
#
# The passive itself carries no icon column. PASSIVE_SKILL_INFO_REF_BUFF_ICON exists but only
# 108 of 1716 passives use it, and what it points at does not track the stat. The icon the
# ability list actually shows comes from the passive's *effect*: in soccer/passive_skill_effect_
# config, every effect carries GRAND_TOTAL_INFO_BUFF_ICON_DATA (an icon id) and, for 28 of them,
# GRAND_TOTAL_INFO_BUILD_TYPE_ICON_DATA (which of the six team builds it belongs to).
#
# Confidence: the grouping is exact. Every passive sharing an icon id names the same stat -
# every name under 11 says "Castle Wall DF", every name under 2 says "Shot AT", and so on across
# all 25 ids in use. The build ids are confirmed the same way, by passives that name their own
# build ("For each Charge Rank up with Bond Team Build..." -> 2), and they come out in exactly
# the order legend.style already uses.

$dumpSchema = "$env:IEVR_BIN\dump_schema.exe"
$dbstat     = "$env:IEVR_BIN\dbstat.exe"
$jsonDir    = "$env:IEVR_OUTPUT\json"
$skillsDb   = "$env:IEVR_OUTPUT\skills.sqlite"

$effectConfig = Get-ChildItem "$env:IEVR_EXTRACT\data\common\gamedata\soccer" -Filter 'passive_skill_effect_config*.cfg.bin' |
    Select-Object -First 1
if (-not $effectConfig) { throw "passive_skill_effect_config introuvable" }

# What each icon id means, read off the passive names that share it rather than guessed.
$iconLabels = [ordered]@{
    '0'  = 'at'
    '1'  = 'df'
    '2'  = 'shot_at'
    '3'  = 'direct_shot_at'
    '4'  = 'breach_rate'
    '8'  = 'tension_breach_cost'
    '9'  = 'castle_wall_pierce_rate'
    '10' = 'kp'
    '11' = 'castle_wall_df'
    '12' = 'save_rate'
    '16' = 'focus_at_df'
    '17' = 'rough_attack_at_df'
    '18' = 'scramble_at_df'
    '19' = 'tension'
    '21' = 'tension_drain'
    '22' = 'bond_power'
    '23' = 'bond_power_loss'
    '24' = 'special_tactics_cooldown'
    '27' = 'foul_rate'
    '28' = 'dash_foul_rate'
    '29' = 'drop_rate_common'
    '30' = 'drop_rate_rare'
    '31' = 'special_move_cooldown'
    '32' = 'at_df'
    '37' = 'at_df_justice'
}

# Same order as legend.style, and proven by the passives that name their build.
$buildNames = @('breach', 'counter', 'bond', 'tension', 'rough_play', 'justice')

# --- effect id -> icon id / build id -------------------------------------------------------
# The config nests each effect's sub lists as separate tables, so the rows have to be walked in
# file order: a BUFF_ICON_DATA row belongs to the last PASSIVE_SKILL_EFFECT_INFO row seen.
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'ievr_passive_effects.json'
$null = & $dumpSchema $effectConfig.FullName $tmp 2>&1   # it lists every nested table on the way
$doc = Get-Content $tmp -Raw | ConvertFrom-Json
Remove-Item $tmp -Force

$iconOf = @{}
$buildOf = @{}
$current = $null
foreach ($table in $doc.tables) {
    foreach ($row in $table.rows) {
        $first = if ($row.values.Count) { $row.values[0][0].PSObject.Properties.Value } else { $null }
        switch ($row.name) {
            'PASSIVE_SKILL_EFFECT_INFO' { $current = [string]$first }
            'PASSIVE_SKILL_EFFECT_INFO_GRAND_TOTAL_INFO_BUFF_ICON_DATA'       { if ($current) { $iconOf[$current]  = [int]$first } }
            'PASSIVE_SKILL_EFFECT_INFO_GRAND_TOTAL_INFO_BUILD_TYPE_ICON_DATA' { if ($current) { $buildOf[$current] = [int]$first } }
        }
    }
}
Write-Output ("effets : {0} avec une icone, {1} avec un build" -f $iconOf.Count, $buildOf.Count)

$unknown = $iconOf.Values | Sort-Object -Unique | Where-Object { -not $iconLabels.Contains([string]$_) }
if ($unknown) { Write-Output ("  ids d'icone sans libelle : {0}" -f ($unknown -join ' ')) }

# --- passive -> effect ----------------------------------------------------------------------
$iconOfPassive = @{}
$buildOfPassive = @{}
$query = "select p.passive_id, e.effect_id from passive_skills p " +
         "join passive_skill_effects e on e.rowid = p.effect_index + 1 where p.effect_count > 0"
foreach ($line in (& $dbstat $skillsDb $query)) {
    $parts = $line -split '\|' | ForEach-Object { $_.Trim() }
    if ($parts.Count -ne 2 -or $parts[0] -eq 'passive_id') { continue }
    if ($iconOf.ContainsKey($parts[1]))  { $iconOfPassive[$parts[0]]  = $iconOf[$parts[1]] }
    if ($buildOf.ContainsKey($parts[1])) { $buildOfPassive[$parts[0]] = $buildOf[$parts[1]] }
}
Write-Output ("passifs : {0} avec une icone, {1} avec un build" -f $iconOfPassive.Count, $buildOfPassive.Count)

# --- into the bundles -----------------------------------------------------------------------
foreach ($lang in @('en', 'fr', 'ja')) {
    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    $missing = 0
    foreach ($passive in $bundle.passives) {
        $key = [string]$passive.id
        $icon = if ($iconOfPassive.ContainsKey($key)) { $iconOfPassive[$key] } else { $null }
        if ($null -eq $icon) { $missing++ }
        $label = if ($null -ne $icon -and $iconLabels.Contains([string]$icon)) { $iconLabels[[string]$icon] } else { $null }
        $build = if ($buildOfPassive.ContainsKey($key)) { $buildNames[$buildOfPassive[$key]] } else { $null }

        $passive | Add-Member -NotePropertyName icon       -NotePropertyValue $icon  -Force
        $passive | Add-Member -NotePropertyName icon_label -NotePropertyValue $label -Force
        $passive | Add-Member -NotePropertyName build      -NotePropertyValue $build -Force
    }

    $legend = [ordered]@{}
    foreach ($k in $iconLabels.Keys) { $legend[$k] = $iconLabels[$k] }
    $bundle.legend | Add-Member -NotePropertyName passive_icon -NotePropertyValue ([pscustomobject]$legend) -Force

    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
    Write-Output ("{0} : {1} passifs, {2} sans icone" -f $lang, $bundle.passives.Count, $missing)
}
