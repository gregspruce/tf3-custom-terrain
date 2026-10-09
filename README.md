# Custom Terrain (Experimental)

A Transport Fever 3 mod by TangoEchoXray, published on mod.io (the game's Mod Hub). This repository holds its
released versions: `mod/` is the mod folder exactly as uploaded (release r1), `docs/` the
development history (CHANGELOG, RELEASE_NOTES). To play, install the mod from the Mod Hub in game.

---

**Last Updated:** 2026-10-03 · modId `custom_terrain_experimental`

A Temperate terrain generator with detailed control over oceans, coastlines, lakes, rivers,
mountains, flat buildable land and transport corridors. It is built on the vanilla Temperate
generator, so forests, ground textures, biome-based industry placement (oil platforms, fishing,
mines, ...) and towns work as in vanilla.

> **Experimental.** The river network is produced by a custom script node shipped with this mod.
> The *Recipe* and *Great river* options are dropdowns. If map generation fails, the game log
> (`stdout.txt`, see *Troubleshooting*) shows why.

## Features

| Area | What you get | How it works |
|---|---|---|
| Meandering rivers | Natural, non-repeating meanders up to looping lowland rivers | A Kinoshita "sine-generated curve", the standard model of real meanders. The wavelength is 10-16 x channel width and varies randomly along the river, with skewed lobes. Amplitude varies too and is damped in rough terrain. |
| River widths | Narrow streams at the source, wider downstream, widening at every confluence, estuaries at mouths, wider outer banks in bends | Width follows the water a river carries: its upstream length plus every tributary. Rivers reaching the ocean or a lake flare out 1.3-2x (great river 1.8-2.6x). |
| Streams vs. rivers | Scenic streams about 20-40 m wide; trunks 60-160 m mid-course and 150-600 m at estuaries | *River width* scales only the large rivers. *Tributaries* sets how many side streams branch off. |
| Deltas | Large rivers reaching water may split into 2-3 curved arms, each possibly splitting again | *River deltas* slider |
| Great river | One large river that crosses the whole map from the coast side to the far edge | *Great river* dropdown. With *Ocean coast None* it runs edge to edge. |
| Coastlines | Coves, points and small inlets on top of large bays; offshore islands; stretches of wide beaches next to steep drop-offs | *Coastline detail*, *Offshore islands* and *Shore variety* sliders |
| Recipes | Easy builder, Challenging terrain, Maritime, Coast to mountains, Alpine, Landlocked, Great plains | *Recipe* dropdown. A recipe **shifts** the sliders by fixed steps: at default sliders you get the preset, and the sliders still fine-tune around it. *Custom* = sliders only. (The menu cannot move the slider handles, so they keep showing your settings.) |
| Buildability | Control over flat land share, lowland flatness, hill height, mountain coverage and height, flat valley floors along rivers, and flat corridors through hills for railways and highways | See *Sliders* |

### Limitations
- **Jetties and sand bars/spits:** features narrower than about 100-200 m are smoothed out by the
  generator's 300-400 m terrain blending.
- **Land-side cliffs:** *Shore variety* changes the underwater slope only.
- **Oxbow lakes** (cut-off meanders) are not generated.

## Sliders

Defaults in **bold**.

| Slider | Values | Effect |
|---|---|---|
| Recipe | **Custom (sliders only)** / Easy builder / Challenging terrain / Maritime / Coast to mountains / Alpine / Landlocked / Great plains | play-style preset |
| Ocean coast | None / **Auto (short edge)** / West / East / North / South | which map edge has an ocean |
| Ocean size | Tiny / Small / **Medium** / Large / Huge | 6-32 % of the map length |
| Shoreline | Steep / Firm / **Medium** / Soft / Gentle | width of the slope from shore to deep water (120-900 m) |
| Coastline detail | Smooth / **Natural** / Rugged / Very rugged | shore irregularity 0 / 267 / 533 / 800 m |
| Offshore islands | None / **Few** / Some / Many | about 0 / 3 / 7 / 14 islands on a Medium map with Medium ocean |
| Shore variety | Uniform / **Varied** / Strong | shore slope width varies ±0 / 35 / 65 % along the coast |
| Lakes | None / Rare / Few / **Normal** / Many / Abundant | lake count (scales with map area) |
| Lake size | Small / Smallish / **Medium** / Large / Huge | 3-10 km lake stamps |
| Rivers | None / Few / Some / **Normal** / Many / Lots | number of rivers |
| River width | Narrow / Slim / **Normal** / Wide / Very wide | width of large rivers (0.6-1.7x) |
| River meandering | Straight / Gentle / **Normal** / Winding / Meandering | meander strength |
| River valleys | Narrow V / Tight / **Normal** / Broad / Wide flats | flat valley floor 0-450 m each side of rivers |
| Tributaries | Few / Some / **Normal** / Many / Lots | how many side streams branch off |
| Great river | **No** / Yes | one river across the map |
| River deltas | None / **Some** / Frequent | delta chance 0 / 50 / 100 % for large rivers reaching water |
| Mountains | None / Rare / Few / **Normal** / Many / Dominant | about 0-32 % of land is mountain massif |
| Mountain height | Low / Moderate / **Normal** / High / Very high | alpine peaks 180-560 m above the plateau |
| Flat land | Scarce / Limited / **Normal** / Plenty / Vast | about 20-70 % of land is flat lowland |
| Hill height | Gentle / Low / **Normal** / High / Rugged | hill relief 40-210 m |
| Lowland relief | Flat / Smooth / **Normal** / Rolling / Undulating | lowland undulation 1-14 m |
| Landscape scale | Fine / Small / **Normal** / Large / Broad | size of terrain regions |
| Inland rise | Off / Slight / **Moderate** / Strong / Very strong | terrain rises from the coast side toward the far side |
| Corridors | None / Few / **Some** / Many / Lots | flat-bottomed valleys (about 800 m wide) through hills and mountains |

Tips:
- Keep some water: Ocean coast not *None*, or Lakes at least *Few*. Oil platforms, fishing grounds
  and sand excavators need open water.
- Rock and snow textures start at about 330 m and 380 m, so *Mountain height* Low/Moderate gives
  mountains without snow caps.

## Install
- **mod.io:** subscribe, then enable the mod for a new game.
- **Manually:** copy this folder into your Transport Fever 3 user-data folder under
  `staging_area/` (or `mods/`), so that `mod.json` sits directly inside the copied folder. The
  user-data folder is `<Steam>/userdata/<your Steam ID>/3493540/local/`.

Then: New Game -> climate **Temperate** -> generator **Custom Terrain (Experimental)**. The
terrain is stored in the savegame, so the mod is only needed to generate maps.

## Diagnostics log
On every map generation (including previews in the New Game screen) the mod writes one line
starting with `CT_DIAG` and one starting with `CT_RIVERS` to the game log
(`<user-data folder>/crash_dump/stdout.txt`). Each line holds JSON: the slider values as the
generator received them, seed, map size, and statistics of the generated terrain (water share,
buildable-grade shares, height percentiles, biome shares, river network size). This helps when
reporting issues or tuning settings. The logger runs in a protected block and outputs nothing that
affects the terrain.

## Troubleshooting

| Symptom | Check |
|---|---|
| Mod listed under My Mods but not in the mod selection | `_metadata/modinfo.json` tags must not contain `Map`, `Map/Savegame` or `Savegame` (those are hidden from the selector) |
| Map generation fails | look in `stdout.txt` for lines mentioning `custom_terrain`, `node_editor` or `Lua` |
| Too much or too little of something | try a *Recipe*, then fine-tune the sliders |

## For developers
- The mod is data plus two plain-Lua script nodes (the engine embeds Lua 5.2):
  - `content/gui/node_editor/custom_terrain_rivers.script.lua` implements the river network (see
    its header). `custom_terrain_river_points.node.lua` declares its sockets and params.
  - `custom_terrain_diag.*` is the diagnostics logger.
- The node graph (`content/climates/temperate/custom_terrain_experimental_gen.tree.lua`) is
  generated by a build script that splices slider logic into the vanilla Temperate graph. New nodes'
  names start with "mg", and they are coloured orange (sliders green) in the in-game Terrain Generator Editor. All
  vanilla outputs (heightmap, biome maps, assets, map data) keep their names and meaning, so the
  vanilla climate, economy and audio keep working.
