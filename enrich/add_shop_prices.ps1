$ErrorActionPreference = "Stop"

# What each shop sells and what it charges, from gamedata/shop/shop_config.
#
# A shop points at a SHOP_TOKEN_GROUP: an ordered list of the currencies it accepts. Each
# SHOP_INFO_ITEM then carries one amount per currency, in that order, starting at column 7 -
# so a price is read by zipping the item's columns onto its shop's token list. Fourteen of the
# sixteen shops work this way.
#
# The other two, market_05 and market_06, are the trade counters: they have no token group and
# carry SHOP_INFO_ITEM_CONSUME sub rows instead, (item id, kind, quantity). Every one of those
# 433 ids is a chara_param row - you pay in spirits, not in currency - so they resolve through
# the same chara_param -> chara_base join the learned-move step uses.
#
# Nothing sells tactics or passives. That is not a gap: passives are rolled, never bought.

$showTable  = "$env:IEVR_BIN\show_table.exe"
$dumpSchema = "$env:IEVR_BIN\dump_schema.exe"
$gamedata   = "$env:IEVR_EXTRACT\data\common\gamedata"
$jsonDir    = "$env:IEVR_OUTPUT\json"

function Split-Row([string]$line) {
    [regex]::Matches($line, 'i:(-?\d+)|"([^"]*)"') | ForEach-Object {
        if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value }
    }
}

# --- currencies: the tk_* items, all of them in ITEM_CONSUME_INFO --------------------------
$itemConfig = (Get-ChildItem "$gamedata\item" -Filter 'item_config*.cfg.bin' | Select-Object -First 1).FullName
$currency = @{}
foreach ($line in (& $showTable $itemConfig ITEM_CONSUME_INFO_LIST 500 2>&1)) {
    if ($line -notmatch '^ITEM_CONSUME_INFO\s') { continue }
    $c = Split-Row $line
    $currency[$c[0]] = @{ string_id = $c[11]; name_id = [int]$c[2] }
}
Write-Output ("monnaies : {0}" -f $currency.Count)

# --- spirits: chara_param row -> the character id the bundles expose -----------------------
$charaBase = (Get-ChildItem "$gamedata\character" -Filter 'chara_base_*.cfg.bin' | Select-Object -First 1).FullName
# Column 2 is the id the bundles expose. It is 0 on the 1394 rows that are NPCs rather than
# playable characters, and a trade counter can ask for one of those - so 0 becomes null rather
# than a lookup that will fail.
$baseToId = @{}
foreach ($line in (& $showTable $charaBase CHARA_BASE_INFO_LIST 20000 2>&1)) {
    if ($line -notmatch '^CHARA_BASE_INFO\s') { continue }
    $c = Split-Row $line
    if (-not $baseToId.ContainsKey($c[0])) { $baseToId[$c[0]] = if ([int]$c[2] -gt 0) { [int]$c[2] } else { $null } }
}
$charaParam = (Get-ChildItem "$gamedata\character" -Filter 'chara_param_*.cfg.bin' | Select-Object -First 1).FullName
$paramToId = @{}
foreach ($line in (& $showTable $charaParam CHARA_PARAM_INFO_LIST 60000 2>&1)) {
    if ($line -notmatch '^CHARA_PARAM_INFO\s') { continue }
    $c = Split-Row $line
    if (-not $paramToId.ContainsKey($c[0]) -and $baseToId.ContainsKey($c[1]) -and $null -ne $baseToId[$c[1]]) {
        $paramToId[$c[0]] = $baseToId[$c[1]]
    }
}

# --- the shop config ------------------------------------------------------------------------
# Sub lists are separate tables, so the rows are walked in file order and each one belongs to
# the last parent seen.
$shopConfig = (Get-ChildItem "$gamedata\shop" -Filter 'shop_config*.cfg.bin' | Select-Object -First 1).FullName
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'ievr_shop.json'
try {
    $ErrorActionPreference = 'Continue'
    & $dumpSchema $shopConfig $tmp *> $null
} finally { $ErrorActionPreference = 'Stop' }
if (-not (Test-Path $tmp)) { throw "dump_schema n'a rien ecrit pour shop_config" }
$doc = Get-Content $tmp -Raw | ConvertFrom-Json
Remove-Item $tmp -Force

$rows = foreach ($table in $doc.tables) {
    foreach ($row in $table.rows) {
        $v = @()
        foreach ($field in $row.values) { foreach ($x in $field) { $v += ($x.PSObject.Properties | Select-Object -First 1).Value } }
        [pscustomobject]@{ name = $row.name; v = $v }
    }
}

# The token groups sit at the end of the file, after the shops that use them, so they have to
# be collected before the items are priced.
$tokenGroups = @{}
$group = $null
foreach ($row in $rows) {
    switch ($row.name) {
        'SHOP_TOKEN_GROUP'       { $group = [string]$row.v[0]; $tokenGroups[$group] = @() }
        'SHOP_TOKEN_GROUP_TOKEN' { $tokenGroups[$group] += [string]$row.v[0] }
    }
}

