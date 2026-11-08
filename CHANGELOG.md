# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versioning follows [Semantic Versioning](https://semver.org/).

Sections:
- **Added** - new features.
- **Changed** - changes to existing behavior.
- **Fixed** - bug fixes.
- **Removed** - removed features.

## [Unreleased]

### Added
- Command system modeled on Brigadier (`scripts/commands/`): commands are trees of literals and typed arguments (`CommandNode`); `CommandDispatcher` parses and runs them, suggests completions for the text being typed and builds usage strings and `/help` from the same tree, so every command is described once. Errors are reported like the classic game (`...<--[HERE]`).
- Reusable argument types with their own parsing and suggestions (`scripts/commands/arguments/`): integer, float, bool, choice (fixed or dynamic list), block (from the registry), position with `~` relative coordinates, time (`100`, `5s`, `2d`), message (rest of the line).
- Commands: `/help [command]`, `/time set|add|query`, `/tick query|freeze|unfreeze|step|rate`, `/gamerule <rule> [value]` (generated from the `GameRules` registry: `doDaylightCycle`, `randomTickSpeed`), `/setblock`, `/fill`, `/tp`, `/seed`, `/say`.
- Chat (`scripts/ui/chat.gd`) in the Minecraft Rus font: **T** opens it, **/** opens it with a command; suggestion list above the current word (Up/Down select, Tab inserts), the rest of the chosen suggestion in gray after the cursor, expected argument or the parse error shown while typing, sent-message history on Up/Down, Page Up/Down scroll, messages fade out 10 s after closing.
- `GameInput` lock: camera and sun controls ignore keys and clicks while the chat is open.
- Game tick system (`scripts/core/tick_loop.gd`, autoload `TickLoop`): all game logic runs at a fixed 20 ticks per second independent of FPS, in ordered phases (world, entities, late); catch-up capped at 10 ticks per frame; `alpha` for interpolating visuals between ticks; measured TPS and ms per tick in the HUD; **P** freezes ticks, **.** steps one tick while frozen.
- World clock in ticks (`scripts/voxel/world_clock.gd`): `game_time` (only grows) and `day_time` (24000 ticks per day, can be moved), `daylight_cycle` switch.
- World ticks in `VoxelWorld`: scheduled block ticks (merged per position, capped per tick), random ticks (`random_tick_speed` = 3 per chunk per tick) and block updates sent to a changed block and its 6 neighbors; `get_block` / `set_block` in world coordinates.
- Block tick handlers in `BlockType` (`random_tick`, `scheduled_tick`, `on_update`) and the first behaviors (`scripts/voxel/behaviors/`): grass spreads onto uncovered dirt and turns into dirt under opaque blocks; sand and gravel fall one block every 2 ticks.
- Changed chunks are re-meshed on worker threads (`WorkerThreadPool`) from a snapshot and swapped in when ready, so block changes do not stall frames.
- Cubic chunks of 16×16×16 blocks: `ChunkData` (`scripts/voxel/chunk_data.gd`), a flat one-byte-per-block array.
- Block registry `Blocks` (`scripts/voxel/blocks.gd`) and `BlockType` (`scripts/voxel/block_type.gd`): per-face textures, optional per-face overlay, sRGB biome tint, render layer (opaque / cutout / translucent) and same-type face culling. New blocks are one `register()` call.
- 52 block types: stone, dirt, 5 biome grasses (plains, forest, taiga, swamp, savanna), cobblestone, bedrock, sand, gravel, sandstone, obsidian, water; oak/birch/spruce logs, leaves and planks; coal/iron/gold/lapis/diamond/redstone ores; iron/gold/lapis/diamond blocks; glass; 16 wool colors; crafting table and furnace (front faces +Z for now).
- Texture atlas `assets/textures/terrain.png` (16×16 tiles), sliced into a `Texture2DArray` at runtime by `BlockMaterials` (`scripts/voxel/block_materials.gd`): no tile bleeding at mip levels, nearest filtering with mipmaps and anisotropy.
- Block shaders (`shaders/`): opaque, cutout (alpha scissor: glass, leaves) and translucent (water); shared code applies tint, overlay and baked AO.
- `ChunkMesher` (`scripts/voxel/chunk_mesher.gd`): builds chunk geometry with hidden face culling, one surface per render layer; returns plain surface arrays so it can later run on worker threads.
- `TerrainGenerator` (`scripts/voxel/terrain_generator.gd`): noise heightmap terrain.
- `VoxelWorld` (`scripts/voxel/voxel_world.gd`): owns chunks, builds their meshes and collects render stats.
- HUD shows chunk count, visible vs. naive face count, triangles, vertices and meshing time.
- `WindowControls` autoload (`scripts/window_controls.gd`): F11 / Alt+Enter toggles fullscreen, minimum window size 640×360, UI scaled by the screen DPI factor (readable HUD on Retina).
- HUD shows the current window size.
- Baked per-vertex voxel ambient occlusion in `ChunkMesher`: corners and creases are darkened (0fps method: two side neighbors + diagonal), quads are split along the darker diagonal to avoid AO anisotropy.
- F3 toggles VSync; HUD shows VSync state and frame time (total and render CPU).

- `RandomBlocksGenerator` (`scripts/voxel/random_blocks_generator.gd`): debug world with a stone floor and every block type scattered randomly, to inspect texture seams, transparency, AO and shadows.
- `VoxelWorld.generator` (`TERRAIN` / `RANDOM_BLOCKS`) and `random_density`; **R** regenerates the world with a new seed.
- Retro sky shader (`shaders/sky.gdshader`): day/night color gradient, sunrise/sunset glow, textured sun and moon with halos (`assets/textures/sky/`, hidden below the horizon; the disc covers the sky and stars, the halo is added), pixel stars after dusk, flat layer of blocky drifting clouds. Details are skipped in the radiance cubemap; the sky updates incrementally at 64 px radiance.
- Moon phases like the real Moon: the terminator is computed per texture pixel (crescent, quarter, gibbous, full), waxing lit on the right and waning on the left, the dark part keeps a faint earthshine, the halo and the moonlight follow the lit fraction. A full cycle takes `lunar_cycle_days` (8 by default; 29.5 is the real value).
- Day/night cycle `DayNightCycle` (`scripts/day_night_cycle.gd`), driven by the world clock and interpolated between ticks: sun path, warm low sun, dim bluish moonlight at night, drives the sky shader. Up/Down arrows change the time of day, Left/Right rotate the sun path, time stops with `/gamerule doDaylightCycle false` (24000 ticks = 20 min per day), **M** skips to the next day. Days are counted at sunrise. HUD shows world generator, seed, day, clock time and moon phase.
- Distance fog colored by the sky (aerial perspective).
- Seasons and the analemma: the sun position is computed for an observer at `latitude_deg` with the sun's declination (axial tilt 23.44°) and the equation of time (orbit eccentricity 0.0167) over a 365.24-day year, so at the same clock time the sun traces a figure 8 over the year; summer days are longer and the noon sun higher. The game starts at the March equinox; HUD shows the calendar date. `analemma_enabled` turns it off.

### Changed
- Main scene renders a terrain chunk instead of a single voxel; camera moved to frame the chunk.
- Blocks are textured instead of vertex-colored; voxel AO and biome tint are passed in the vertex color (rgb = tint, a = AO).
- The window starts maximized and is explicitly resizable.
- VSync is off by default, so FPS is no longer capped at the monitor refresh rate.
- Rendering optimized for high-DPI screens (measured on Apple M4, 3420×2090: 50 → ~155 FPS): SSAO removed (replaced by voxel AO), MSAA 2x replaced by FXAA, hard directional shadows.
- Main scene starts in `RANDOM_BLOCKS` mode.

### Fixed
- Voxel AO was 2–3× too dark: the AO factor was applied to sRGB vertex colors and then gamma-expanded by the material (0.5 became ~0.22). Block colors are now converted to linear once and AO is applied in linear space (`vertex_color_is_srgb = false`).

### Removed
- `VoxelBlock` (`scripts/voxel_block.gd`), replaced by chunk meshing.

## [0.0.1] - 2026-11-08

### Added
- Godot 4.5 project (Forward+), 1280×720 window, MSAA 2x.
- Git settings: `.gitignore` (`.godot/` cache, builds, OS and IDE files), `.gitattributes` (LF, binary assets), `.editorconfig`.
- Main scene `scenes/main.tscn`: procedural sky, sun with shadows, SSAO, floor.
- Voxel `VoxelBlock` (`scripts/voxel_block.gd`): a 1×1×1 cube, mesh assembled manually face by face into an `ArrayMesh`.
- Free camera `FreeCamera` (`scripts/free_camera.gd`): WASD, E/Space - up, Q - down, Shift - boost, mouse wheel - speed, LMB/Esc - capture mouse.
- HUD (`scripts/hud.gd`): FPS, camera position, control hints.
- Input actions in project settings: `move_*`, `sprint`.
- README describing running, controls, and structure.

[Unreleased]: https://github.com/MishaelS/voxel-engine/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/MishaelS/voxel-engine/releases/tag/v0.0.1
