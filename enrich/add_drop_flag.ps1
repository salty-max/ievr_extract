$ErrorActionPreference = "Stop"

# Marks who the game hands you as a spirit from its drop tables. Non-destructive:
# the builder can filter on it, the wiki keeps everyone.
$scratch = $PSScriptRoot
$jsonDir = "$env:IEVR_OUTPUT\json"

$droppable = @{}
Get-Content "$scratch\droppable_ids.txt" | ForEach-Object {
    if ($_ -match '^\d+$') { $droppable[[int]$_] = 1 }
}

foreach ($lang in @('en', 'fr', 'ja')) {
    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    foreach ($kind in @('characters', 'heroes', 'basaras')) {
        $n = 0
        foreach ($entity in $bundle.$kind) {
            $flag = $droppable.ContainsKey([int]$entity.id)
            $entity | Add-Member -NotePropertyName spirit_drop -NotePropertyValue $flag -Force
            if ($flag) { $n++ }
        }
        if ($lang -eq 'en') { Write-Output ("{0,-11} {1,5} entrees, {2} marquees" -f $kind, $bundle.$kind.Count, $n) }
    }

    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
}
Write-Output "ecrit pour en / fr / ja"


