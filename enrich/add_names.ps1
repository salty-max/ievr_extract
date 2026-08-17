$ErrorActionPreference = "Stop"

# The game splits a name into family (part 11) and given (part 12) for the main cast only.
# Read them from the merged database, where the dataminer has already filled any name
# placeholder â€” reading chara_text raw is what let <FST:ALICE> leak back into the bundles.
$dbstat    = "$env:IEVR_BIN\dbstat.exe"
$showTable = "$env:IEVR_BIN\show_table.exe"
$db        = "$env:IEVR_OUTPUT\ievr.sqlite"
$gamedata  = "$env:IEVR_EXTRACT\data\common\gamedata\character"
$jsonDir   = "$env:IEVR_OUTPUT\json"



# bundle id (chara_base column 2) -> name id (column 3)
$charaBase = (Get-ChildItem $gamedata -Filter "chara_base_*.cfg.bin" | Select-Object -First 1).FullName
$nameIdOf = @{}
foreach ($line in (& $showTable $charaBase CHARA_BASE_INFO_LIST 20000 2>&1)) {
    if ($line -notmatch '^CHARA_BASE_INFO\s') { continue }
    $c = [regex]::Matches($line, 'i:(-?\d+)|"([^"]*)"') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
    $index = [int]$c[2]
    if (-not $nameIdOf.ContainsKey($index)) { $nameIdOf[$index] = $c[3] }
}

foreach ($lang in @('en', 'fr', 'ja')) {
    $surname = @{}; $given = @{}
    foreach ($line in (& $dbstat $db "SELECT id, part, text FROM character_name_parts WHERE lang='$lang'" | Select-Object -Skip 1)) {
        $p = $line -split ' \| ', 3
        if ($p.Count -lt 3) { continue }
        if ($p[1] -eq '11') { $surname[$p[0]] = $p[2] } elseif ($p[1] -eq '12') { $given[$p[0]] = $p[2] }
    }

    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    $total = 0
    foreach ($kind in @('characters', 'heroes', 'basaras')) {
        foreach ($entity in $bundle.$kind) {
            $nid = $nameIdOf[[int]$entity.id]
            if (-not $nid) { continue }
            if ($surname.ContainsKey($nid)) {
                $entity | Add-Member -NotePropertyName surname -NotePropertyValue $surname[$nid] -Force
                $total++
            }
            if ($given.ContainsKey($nid)) {
                $entity | Add-Member -NotePropertyName given_name -NotePropertyValue $given[$nid] -Force
            }
        }
    }
    Write-Output ("{0} : {1} entrees enrichies" -f $lang, $total)

    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
}


