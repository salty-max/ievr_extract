$ErrorActionPreference = "Stop"

# chara_base column 4 is the short name the game prints on the pitch â€” usually the family
# name, but Byron Love is "Aphrody" there. Column 5 is the same string uppercased, skipped.
# The text comes from the merged database so that any name placeholder is already filled.
$dbstat    = "$env:IEVR_BIN\dbstat.exe"
$showTable = "$env:IEVR_BIN\show_table.exe"
$db        = "$env:IEVR_OUTPUT\ievr.sqlite"
$gamedata  = "$env:IEVR_EXTRACT\data\common\gamedata\character"
$jsonDir   = "$env:IEVR_OUTPUT\json"



$charaBase = (Get-ChildItem $gamedata -Filter "chara_base_*.cfg.bin" | Select-Object -First 1).FullName
$nicknameIdOf = @{}
foreach ($line in (& $showTable $charaBase CHARA_BASE_INFO_LIST 20000 2>&1)) {
    if ($line -notmatch '^CHARA_BASE_INFO\s') { continue }
    $c = [regex]::Matches($line, 'i:(-?\d+)|"([^"]*)"') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
    $index = [int]$c[2]
    if ($c[4] -eq '0') { continue }
    if (-not $nicknameIdOf.ContainsKey($index)) { $nicknameIdOf[$index] = $c[4] }
}

foreach ($lang in @('en', 'fr', 'ja')) {
    # part 0 is the entry as written, already resolved by the dataminer
    $text = @{}
    foreach ($line in (& $dbstat $db "SELECT id, text FROM character_name_parts WHERE lang='$lang' AND part=0" | Select-Object -Skip 1)) {
        $p = $line -split ' \| ', 2
        if ($p.Count -eq 2) { $text[$p[0]] = $p[1] }
    }

    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    $n = 0; $missing = 0
    foreach ($kind in @('characters', 'heroes', 'basaras')) {
        foreach ($entity in $bundle.$kind) {
            $nid = $nicknameIdOf[[int]$entity.id]
            if (-not $nid) { continue }
            $value = $text[$nid]
            if (-not $value) { $missing++; continue }
            $entity | Add-Member -NotePropertyName nickname -NotePropertyValue $value -Force
            $n++
        }
    }
    Write-Output ("{0} : {1} surnoms, {2} sans texte" -f $lang, $n, $missing)

    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
}


