# voxel-engine

A voxel engine for Godot 4.5.

## Running
Open the project folder in Godot 4.5+ (Import → `project.godot`) and press F5.
Controls
* LMB: capture the mouse, Esc - release it
* WASD: movement, E/Space - up, Q - down
* Shift: speed boost, mouse wheel - base speed

## Structure
* `scenes/main.tscn` - main scene (sky, sun, floor, voxel, camera, HUD)
* `scripts/voxel_block.gd` - the voxel, whose mesh is assembled face by face (the foundation for future chunk meshing)
* `scripts/free_camera.gd` - free camera
* `scripts/hud.gd` - FPS and hints