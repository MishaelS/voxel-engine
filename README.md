# voxel-engine

A voxel engine for Godot 4.5.

## Running
Open the project folder in Godot 4.5+ (Import → `project.godot`) and press F5.
Controls
* LMB: capture the mouse, Esc - release it
* WASD: movement, E/Space - up, Q - down
* Shift: speed boost, mouse wheel - base speed
* R: regenerate the world with a new seed
* Up/Down arrows: time of day, Left/Right: rotate the sun path
* T: toggle the automatic day/night cycle
* M: skip to the next day (moon phases)
* F3: toggle VSync (off by default)
* F11 / Alt+Enter: toggle fullscreen (the window starts maximized and can be resized)

## Structure
* `scenes/main.tscn` - main scene (sky, sun, voxel world, camera, HUD)
* `assets/textures/terrain.png` - block texture atlas (16×16 tiles)
* `assets/textures/sky/` - sun and moon textures (32×32, 8×8 disc with a halo)
* `shaders/` - block shaders (opaque, cutout, translucent) and the sky shader
* `scripts/voxel/blocks.gd` - block registry: all block types and their atlas tiles
* `scripts/voxel/block_type.gd` - block type description (faces, overlay, tint, render layer)
* `scripts/voxel/block_materials.gd` - atlas → Texture2DArray, one material per render layer
* `scripts/voxel/chunk_data.gd` - block storage of a 16×16×16 chunk
* `scripts/voxel/chunk_mesher.gd` - chunk meshing with hidden face culling and voxel AO
* `scripts/voxel/terrain_generator.gd` - noise heightmap terrain
* `scripts/voxel/voxel_world.gd` - owns chunks, builds meshes, render stats; `generator` switches terrain / random blocks
* `scripts/voxel/random_blocks_generator.gd` - debug world: every block type scattered randomly
* `scripts/day_night_cycle.gd` - sun/moon movement, day counter, moon phases, light; drives the sky
* `scripts/free_camera.gd` - free camera
* `scripts/hud.gd` - FPS, render stats and hints
* `scripts/window_controls.gd` - autoload: minimum window size, fullscreen and VSync toggles

## Adding a block
Append a `register()` call at the end of `Blocks._register_all()` in `scripts/voxel/blocks.gd`:

```gdscript
register(BlockType.cube("bricks", 7))                       # same tile on every face
register(BlockType.column("pumpkin", 102, 118))             # top / sides (/ bottom)
register(BlockType.cube("ice", 67).set_layer(Layer.CUTOUT)) # transparent pixels cut out
```

Tile number = `row * 16 + column` in the atlas. Always append at the end: ids follow registration order.
