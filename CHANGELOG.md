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
- Debug sun control (`scripts/debug_sun.gd`): arrow keys rotate the sun and change its elevation; HUD shows world generator, seed and sun angles.

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
