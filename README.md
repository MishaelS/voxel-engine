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
* T: open the chat, /: open it with a command (Tab completes, Up/Down choose, Esc closes)
* P: freeze game ticks, . (period): run one tick while frozen
* M: skip to the next day (moon phases)
* F3: toggle VSync (off by default)
* F11 / Alt+Enter: toggle fullscreen (the window starts maximized and can be resized)

## Commands
Type `/help` in the chat. Commands are trees of literals and typed arguments; parsing, suggestions,
usage and `/help` all come from the same definition (`scripts/commands/builtin/*_command.gd`):

```gdscript
d.register(CommandNode.literal("setblock").describe("Changes a block")
	.then(CommandNode.argument("pos", PositionArgument.new(true))
		.then(CommandNode.argument("block", BlockArgument.new()).executes(func(ctx: CommandContext) -> int:
			ctx.source.world.set_block(ctx.arg("pos"), ctx.arg("block"))
			return ctx.feedback("Changed the block")))))
```

New command: add a file with a static `register(dispatcher)` and call it in `Commands._create()`.
New argument type: extend `ArgumentType` (`parse`, `suggest`). New game rule: one `GameRules.register()` call.

## Game ticks
All game logic runs in fixed ticks, 20 per second (`TickLoop` autoload), like the classic game:
the world clock (24000 ticks per day), scheduled block ticks, random block ticks and block updates.
Rendering runs every frame and interpolates between ticks. A block reacts to ticks through
handlers in its `BlockType`:

```gdscript
register(BlockType.cube("sand", 18)
	.set_on_update(Callable(FallingBlockBehavior, "on_update"))          # neighbor changed
	.set_scheduled_tick(Callable(FallingBlockBehavior, "scheduled_tick"))) # world.schedule_tick(pos, delay)
register(BlockType.cube("grass", 0).set_random_tick(Callable(GrassBehavior, "random_tick")))
```

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
* `scripts/core/tick_loop.gd` - autoload: fixed-rate game tick loop (20 TPS), phases, freeze/step
* `scripts/core/game_input.gd` - blocks gameplay input while typing
* `scripts/commands/` - command system: dispatcher, nodes, argument types, game rules, built-in commands
* `scripts/ui/chat.gd` - chat with command suggestions and history
* `scripts/voxel/world_clock.gd` - world time in ticks (game time, day time)
* `scripts/voxel/voxel_world.gd` - chunks, world ticks (scheduled, random, block updates), async re-meshing; `generator` switches terrain / random blocks
* `scripts/voxel/behaviors/` - block tick behaviors (grass, falling blocks)
* `scripts/voxel/random_blocks_generator.gd` - debug world: every block type scattered randomly
* `scripts/day_night_cycle.gd` - sun/moon movement (latitude, seasons, analemma), day counter, moon phases, light; drives the sky
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
