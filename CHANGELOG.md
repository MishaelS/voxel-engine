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
- Player (`scripts/player/player.gd`) with the movement of the classic game, replacing the free-flying camera: physics in fixed steps of 20 per second with the classic constants (blocks per tick), interpolated for rendering; a 0.6 x 1.8 box colliding with blocks axis by axis (Y, X, Z), eyes at 1.62. Walking 4.32 m/s, sprinting 5.66 m/s (**Ctrl** or double-tap **W**, sprint-jumps push forward, FOV widens), jump height 1.25 blocks, ground friction (ice is slippery), stepping up to 0.6 blocks, sneaking (**Shift**: x0.3 speed, eyes lower, no walking off edges), swimming (Space swims up, climbing out onto the shore), creative flying (double-tap **Space**, Space / Shift up and down, ends on landing), view bobbing (new Video setting).
- Game modes, survival and creative, and `/gamemode <survival|creative>` (also `s`/`c`, `0`/`1`). The game starts in creative.
- Inventory (`scripts/player/inventory.gd`): 36 slots (hotbar + main), stacks of up to 64. The hotbar shows the first 9 slots with item counts.
- Inventory windows on **E** (`scripts/ui/inventory/`), built on the container textures: survival with armor slots (empty for now), a 2x2 crafting grid and result, the main inventory and the hotbar; creative with every block in a scrollable 9x6 catalog. Classic mouse handling: pick up / put down / swap stacks, right click for half / one, shift-click to move between hotbar and inventory, number keys over a slot to swap with the hotbar, tooltips with block names. Closing returns the held stack and the crafting grid to the inventory.
- Crafting (`scripts/player/crafting.gd`): shaped recipes matched anywhere in the grid; logs -> 4 planks, 2x2 planks -> crafting table, 2x2 sand -> sandstone.
- Survival block breaking: hold LMB, time = hardness x 1.5 s by hand (new `BlockType.hardness`, classic values; bedrock and water can't be broken), crack stages from the atlas drawn over the block; the block (or its drop: stone -> cobblestone, grass -> dirt, glass / leaves / ice -> nothing) goes into the inventory. Placing uses up one item. Creative: instant breaking and placing without using items. Holding the buttons repeats (5 / 4 ticks) like the classic game.
- `BlockType.collides`, `slipperiness`, `drop`; `Blocks.collides_table`, `Blocks.drop_of()`, `Blocks.display_name()`.
- Debug screen: game mode, horizontal speed and player state (on ground, flying, sprinting, sneaking, in water); XYZ is now the feet position.
- Sky light like the classic game (`scripts/voxel/sky_light.gd`): every block has a light level 0..15; full light comes straight down from the sky (leaves take 1, water and ice 2, solid blocks stop it), then spreads sideways and down into overhangs and caves, losing at least 1 per block. A column is lit on a worker thread from the 3x3 columns around it, so there are no seams at column borders; cells above the heightmap are never stored or visited, so it stays cheap.
- Re-lighting on block changes: light removal and re-spreading from the changed block (the classic algorithm); only chunks whose light changed are re-meshed.
- Smooth lighting in the mesher: each vertex gets the average light of the up to 4 clear cells around the corner, mapped with the classic light curve (level 0 keeps 5%) and combined with voxel AO. With Smooth Lighting off, faces get flat light.
- `BlockType.light_opacity`, per-chunk light arrays and per-column heightmaps. Debug screen: sky light at the player and at the targeted face, lighting jobs.
- Endless world (`VoxelWorld`): columns of 8 chunks (128 blocks high) are generated around the player on worker threads, nearest first, meshed once their neighbor columns exist and unloaded when far away; `Render Distance` setting (2-16 chunks, default 6) with fog starting at 60% of it like the classic game. Spawn is searched on land.
- Beta 1.7.3 style world generator (`scripts/worldgen/beta_generator.gd`, own implementation of the same approach): 3D density terrain from limit / main / depth / scale noises with overhangs, sea level 64; biomes from temperature and humidity with the classic table (tundra, taiga, swampland, forest, seasonal forest, rainforest, savanna, shrubland, plains, desert); grass / dirt surface, sand and gravel beaches, sandstone, uneven bedrock; worm caves and rooms crossing columns; ore veins and dirt / gravel pockets at the classic heights; oak, birch, spruce and pine trees by biome; ice on cold water. Deterministic per seed.
- `WorldGenerator` base class for column generators; the random-blocks debug world is one of them.
- Blocks: snowy grass, snow, ice.
- Debug screen: biome, loaded / visible chunks, columns, render distance, generation and meshing jobs.
- Falling block entities (`scripts/entities/falling_blocks.gd`): sand and gravel with nothing below turn into entities that accelerate down smoothly (classic physics per tick: gravity 0.04, drag 0.98) and become blocks again where they land; blocks landing in the same column in the same tick stack up. Simulated in game ticks on packed arrays (no node per entity), rendered with one MultiMesh per block type using the chunk block mesh and materials, positions interpolated between ticks. Tested with 256 blocks falling at once: under 1 ms per tick.
- Debug screen shows the number of falling block entities.
- Hotbar (`scripts/ui/hotbar.gd`) drawn with hotbar.png / hotbarSelector.png: 9 slots with isometric block icons generated from the atlas (`BlockIcons`: top, south and east faces with shading, biome tints and overlays), selection with **1-9** or the mouse wheel, block name shown above for 2 s.
- Crosshair (`scripts/ui/crosshair.gd`, cursor.png) that inverts the colors behind it.
- Block interaction (`scripts/player/block_interaction.gd`) with the mouse captured: **LMB** breaks, **RMB** places the selected block, **MMB** picks the targeted block into the hotbar; reach 5 blocks, outline around the targeted block. Edits go through `set_block`, so block updates apply (sand falls, grass reacts).
- `VoxelWorld.raycast()`: voxel traversal (Amanatides & Woo) returning the hit block, face and distance; air and water are passed through.
- Debug screen (`scripts/ui/debug_screen.gd`) in the style of the classic F3 screen, toggled with **F3**: version, FPS, render stats, ticks, chunks and faces, XYZ / block / chunk position, facing with yaw and pitch, world, clock, sun and light on the left; renderer, memory, CPU, GPU, display, render settings and the targeted block (name, id, layer, face, distance, tick behaviors) on the right. Each line on a translucent gray background.
- `application/config/version` in project.godot (shown on the debug screen).
- In-game menu (`scripts/ui/menu/`): **Esc** pauses the game (ticks stop) and opens a minimal Game Menu with one button, Options; Esc / Done go back. Options: FOV, Video Settings, Controls, World Settings. Styled like the classic game with the GUI widget textures (buttons, sliders) and the pixel font with shadows (`UiTheme`, shared with the chat).
- Settings system (`scripts/settings/`): every option is a `Setting` (toggle, choice or range) registered by category in the `Settings` autoload and saved to `user://settings.cfg`; menus build widgets from settings automatically. Video: render scale, max framerate, VSync, fullscreen, GUI scale, anti-aliasing, shadows, smooth lighting (voxel AO), clouds, fog, brightness, debug info. Controls: mouse sensitivity, invert mouse.
- Key bindings (`KeyBindings`): every action can be rebound on the Controls screen (click, press a key, Esc cancels), conflicts are shown in red, Reset Keys restores the defaults; saved with the settings.
- World Settings screen built from the `GameRules` registry (doDaylightCycle, randomTickSpeed) plus generator, seed and world regeneration.
- Command system modeled on Brigadier (`scripts/commands/`): commands are trees of literals and typed arguments (`CommandNode`); `CommandDispatcher` parses and runs them, suggests completions for the text being typed and builds usage strings and `/help` from the same tree, so every command is described once. Errors are reported like the classic game (`...<--[HERE]`).
- Reusable argument types with their own parsing and suggestions (`scripts/commands/arguments/`): integer, float, bool, choice (fixed or dynamic list), block (from the registry), position with `~` relative coordinates, time (`100`, `5s`, `2d`), message (rest of the line).
- Commands: `/help [command]`, `/time set|add|query`, `/tick query|freeze|unfreeze|step|rate`, `/gamerule <rule> [value]` (generated from the `GameRules` registry: `doDaylightCycle`, `randomTickSpeed`), `/setblock`, `/fill`, `/tp`, `/seed`, `/say`.
- Chat (`scripts/ui/chat.gd`) in the Minecraft Rus font: **T** opens it, **/** opens it with a command; suggestion list above the current word (Up/Down select, Tab inserts), the rest of the chosen suggestion in gray after the cursor, expected argument or the parse error shown while typing, sent-message history on Up/Down, Page Up/Down scroll, messages fade out 10 s after closing.
- `GameInput` lock: camera and sun controls ignore keys and clicks while the chat is open.
- Game tick system (`scripts/core/tick_loop.gd`, autoload `TickLoop`): all game logic runs at a fixed 20 ticks per second independent of FPS, in ordered phases (world, entities, late); catch-up capped at 10 ticks per frame; `alpha` for interpolating visuals between ticks; measured TPS and ms per tick in the HUD; **P** freezes ticks, **.** steps one tick while frozen.
- World clock in ticks (`scripts/voxel/world_clock.gd`): `game_time` (only grows) and `day_time` (24000 ticks per day, can be moved), `daylight_cycle` switch.
- World ticks in `VoxelWorld`: scheduled block ticks (merged per position, capped per tick), random ticks (`random_tick_speed` = 3 per chunk per tick) and block updates sent to a changed block and its 6 neighbors; `get_block` / `set_block` in world coordinates.
- Block tick handlers in `BlockType` (`random_tick`, `scheduled_tick`, `on_update`) and the first behaviors (`scripts/voxel/behaviors/`): grass spreads onto uncovered dirt and turns into dirt under opaque blocks; sand and gravel fall (now as smooth falling entities, see above).
- Changed chunks are re-meshed on worker threads (`WorkerThreadPool`) from a snapshot and swapped in when ready, so block changes do not stall frames.
- Cubic chunks of 16×16×16 blocks: `ChunkData` (`scripts/voxel/chunk_data.gd`), a flat one-byte-per-block array.
- Block registry `Blocks` (`scripts/voxel/blocks.gd`) and `BlockType` (`scripts/voxel/block_type.gd`): per-face textures, optional per-face overlay, sRGB biome tint, render layer (opaque / cutout / translucent) and same-type face culling. New blocks are one `register()` call.
- 52 block types: stone, dirt, 5 biome grasses (plains, forest, taiga, swamp, savanna), cobblestone, bedrock, sand, gravel, sandstone, obsidian, water; oak/birch/spruce logs, leaves and planks; coal/iron/gold/lapis/diamond/redstone ores; iron/gold/lapis/diamond blocks; glass; 16 wool colors; crafting table and furnace (front faces +Z for now).
- Texture atlas `assets/textures/terrain.png` (16×16 tiles), sliced into a `Texture2DArray` at runtime by `BlockMaterials` (`scripts/voxel/block_materials.gd`): no tile bleeding at mip levels, nearest filtering with mipmaps and anisotropy.
- Block shaders (`shaders/`): opaque, cutout (alpha scissor: glass, leaves) and translucent (water); shared code applies tint, overlay and baked AO.
- `ChunkMesher` (`scripts/voxel/chunk_mesher.gd`): builds chunk geometry with hidden face culling, one surface per render layer; returns plain surface arrays so it can later run on worker threads.
- `VoxelWorld` (`scripts/voxel/voxel_world.gd`): owns chunks, builds their meshes and collects render stats.
- HUD shows chunk count, visible vs. naive face count, triangles, vertices and meshing time.
- `WindowControls` autoload (`scripts/window_controls.gd`): F11 / Alt+Enter toggles fullscreen and F4 VSync (both change the same settings as the Video menu), minimum window size 640×360.
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
- Controls like the classic game: **Space** jumps, **Shift** sneaks, **Ctrl** sprints, **E** opens the inventory (were fly up / fly down / speed boost); key binding actions `jump`, `sneak`, `inventory`.
- Block icons are rendered by the GPU (`BlockIcons`): an orthographic view of the block's own mesh at the classic angle, at exactly the slot's pixel size, so texture pixels are sharp and even (the old CPU projection drew them unevenly). Placement is refused only where the block would overlap the player's box.
- Faster world loading (render distance 6: first chunk 2.5 s -> 0.7 s, whole area 20.9 s -> 5.3 s). In GDScript, function calls, engine method calls, Dictionary and generic Array reads serialize across worker threads, so the hot loops of generation, sky light and meshing now use only inline arithmetic on packed arrays (block / light tables, AO offsets and corner offsets as packed arrays, biomes as packed tables). Worker scaling: generation 3.6x, light 7.1x, meshing 4.6x (was below 1x).
- Columns that start no caves are skipped with an inline hash before creating a random generator; tunnels that can never reach the column are dropped early; bedrock no longer draws a random number for every block of the column. World generation for a given seed differs slightly (cave placement, bedrock pattern).
- Chunks to mesh are kept in a sorted queue rebuilt only when something changes (column lit or loaded, player moved, block changed) instead of rescanning every waiting chunk each frame: worst main-thread cost while flying dropped from ~11 ms to ~1 ms.
- Opaque and cutout block shaders use Lambert diffuse without specular (blocks are fully rough anyway).
- The crosshair copies only its own rectangle of the screen to invert the colors behind it, instead of the whole (Retina-sized) frame every frame.
- Debug screen text is rebuilt every 50 ms instead of every frame.
- Streaming pipeline: generate (render distance + 1) -> light (when the 8 neighbor columns exist; the outer ring treats unloaded neighbors as solid) -> mesh (when the 8 neighbor columns are lit). Caves are dark now instead of lit by the sky everywhere.
- `threading/worker_pool/low_priority_thread_ratio` raised to 0.75 so world jobs may use more worker threads.
- `ChunkMesher` works on a padded 18³ volume (the chunk plus a border from its 26 neighbors): faces and AO are correct across chunk borders and neighbor lookups are plain index offsets; fully buried chunks are skipped. Editing a block on a chunk border re-meshes the neighbor chunks too.
- Random ticks skip chunks without random-ticking blocks (tracked per chunk).
- Shadow presets: Low = 2 cascades up to 48 blocks, High = 4 cascades up to 64 blocks (far shadows are under fog and cost draw calls).
- The old HUD label is replaced by the debug screen (hidden by default, F3 shows it); the controls hint moved to the Controls screen.
- VSync hotkey moved from F3 to F4 (F3 is the debug screen, like the classic game).
- Mouse wheel selects the hotbar slot; fly speed is now Ctrl + mouse wheel.
- The first click only captures the mouse; clicks with the mouse captured act on blocks.
- Chat messages are shown above the hotbar.
- Main scene renders a terrain chunk instead of a single voxel; camera moved to frame the chunk.
- Blocks are textured instead of vertex-colored; voxel AO and biome tint are passed in the vertex color (rgb = tint, a = AO).
- The window starts maximized and is explicitly resizable.
- VSync is off by default, so FPS is no longer capped at the monitor refresh rate.
- Rendering optimized for high-DPI screens (measured on Apple M4, 3420×2090: 50 → ~155 FPS): SSAO removed (replaced by voxel AO), MSAA 2x replaced by FXAA, hard directional shadows.
- Main scene starts in `RANDOM_BLOCKS` mode.

### Fixed
- Voxel AO was 2–3× too dark: the AO factor was applied to sRGB vertex colors and then gamma-expanded by the material (0.5 became ~0.22). Block colors are now converted to linear once and AO is applied in linear space (`vertex_color_is_srgb = false`).

### Removed
- Free-flying camera (`FreeCamera`, Ctrl + mouse wheel fly speed): replaced by the player and creative flying.
- The single-chunk heightmap `TerrainGenerator` (replaced by the beta generator).
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
