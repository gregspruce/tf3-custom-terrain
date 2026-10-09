# Changelog - Custom Terrain

All notable changes to the Custom Terrain mods and their tooling.
Format: [Keep a Changelog](https://keepachangelog.com/). Last Updated: 2026-10-09.

## [Released] revision 1 - mod.io 6424823 (recorded 2026-10-09)
- Published before the workspace history began; the committed state is the published version (author). Release
  tag `ct-r1`; public repository `tf3-custom-terrain` (release r1).

## [exp 0.3.2] - 2026-10-05 - author name

### Changed
- modinfo author is now "TangoEchoXray" (was "Custom Terrain contributors"). The single source is
  `AUTHOR` in `tools/build_tree.py` (the build_exp override was removed). The rebuild changed only that line.

## [exp 0.3.1] - 2026-10-05 - moved into the multi-project workspace (no mod changes)

### Changed
- Mod folder renamed to `custom_terrain_experimental/` (the folder name has no functional meaning in the game;
  modId unchanged). Build output byte-identical.
- The earlier v1 generator was retired; build_tree.py remains the base library.

## [exp 0.3] - 2026-10-03 - prepared for public release (fork only)

### Changed
- Names prepared for public release: modId `custom_terrain_experimental` (generator files renamed to match);
  script nodes `custom_terrain_river_points` / `custom_terrain_rivers` / `custom_terrain_diag`; log tags
  `CT_DIAG`/`CT_RIVERS`; modinfo author "Custom Terrain
  contributors"; README rewritten for public readers. v1 output unchanged
  (byte-identical); `build_tree.AUTHOR` makes the author configurable.
- `_metadata/description.html` (shown in the in-game mod browser and uploaded to mod.io; overrides the
  modinfo description) is generated from README.md on every build by tools/readme_to_html.py:
  basic tags only, tables converted to lists.
- tools/analyze_tests.py accepts any `<PREFIX>_DIAG` / `<PREFIX>_RIVERS` tag (old logs still parse).

## [exp 0.2] - 2026-10-01 - automated test logging (fork only)

### Added
- Diagnostics script node (generated `.node.lua`, plain Lua script): on every generation it writes a
  `CT_DIAG {json}` line (tag name since 0.3): slider values as received, seed, map size, terrain
  stats from the final heightmap. Runs in pcall; its output (always 0) is wired into a zero param
  only to schedule it after the terrain.
- River node writes a `CT_RIVERS {json}` summary (tag name since 0.3).
- tools/analyze_tests.py: parses the game log (plus engine pipeline time/memory and seed text),
  verifies the slider convention, analyzes exported heightmaps and lists screenshots, then writes
  testlogs/<stamp>_report.md.
- preview.py runs the diagnostics script offline too (Lua 5.2), capturing its log lines.

## [exp 0.1] - 2026-10-01 - experimental fork, untested in game

### Added (fork only; v1 output is byte-identical)
- Custom river script node (plain Lua,
  tools/exp_src/): Kinoshita meanders with varying wavelength and amplitude, discharge-based
  widths (streams to trunks), estuary flares, confluence bulges, outer-bank widening in bends,
  curved bifurcating deltas, optional great river crossing the map. Order-dependent river spacing
  gives many more tributaries.
- Coast: multi-scale shoreline detail, offshore islands (tropical island atlas), shore steepness
  variety.
- Recipe ComboBox (7 presets that shift the sliders); new sliders: Tributaries, Great river,
  River deltas, Coastline detail, Offshore islands, Shore variety.
- Tooling: tools/build_exp.py, `--exp` mode in tools/preview.py, which runs the real Lua river
  script via a vendored Lua 5.4 (tools/_vendor/lupa) and rasterizes the channels; tools/_river_stats.py.
- treetool lint accepts mod-shipped node types, validated against their.node.lua.

## [1.0.1] - 2026-10-01 (mod.json revision 1)

### Fixed
- Mod did not appear in the new-game mod selection: `_metadata/modinfo.json` was tagged `"Map"`,
  which the selector excludes (map/savegame content). Now tagged `"Temperate"` (from the game's
  built-in tag list).

## [1.0.0] - 2026-10-01 (mod.json revision 1) - untested in game

### Added
- Temperate generator "Custom Terrain" (`order = 20`), forked from the vanilla Temperate graph with
  all 14 vanilla outputs preserved.
- 17 sliders: Ocean coast (None/Auto/W/E/N/S), Ocean size, Shoreline, Lakes, Lake size, Rivers,
  River width, River meandering, River valleys, Mountains, Mountain height, Flat land, Hill height,
  Lowland relief, Landscape scale, Inland rise, Corridors.
- Ocean along a chosen edge (coast-axis machinery), merged into
  the vanilla water mask.
- Flat-floored river valleys (floor width plus wall scale).
- Corridors: flat U-shaped valleys through hills and mountains, independent of rivers; alpine
  peaks faded near them.
- Biome coverage split calibrated to land-area targets via offline previews.
- Tooling: `tools/treetool.py` (parser/serializer/lint), `tools/build_tree.py` (builder),
  `tools/preview.py` (approximate previewer).
- Docs: README, architecture, slider and testing notes.

### Changed (vs vanilla behaviour)
- Height-blend weights sum to 1. This removes possible border ridges and is robust to the unknown
  maskcomb formula. The water mask stays authoritative, so the Shoreline slider still shapes the
  depth ramp (review fix).
- Mountains = None now gives a strictly empty B4 interval. Upland and plateau base heights scale up
  with High/Rugged hills. Lint checks that defaultIndex is 1-based (review fixes).
- Biome field mapped with a fixed range instead of per-map min/max (more predictable shares across
  seeds). Seeded region frequency narrowed to 0.00018..0.00026.
- Biome 4 noise gets its own seed (vanilla B3/B4 used identical noise).
- Lake count rounds instead of floors. Alpine stamp height calibrated to the real atlas maximum
  (0.6468).
- 37 vanilla nodes removed (dead in vanilla, or replaced by slider logic).