$shops = [ordered]@{}
$offers = @{}          # sold item id -> list of offers
$shop = $null; $item = $null; $unnamed = 0; $unknownSpirit = 0

foreach ($row in $rows) {
    $v = $row.v
    switch ($row.name) {
            'SHOP_INFO' {
            $shop = [string]$v[0]
            # column 18 is a texture path like shop_market_04.g4tx, the only readable name
            $label = if ($v.Count -gt 18 -and $v[18] -is [string]) { $v[18] -replace '^shop_|\.g4tx$', '' }
                     else { $unnamed++; "unnamed_0$unnamed" }
            $shops[$shop] = @{ label = $label; group = [string]$v[17] }
        }
        'SHOP_INFO_ITEM' {
            $item = [string]$v[2]
            $tokens = $tokenGroups[$shops[$shop].group]
            $price = @()
            if ($tokens) {
                for ($k = 0; $k -lt $tokens.Count -and 7 + $k -lt $v.Count; $k++) {
                    $amount = [int]$v[7 + $k]
                    if ($amount -le 0) { continue }
                    $sid = if ($currency.ContainsKey($tokens[$k])) { $currency[$tokens[$k]].string_id } else { $null }
                    $price += [pscustomobject]@{ currency = $sid; currency_id = [int]$tokens[$k]; amount = $amount }
                }
            }
            $offer = [pscustomobject]@{ shop = $shops[$shop].label; price = $price; spirits = @() }
            if (-not $offers.ContainsKey($item)) { $offers[$item] = @() }
            $offers[$item] += $offer
        }
        'SHOP_INFO_ITEM_CONSUME' {
            $last = @($offers[$item])[-1]
            $who = $paramToId[[string]$v[0]]
            if ($null -eq $who) { $unknownSpirit++ }
            $last.spirits += [pscustomobject]@{ character = $who; count = [int]$v[2] }
        }
    }
}
$priced = ($offers.Values | ForEach-Object { $_ } | Where-Object { $_.price.Count -or $_.spirits.Count }).Count
Write-Output ("{0} boutiques, {1} articles distincts, {2} offres chiffrees" -f $shops.Count, $offers.Count, $priced)
$noName = ($offers.Values | ForEach-Object { $_ } | ForEach-Object { $_.price } | Where-Object { $_ -and -not $_.currency }).Count
if ($noName) { Write-Output "  $noName lignes de prix dont la monnaie n'est pas dans ITEM_CONSUME_INFO" }
if ($unknownSpirit) { Write-Output "  $unknownSpirit esprits demandes qui sont des PNJ, hors catalogue (character null)" }

# --- currency names, per language, from the merged text database ---------------------------
$used = @($tokenGroups.Values | ForEach-Object { $_ } | Sort-Object -Unique)
$wanted = ($used | ForEach-Object { $currency[$_].name_id }) -join ','
$currencyName = @{}
foreach ($lang in @('en', 'fr', 'ja')) {
    $currencyName[$lang] = @{}
    $sql = "select id, replace(name,'|','/') from item_names where lang='$lang' and id in ($wanted)"
    foreach ($line in (& "$env:IEVR_BIN\dbstat.exe" "$env:IEVR_OUTPUT\ievr.sqlite" $sql)) {
        $p = $line -split '\|', 2
        if ($p.Count -eq 2 -and $p[0].Trim() -ne 'id') { $currencyName[$lang][$p[0].Trim()] = $p[1].Trim() }
    }
}

# --- into the bundles -----------------------------------------------------------------------
$sections = @('hissatsu', 'aura_hissatsu', 'auras', 'equipment', 'synergies', 'tactics', 'passives')

foreach ($lang in @('en', 'fr', 'ja')) {
    $path = "$jsonDir\ievr.$lang.json"
    $bundle = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json

    $counts = @()
    foreach ($section in $sections) {
        $sold = 0
        foreach ($entry in $bundle.$section) {
            $o = $offers[[string]$entry.id]
            if ($o) { $sold++ }
            $entry | Add-Member -NotePropertyName shops -NotePropertyValue @($o) -Force
        }
        $counts += "{0} {1}/{2}" -f $section, $sold, $bundle.$section.Count
    }

    # the currencies themselves, so a price can be shown with its icon and label
    $list = foreach ($id in $used) {
        [pscustomobject]@{
            id        = [int]$id
            string_id = $currency[$id].string_id
            name      = $currencyName[$lang][[string]$currency[$id].name_id]
        }
    }
    $bundle | Add-Member -NotePropertyName currencies -NotePropertyValue @($list) -Force

    $bundle | ConvertTo-Json -Depth 12 -Compress | Set-Content $path -Encoding UTF8 -NoNewline
    Write-Output ("{0} : {1}" -f $lang, ($counts -join ' ; '))
}
