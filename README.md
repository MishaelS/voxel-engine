# Voxel Engine Bedrock Edition

A voxel engine for Godot 4.5 by MishaelS.

## Running
Open the project folder in Godot 4.5+ (Import → `project.godot`) and press F5: the title screen
opens (Singleplayer → select or create a world). Worlds are saved in `user://saves/<world>/`.
Running `scenes/main.tscn` directly (F6) also goes to the title screen first.
Controls
* LMB: capture the mouse, then break blocks (survival: hold; the right tool is faster, stone and ores need a pickaxe to drop anything); MMB: pick the targeted block
* RMB: use the targeted crafting table, chest, furnace or bed (Shift: place against it instead), else use the item in hand: place a block, a bed, fill / pour a bucket, eat (hold)
* 1-9 / mouse wheel: hotbar slot; E: inventory (survival: 2x2 crafting; creative: all blocks and items); Q: throw one item (Ctrl+Q: the stack)
* Crafting table: 3x3 recipes (sticks, tools, chest, furnace, bed, bucket, ...); furnace: smelts ores, sand, cobblestone and logs with coal, charcoal or wood
* Beds skip the night (only at night) and set the respawn point; dropped items are picked up by walking over them
* F3: debug screen; F4: toggle VSync
* F1: hide GUI; F2: screenshot; F6: isometric camera (Z / X turn, wheel zooms); F7: isometric screenshot of the whole area
* Esc: menu (pauses the game): Options - video, controls (key rebinding), world
* WASD: walk; Space: jump (creative: double-tap to fly, then Space / Shift up and down)
* Ctrl or double-tap W: sprint; Shift: sneak (slower, doesn't fall off edges)
* `/gamemode survival|creative`: game mode (chosen when creating a world)
* Survival: health and hunger like the classic game (fall damage, starvation, natural healing at full food)
* R: regenerate the world with a new seed (unsaved test world only)
* Esc → Save and Quit to Title; the world also autosaves every 45 s and when the window closes
* T: open the chat, /: open it with a command (Tab completes, Up/Down choose, Esc closes)
* P: freeze game ticks, . (period): run one tick while frozen
* M: skip to the next day (moon phases)
* F11 / Alt+Enter: toggle fullscreen (the window keeps its last size and opens in the middle of the screen)

## Settings
Player options live in the `Settings` autoload and are saved to `user://settings.cfg`.
An option is described once as a `Setting`; menus build the widget from it:

```gdscript
# scripts/settings/settings.gd, _register_all()
define("video", Setting.toggle("clouds", "Clouds", true))
define("video", Setting.range_of("render_scale", "Render Scale", 50, 100, 100, 5))
```

A new setting in an existing category appears in its menu automatically; apply it in
`Settings._apply_global` (window-level) or `SettingsApplier._apply` (scene nodes).

## Video settings and performance
Options → Video Settings is laid out like the classic game, with Details, Quality, Performance and
Shaders sections and presets: **Low** for weak computers (fast graphics, short render distance, 75%
render scale, Classic shaders), **Medium**, **High** for powerful ones (far render distance, Dynamic
Lighting). Modern optimizations: cave culling (chunks you can't see are not drawn), chunks in front
of the camera built first, lower FPS in the background, compressed vertex data, worker-thread
generation / lighting / meshing.

## Languages
Options → Language... switches between English and Russian. Texts are written in English;
`assets/lang/<code>.lang` maps each one to its translation (`English text=Перевод`). Labels and
buttons translate themselves; texts built in code go through `Lang.t()`. Add a language with a new
.lang file and a line in `Lang.LANGUAGES` (`scripts/core/lang.gd`).

## Shader packs
Options → Shaders... chooses the lighting: **Classic** (like the original game, the default) or
**Dynamic Lighting** (real-time sun, moon and shadows). New Pack copies the selected pack into your
own (`user://shaderpacks/<name>.cfg`), whose options (sliders, toggles) you can change. A new option
is one `Setting` in `ShaderPack._definitions()` plus applying it in `BlockMaterials.apply_pack()` (block
shaders) or `ShaderPackApplier` (light, environment).

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
* `scenes/title.tscn` - title screen (panorama, logo, world selection and creation)
* `scenes/main.tscn` - game scene (sky, sun, voxel world, player, HUD); `scripts/game.gd` saves and shows the loading screen
* `scripts/save/world_save.gd` - saved worlds: level.cfg (world, time, rules, player) and changed columns
* `scripts/ui/title/` - title screen and its live world panorama
* `scripts/ui/loading_screen.gd` - loading screen with the island that builds itself as the world loads
* `assets/textures/terrain.png` - block texture atlas (16×16 tiles)
* `assets/textures/sky/` - sun and moon textures (32×32, 8×8 disc with a halo)
* `shaders/` - block shaders (opaque, cutout, translucent with animated water, icon, held block, cracks), sky, clouds, screen overlay
* `scripts/voxel/blocks.gd` - block registry: all block types and their atlas tiles (with facings, flowing water levels, bed halves)
* `scripts/items/` - item registry (tools, ingots, food, buckets, the bed) and the 3D shapes of flat items in hand
* `scripts/player/crafting.gd`, `scripts/player/smelting.gd` - crafting and furnace recipes
* `scripts/entities/item_entities.gd`, `scripts/entities/block_particles.gd` - dropped items and particles
* `scripts/voxel/behaviors/` - block behaviors: flowing water and lava, falling sand, grass, plants, leaf decay
* `scripts/voxel/block_type.gd` - block type description (faces, overlay, tint, render layer)
* `scripts/voxel/block_materials.gd` - atlas → Texture2DArray, one material per render layer
* `scripts/voxel/chunk_data.gd` - block storage of a 16×16×16 chunk
* `scripts/voxel/chunk_mesher.gd` - chunk meshing on a padded volume (neighbor borders): face culling, voxel AO and smooth sky light across chunks
* `scripts/voxel/sky_light.gd` - sky light (0..15) for a column, computed from the 3x3 columns around it
* `scripts/worldgen/world_generator.gd` - base of column generators (16 x 128 x 16)
* `scripts/worldgen/beta_generator.gd` - Beta 1.7.3 style terrain, biomes, caves, ores, trees
* `scripts/core/tick_loop.gd` - autoload: fixed-rate game tick loop (20 TPS), phases, freeze/step
* `scripts/core/game_input.gd` - blocks gameplay input while typing
* `scripts/commands/` - command system: dispatcher, nodes, argument types, game rules, built-in commands
* `scripts/player/player.gd` - the player: classic movement physics (20 steps/s, box collision), camera, game mode
* `scripts/player/inventory.gd` - 36-slot inventory (hotbar + main), stacks of 64
* `scripts/player/food_stats.gd` - hunger: food, saturation, exhaustion, healing and starvation
* `scripts/ui/status_bars.gd`, `scripts/ui/death_screen.gd` - hearts and food, the death screen
* `scripts/player/crafting.gd` - shaped crafting recipes
* `scripts/player/block_interaction.gd` - breaking (survival progress and cracks), placing, picking blocks
* `scripts/ui/inventory/` - inventory windows (survival / creative) and the item slot widget
* `scripts/ui/block_icons.gd` - block icons rendered by the GPU (orthographic view of the block mesh)
* `scripts/player/held_item.gd` - the block in hand (swing and equip animations)
* `scripts/render/atmosphere.gd` - fog colored like the sky, underwater fog and tint, vignette, cloud color
* `scripts/render/clouds.gd` - 3D clouds driven by the shader (no per-frame CPU work)
* `scripts/render/shader_packs.gd`, `shader_pack.gd`, `shader_pack_applier.gd` - shader packs (Classic, Dynamic Lighting, your own)
* `scripts/render/water_animation.gd` - animated still / flowing water textures like the classic Beta game
* `scripts/ui/chat.gd` - chat with command suggestions and history
* `scripts/ui/ui_theme.gd` - shared UI look (pixel font, GUI widget textures)
* `scripts/ui/menu/` - in-game menu: menu stack, screen base, screens
* `scripts/settings/` - settings registry and saving, key bindings, scene applier
* `scripts/voxel/world_clock.gd` - world time in ticks (game time, day time)
* `scripts/voxel/voxel_world.gd` - endless world: chunk streaming around the player, world ticks (scheduled, random, block updates), async generation and meshing
* `scripts/voxel/behaviors/` - block tick behaviors (grass, falling blocks)
* `scripts/entities/falling_blocks.gd` - falling sand/gravel entities: tick physics on packed arrays, MultiMesh rendering
* `scripts/voxel/random_blocks_generator.gd` - debug generator: every block type scattered randomly
* `scripts/day_night_cycle.gd` - the classic sun and moon (celestial angle, 8 moon phases), sky brightness and night darkness of sky light; drives the sky
* `scripts/free_camera.gd` - free camera
* `scripts/ui/debug_screen.gd` - F3 debug screen
* `scripts/ui/hotbar.gd`, `scripts/ui/block_icons.gd` - hotbar and isometric block icons
* `scripts/ui/crosshair.gd` - crosshair
* `scripts/player/block_interaction.gd` - breaking, placing and picking blocks, target outline
* `scripts/window_controls.gd` - autoload: minimum window size, fullscreen and VSync toggles

## Adding a block
Append a `register()` call at the end of `Blocks._register_all()` in `scripts/voxel/blocks.gd`:

```gdscript
register(BlockType.cube("bricks", 7))                       # same tile on every face
register(BlockType.column("pumpkin", 102, 118))             # top / sides (/ bottom)
register(BlockType.cube("ice", 67).set_layer(Layer.CUTOUT)) # transparent pixels cut out
```

Tile number = `row * 16 + column` in the atlas. Always append at the end: ids follow registration order.
