$ErrorActionPreference = "Stop"

# position and style codes, decoded by joining the datamined roster against the
# Inazugle scrape on player name. Element is already known and comes out of the
# same join at 99.5%, which is what makes the other two believable.
$jsonDir = "$env:IEVR_OUTPUT\json"

$position = [ordered]@{ '1' = 'GK'; '2' = 'FW'; '3' = 'MF'; '4' = 'DF' }
$style    = [ordered]@{ '0' = 'breach'; '1' = 'counter'; '2' = 'bond'; '3' = 'tension'; '4' = 'rough_play'; '5' = 'justice' }

foreach ($lang in @('en', 'fr', 'ja')) {
    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    $bundle.legend | Add-Member -NotePropertyName position -NotePropertyValue ([pscustomobject]$position) -Force
    $bundle.legend | Add-Member -NotePropertyName style    -NotePropertyValue ([pscustomobject]$style)    -Force
    $bundle.legend.note = 'element, position and style decoded; hissatsu_category, aura_type and gender resolved in place'

    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
}

$check = Get-Content "$jsonDir\ievr.en.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$check.legend | ConvertTo-Json -Depth 4

