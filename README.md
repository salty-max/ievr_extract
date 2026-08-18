# ievr-extract

Turns an installed copy of *Inazuma Eleven: Victory Road* into three JSON bundles — `en`, `fr`,
`ja` — covering characters, hissatsu, passives, tactics, synergies, equipment and auras, plus the
sprite atlases cut into individual icons.

Built for [kizuna](https://github.com/salty-max/kizuna), but the output is game data with no app
in it.

```powershell
.\run.ps1              # unpack, mine, enrich, verify
.\run.ps1 -Stage clean # give the disk back
```

Bundles land in `out/`. Everything else lives under `work/` and is regenerable.

## What this is, and what it needs

The heavy lifting is done by [Telmo26/ievr_dataminer](https://github.com/Telmo26/ievr_dataminer),
a Rust program that reads Level-5's `.cfg.bin` config files into SQLite. This repo is what stands
around it: the patch that makes it work against the current game build, the steps that extract
what it does not, and a driver that runs the whole thing in the right order.

Prerequisites, none of which are vendored here:

| | |
| --- | --- |
| The game | Steam build **6.00.23.00**. Column indices are pinned to it — see [After a game patch](#after-a-game-patch). |
| `ievr_toolbox-cli-win64.exe` | From [ievr_toolbox](https://github.com/Telmo26/ievr_toolbox) releases. Unpacks CPK archives. |
| Rust | Stable, MSVC or MinGW. A msvcrt MinGW-w64 works; the mingw tree is ~918 MB and is only needed at build time. |
| A clone of ievr_dataminer | At `37f224b`, with `dataminer.patch` applied. |

Setting up the dataminer:

```bash
git clone https://github.com/Telmo26/ievr_dataminer && cd ievr_dataminer
git checkout 37f224b && git am < ../ievr-extract/dataminer.patch
cargo build --profile dist
```

The `dist` profile exists because Smart App Control blocks freshly built unsigned binaries — a
step dies with *"An Application Control policy has blocked this file"*. If it still bites, point
`run.ps1 -Dataminer` at a build Windows has already accepted.

## Stages

`run.ps1` takes `-Stage unpack | mine | enrich | verify | clean`, default `all`. They are
independent, so you can re-run one after changing it.

**unpack** — hard-links the two archives that matter into a staging tree and dumps them. The game
ships 5863 `.cpk` files totalling 56.7 GB; the data is in two of them, about 200 MB unpacked.
Hard links rather than copies, since these are multi-GB files on the same volume.

**mine** — `ievr_dataminer`, then `merge_db` (one SQLite with all nine languages), then
`export_json`. The dataminer wipes its output directory on every run, which is why enrichment has
to come after and cannot be cached.

**enrich** — twelve PowerShell steps for things the Rust does not emit: learned techniques,
synergy members, aura types, passive icons and builds, gender, name parts, nicknames, spirit
drops and where to find them, position and style legends. Order matters — `spirit_pool` writes the list `add_drop_flag` reads,
and `add_legend_tail` builds furigana-free variants of fields earlier steps create. It ends by
counting unresolved `<...>` placeholders and refuses to finish if it finds any.

**verify** — copies the bundles to `out/` and checks each section is non-empty.

**clean** — deletes the unpacked game files, the intermediate databases and the Rust `target/`,
which is where the gigabyte actually goes. `-Keep` spares the unpacked files, worth it while
chasing a column shift since unpacking is the slow part.

Disk during a full run: ~200 MB unpacked + ~60 MB databases + ~830 MB `target/`.

## Assets

`assets/` holds the sprite tooling, driven by hand rather than by `run.ps1` — atlases change
rarely and cutting them is a judgement call.

- **`find-texture.ps1`** — which archive holds a given texture, and optionally unpacks just that
  one. Each `.cpk` starts with its own table of contents, XOR-encrypted with a key that is the
  CRC32 of the archive's own file name; decrypt the first few MB of each and the names fall out
  as plain text. This is the trick behind unpacking 200 MB instead of 56.7 GB.
- **`cut-rects.ps1`** — cuts an atlas using the sprite table inside its own header. Use this one.
- **`slice-grid.ps1`** — the older fallback: cuts by detecting transparent gutters, for an atlas
  whose header table does not parse.
- **`contact-sheet.ps1`** — renders an atlas with numbered cells, for reading it.
- **`cri_lib.ps1`** — the CRI block cipher and CRC32, shared by the above.

Three things worth not rediscovering:

**A `.g4tx` carries its own sprite table.** No `.g4tp` descriptor ships, which made the atlases
look like undocumented grids for a long time — but the header does the job. It is a list of
sub-rectangles, `x y w h` as `u16`, 24 bytes per record, from `0x94` up to the `DDS ` magic.
That is authoritative, and it catches what a grid pass cannot: `icon_teambuff` packs eight 48×32
position badges (`MF` `DF` `GK` … `FW`) into what looks like a single 128×128 cell, and a grid
slicer silently merges them into three garbled cells.

**Sprite order is the packer's insertion order, not row-major.** The rects come out in expanding
L-shells — (0,0), (1,0), (0,1), (1,1), (2,0), (2,1), (0,2)… — because the sheet grew as sprites
were added. So neither the grid index nor the sprite index is anything you can guess from the
picture.

**Neither index is the id the data uses.** Verified on tactics, where the mapping is known for all
71 icons: the sprite order tracks ascending `wht*` id for the original set but appends
later-patched tactics at the end, so it is *correlated* with the data and equal to it nowhere.
All 17 columns of `SPECIAL_TACTICS_INFO` were tested against the cells, best 3/81. The
data→sprite step lives in the menu code, which ships as compiled Lua. Labelling an atlas still
means matching it against names obtained elsewhere — an in-game screenshot, or, as for the
passives below, the text of the entries that use each icon.

## After a game patch

**Column indices are build-specific and a patch will shift them.** The failure mode is nasty:
`main.rs` joins its threads with `let _ = handle.join()`, so a panic in `parse_*_value` is
swallowed and the symptom is a *silently empty table*. `run.ps1 -Stage verify` exists to catch
exactly that, but it only checks the sections it knows about.

The invariant that finds a shifted column fastest: **every game id is the CRC32 of its string
id** (`ps10001` → 975948532, verified on 1716/1716 passives). Dump the table, hash the string ids,
and the column that matches is the one you want. `dump_schema`, `show_table`, `find_ids` and
`dbstat` are in the patch for this, and each module in the patch notes which column it reads and
what pins it down.

The name placeholder resolver is the one part that fails loudly on purpose: an unknown key stops
the process with the key and the offending line, rather than writing partial text. The enrichment
check exists for the same reason — a step reading a raw `.cfg.bin` instead of the resolved
database is exactly what let `<FUL:KOMEI2>` reach the app once.

Archive names are hashes and may change. `assets\find-texture.ps1` rediscovers them; update
`$WANTED_ARCHIVES` at the top of `run.ps1`.

The upstream release cannot produce any of this, for the record: release 1.1 predates skill
parsing so it writes an empty `skills.sqlite`, its extractor download URL 404s with an unchecked
status so it prints "download complete" then panics, it calls the toolbox with the pre-1.2 flat
CLI, and `data\cpk_list.cfg.bin` no longer decrypts on this build so the rules filter is dead.

## What the patch changes

| Where | Why |
| --- | --- |
| `skills/hissatsu.rs` | `recastTime` moved to column 18 in this build; 19 is now a Byte, which panicked |
| `skills/passive.rs` (new) | passives moved out of `m_skillInfoList` into `passive_skill_config` |
| `text/text_database.rs` | `write_skill` never wrote `description`; channel widened to carry `(name_id, desc_id)`. Also resolves name placeholders and emits `character_name_parts`, `place_names`, `location_names` |
| `text/name_tags.rs` (new) | fills the `<FUL:ENDO>` placeholders fr/en carry; aborts on any key it cannot resolve |
| `common.rs` | `parse_number_value` — T2B stores round numbers as `Integer`, so a numeric column mixes Float and Int |
| `bin/` | `export_json`, `merge_db`, plus `dump_schema` / `show_table` / `find_ids` / `dbstat` for analysis |

Add a language by editing the `LANGUAGES` const in `src/bin/export_json.rs`. `de`, `es`, `it`,
`pt`, `zh_hans` and `zh_hant` all exist upstream and cost nothing but bundle size.

### Name placeholders

Shipped fr/en text carries `<FUL:ENDO>`-style placeholders the game substitutes at runtime —
about 3900 of them, mostly in character descriptions. `chara_name_tag` maps each key to a target
id; the prefix selects which part of the name to use, resolved through `chara_text` sub-indexes
(0 = full, 11 = family, 12 = given). Japanese is the oracle: the same line in `ja` has the name
written out, so a candidate reading can be checked rather than guessed.

Ten prefixes appear. `FUL`/`FFC`/`LFC` take the full name, `LST`/`FLC`/`FLA` the family name,
`FST`/`FFS`/`LAF` the given name; the intra-group distinction only matters for Japanese ruby.
Three symbols have no usable target — `TANAKA` points at an id present in no text file,
`SHIROYAMA` and `YAMADA` carry target 0 — and are hardcoded to their romaji, which is a
derivation rather than a guess since every symbol key *is* the uppercase romaji of the name it
stands for. Six more zero-target symbols are locale grammar, not names: `DE1` `DE2` `QUE1` `QUE2`
in French, `ad_a` and `il_l'` in Italian.

`DE1`/`DE2` track the *Japanese* name rather than the localised one, so shipped French reads
"de Arion". That is the game's bug and it is reproduced, not fixed.

Roma names resolve against roma parts, not localised ones — `<FUL:UMIBOZU>` in `name_original` is
Umibozu, not Kraken.

### Which icon a passive gets

A passive row carries no icon column, and `PASSIVE_SKILL_INFO_REF_BUFF_ICON` — the one that looks
like the answer — is used by 108 of 1716 and does not track the stat. The icon the ability list
shows comes from the passive's **effect**: in `soccer/passive_skill_effect_config`, every effect
carries `GRAND_TOTAL_INFO_BUFF_ICON_DATA`, an icon id, and 28 of them also carry
`GRAND_TOTAL_INFO_BUILD_TYPE_ICON_DATA`, which of the six team builds it belongs to. Joining
passive → effect → icon covers **1630 of 1716**; the rest are 70 passives whose effect has no
icon and 16 with no effect at all.

The ids are self-labelling, which is what makes this checkable rather than plausible: every
passive sharing an id names the same stat. All 144 under id 11 say "Castle Wall DF", all 190
under id 2 say "Shot AT", and so on across the 25 ids in use — so `legend.passive_icon` is read
off the game's own text, not guessed. The build ids come out in exactly the order `legend.style`
already uses, confirmed by the passives that name their own build ("For each Charge Rank up with
Bond Team Build…" → 2).

What is still missing is only the last hop, id → sprite. The atlas is
`menu/200_icon/08_icon_teambuff/<LG>/icon_teambuff.g4tx` (localised, 45 pictograms plus the 8
position badges), and the ids are not its sprite indices. Eight are certain anyway because the
pictogram is unambiguous or is literally the text — `AT`, `DF`, `T`, the intact and the breached
castle wall, the two money bags, the shooting comet. The rest are graded in
`_passive_icons.csv` next to the cut sprites.

## Known limits

- **Character → passive does not exist as a table.** `ability_learning_config` rolls passives from
  a nested lottery (`INFO(6) → MAIN(24) → SUB(72) → GROWTH(144) → STYLE(432) → SKILL`) keyed on
  attributes, not identity: 161 distinct passives out of 1716 across every pool. Each player ships
  five that scale with rarity plus a custom slot at level 50. The most a tool can offer is the
  candidate pool for a style and growth pattern.
- **Synergy icons are unlabelled** — 41 icons, 37 synergies, no link in any data file.
- **Passive icon ids do not resolve to sprites** — see above. Seventeen of the 25 are still
  graded guesses.
- **The enrichment is still PowerShell shelling out to `show_table` and parsing its output.** It
  works and it is checked, but it belongs in Rust. Mechanical to move: every config those steps
  read is one the dataminer already opens.
- 410 rarity-table passive ids resolve to nothing. Checked against all 60 247 `cfg.bin` files in
  the extraction — cut or unreleased content, not a missing file.

## Licence

Scripts here: MIT. The extracted data and art are Level-5's and are not redistributed by this
repo.
