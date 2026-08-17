$ErrorActionPreference = "Stop"

# Two finishing touches that never made it into a file of their own.
#
# hissatsu_category is a legend rather than a resolved field because the codes are what the
# bundles carry; it was checked against moves whose type is not in doubt - Fire Tornado is a
# shoot, Killer Slide and The Tower are blocks, Mugen The Hand is a catch.
#
# The _plain variants follow the convention already used for name and description: they exist
# only where furigana markup is present, so a consumer needs a `plain ?? raw` fallback.
$jsonDir = "$env:IEVR_OUTPUT\json"

foreach ($lang in @('en', 'fr', 'ja')) {
    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    $bundle.legend | Add-Member -NotePropertyName hissatsu_category -NotePropertyValue ([pscustomobject]@{
        '1' = 'shoot'; '2' = 'dribble'; '3' = 'block'; '4' = 'catch'
    }) -Force

    $plain = 0
    foreach ($kind in @('characters', 'heroes', 'basaras')) {
        foreach ($entity in $bundle.$kind) {
            foreach ($field in @('surname', 'given_name', 'nickname')) {
                $value = $entity.$field
                if ($value -and $value -match '\[') {
                    $entity | Add-Member -NotePropertyName ($field + '_plain') `
                        -NotePropertyValue ([regex]::Replace($value, '\[([^/\]]+)/[^\]]+\]', '$1')) -Force
                    $plain++
                }
            }
        }
    }
    Write-Output ("{0} : {1} variantes sans furigana" -f $lang, $plain)

    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
}
