# voxel-engine

A voxel engine for Godot 4.5.

## Running
Open the project folder in Godot 4.5+ (Import → `project.godot`) and press F5.
Controls
* LMB: capture the mouse, Esc - release it
* WASD: movement, E/Space - up, Q - down
* Shift: speed boost, mouse wheel - base speed
* F11 / Alt+Enter: toggle fullscreen (the window starts maximized and can be resized)

## Structure
* `scenes/main.tscn` - main scene (sky, sun, voxel world, camera, HUD)
* `scripts/voxel/blocks.gd` - block type registry
* `scripts/voxel/chunk_data.gd` - block storage of a 16×16×16 chunk
* `scripts/voxel/chunk_mesher.gd` - chunk meshing with hidden face culling
* `scripts/voxel/terrain_generator.gd` - noise heightmap terrain
* `scripts/voxel/voxel_world.gd` - owns chunks, builds meshes, render stats
* `scripts/free_camera.gd` - free camera
* `scripts/hud.gd` - FPS, render stats and hints
* `scripts/window_controls.gd` - autoload: minimum window size, fullscreen toggle
