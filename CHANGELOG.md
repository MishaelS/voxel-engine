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
