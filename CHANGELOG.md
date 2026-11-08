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
- Block registry `Blocks` (`scripts/voxel/blocks.gd`): air, stone, dirt, grass (vertex colors for now).
- `ChunkMesher` (`scripts/voxel/chunk_mesher.gd`): builds chunk geometry with hidden face culling; returns plain surface arrays so it can later run on worker threads.
- `TerrainGenerator` (`scripts/voxel/terrain_generator.gd`): noise heightmap terrain.
- `VoxelWorld` (`scripts/voxel/voxel_world.gd`): owns chunks, builds their meshes and collects render stats.
- HUD shows chunk count, visible vs. naive face count, triangles, vertices and meshing time.
- `WindowControls` autoload (`scripts/window_controls.gd`): F11 / Alt+Enter toggles fullscreen, minimum window size 640×360, UI scaled by the screen DPI factor (readable HUD on Retina).
- HUD shows the current window size.

### Changed
- Main scene renders a terrain chunk instead of a single voxel; camera moved to frame the chunk.
- The window starts maximized and is explicitly resizable.

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
