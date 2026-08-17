$ErrorActionPreference = "Stop"

$showTable = "$env:IEVR_BIN\show_table.exe"
$gamedata  = "$env:IEVR_EXTRACT\data\common\gamedata\character"
$jsonDir   = "$env:IEVR_OUTPUT\json"

# chara_base column 11: 1 male, 2 female, 5 neither (Terracotta Warriors and the like),
# 0 left unset on mobs and creatures. Column 2 is the id the bundles expose.
$label = @{ '0' = $null; '1' = 'male'; '2' = 'female'; '4' = 'other'; '5' = 'other' }

$charaBase = (Get-ChildItem $gamedata -Filter "chara_base_*.cfg.bin" | Select-Object -First 1).FullName
$genderOf = @{}
$conflicts = 0
foreach ($line in (& $showTable $charaBase CHARA_BASE_INFO_LIST 20000 2>&1)) {
    if ($line -notmatch '^CHARA_BASE_INFO\s') { continue }
    $c = [regex]::Matches($line, 'i:(-?\d+)|"([^"]*)"') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
    $index = [int]$c[2]
    $g = $label[$c[11]]
    if ($genderOf.ContainsKey($index)) {
        if ($genderOf[$index] -ne $g) { $conflicts++ }
        continue
    }
    $genderOf[$index] = $g
}
Write-Output "ids indexes : $($genderOf.Count) ; conflits entre lignes du meme id : $conflicts"

foreach ($lang in @('en', 'fr', 'ja')) {
    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    foreach ($kind in @('characters', 'heroes', 'basaras')) {
        $counts = @{}
        foreach ($entity in $bundle.$kind) {
            $g = $null
            if ($genderOf.ContainsKey([int]$entity.id)) { $g = $genderOf[[int]$entity.id] }
            $entity | Add-Member -NotePropertyName gender -NotePropertyValue $g -Force
            $key = if ($g) { $g } else { 'null' }
            if ($counts.ContainsKey($key)) { $counts[$key]++ } else { $counts[$key] = 1 }
        }
        if ($lang -eq 'en') {
            $summary = ($counts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ', '
            Write-Output ("{0,-11} {1}" -f $kind, $summary)
        }
    }

    $bundle.legend | Add-Member -NotePropertyName gender -NotePropertyValue ([pscustomobject]@{
        '1' = 'male'; '2' = 'female'; '4' = 'other'; '5' = 'other'
    }) -Force

    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
}
Write-Output "ecrit pour en / fr / ja"

