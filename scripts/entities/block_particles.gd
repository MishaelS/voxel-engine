class_name BlockParticles
extends Node3D
## Particles like the classic game, all in one MultiMesh (particle.gdshader):
## - breaking a block bursts it into 4 x 4 x 4 bits of its texture;
## - hitting a block while breaking it chips small bits off the face;
## - eating sends crumbs of the food from the mouth;
## - a lit furnace gives off smoke and flames;
## - smoke, flames, lava sparks, hearts, notes, splashes, explosions and the
##   fight (hurt hearts, critical hits, the sword's sweep) are pictures of
##   the particle atlas (textures/extra/particles-atlas.png, the game's), animated
##   frame by frame like the game's (smoke shrinks as it rises, the sweep
##   swings);
## - a creature gone and explosions: poofs of white-gray smoke and the big
##   explosion clouds, from textures/extra/explosion.png (our own pixel art,
##   tools/make_explosion_texture.py), put into the atlas at EXPLOSION_AT.
## - lava bubbles (embers, pops), rain and snow hiss into steam on lava, fire
##   and torches, items burn up in lava and fire, rain and snow splash on
##   water and the ground;
## - near the bedrock, dark specks float in the air (the void's dust).
## Bits fall with gravity (0.04 blocks per tick per tick, drag 0.98), stop
## on blocks and live 4..40 ticks; simulated in game ticks (TickLoop) and
## interpolated between them for drawing. Lit particles take the light where
## they are every tick, like the classic game (inside a block, the brightest
## light next to it: the bits of a block being broken are not black).
##
## The simulation and drawing run in native code (NativeParticles,
## native/src/native_particles.cpp): one call a tick asks the world for the
## few cells the particles touch, one call a frame fills the MultiMesh. The
## GDScript below does the same without the native library.

const MAX_PARTICLES := 4000
const GRAVITY := 0.04

enum Kind { TILE, ITEM, PLAIN }

const ATLAS_PATH := "res://assets/textures/extra/particles-atlas.png"
const ATLAS_SIZE := Vector2(512, 256)
const EXPLOSION_PATH := "res://assets/textures/extra/explosion.png"
## Where explosion.png goes in the atlas (an empty place): 4 x 4 explosion
## frames of 16 x 16, under them 8 poof frames of 8 x 8 (small to big).
const EXPLOSION_AT := Vector2i(320, 0)
## Picture size codes (particle.gdshader): 8 x 8, 16 x 16, 32 x 16 pixels.
enum Picture { SMALL, BIG, WIDE }
## Single pictures of the atlas: [x, y, size code].
const FLAME := [272, 48, Picture.SMALL]
const LAVA := [272, 216, Picture.SMALL]
const HEART := [272, 200, Picture.SMALL]
const NOTE := [272, 232, Picture.SMALL]
## The smallest smoke puff: the void's dust.
const SPECK := [272, 128, Picture.SMALL]
const DAMAGE := [192, 208, Picture.SMALL]
const CRIT := [184, 208, Picture.SMALL]
## Animations: frames [x, y] of one size code, played over the particle's
## life. ANIMS order: GENERIC (smoke, big to small), SWEEP, BIG_SMOKE (big to
## small), SPLASH, POOF (shaded smoke, big to small), EXPLOSION (the big
## cloud, bursting and breaking up).
enum Anim { GENERIC, SWEEP, BIG_SMOKE, SPLASH, POOF, EXPLOSION }
const ANIMS := [
	[Picture.SMALL, [[272, 184], [272, 176], [272, 168], [272, 160], [272, 152], [272, 144], [272, 136], [272, 128]]],
	[Picture.WIDE, [[160, 168], [192, 168], [224, 168], [0, 200], [32, 200], [64, 200], [96, 200], [128, 200]]],
	[Picture.BIG, [[0, 224], [16, 224], [32, 224], [48, 224], [64, 224], [80, 224], [96, 224], [112, 224]]],
	[Picture.SMALL, [[288, 128], [288, 136], [288, 144], [288, 152]]],
	[Picture.SMALL, [[376, 64], [368, 64], [360, 64], [352, 64], [344, 64], [336, 64], [328, 64], [320, 64]]],
	[Picture.BIG, [[320, 0], [336, 0], [352, 0], [368, 0], [320, 16], [336, 16], [352, 16], [368, 16],
		[320, 32], [336, 32], [352, 32], [368, 32], [320, 48], [336, 48], [352, 48], [368, 48]]],
]

## Where Beta 1.7.3's particles.png has the pictures the atlas has (a
## texture pack's particles.png draws them): atlas [x, y] -> Beta cell
## (8 x 8 pixels, index = row * 16 + column, like the game's
## particleTextureIndex). Smoke: Beta's cells 7..0, big to small.
const BETA_CELLS := [
	[[272, 184], 7], [[272, 176], 6], [[272, 168], 5], [[272, 160], 4],
	[[272, 152], 3], [[272, 144], 2], [[272, 136], 1], [[272, 128], 0],
	[[288, 128], 19], [[288, 136], 20], [[288, 144], 21], [[288, 152], 22], # rain splashes
	[[272, 48], 48], [[272, 216], 49], [[272, 232], 64], [[272, 200], 80], # flame, lava, note, heart
	[[376, 64], 7], [[368, 64], 6], [[360, 64], 5], [[352, 64], 4], # poof (Beta's "explode": the smoke cells)
	[[344, 64], 3], [[336, 64], 2], [[328, 64], 1], [[320, 64], 0],
]


## The atlas: the game's with explosion.png at EXPLOSION_AT, and a texture
## pack's particles.png pictures put in at their places (BETA_CELLS); the
## game's own (critical hits, the sweep, big smoke, explosions) stay.
static func atlas_texture() -> Texture2D:
	var atlas := TexturePacks.load_image(ATLAS_PATH)
	var sheet := TexturePacks.load_image(EXPLOSION_PATH)
	atlas.blit_rect(sheet, Rect2i(Vector2i.ZERO, sheet.get_size()), EXPLOSION_AT)
	var pack := TexturePacks.pack_image("particles.png")
	if pack == null:
		return ImageTexture.create_from_image(atlas)
	for entry: Array in BETA_CELLS:
		var cell: int = entry[1]
		var at := Vector2i(entry[0][0], entry[0][1])
		atlas.fill_rect(Rect2i(at, Vector2i(8, 8)), Color(0, 0, 0, 0))
		atlas.blit_rect(pack, Rect2i((cell % 16) * 8, (cell / 16) * 8, 8, 8), at)
	return ImageTexture.create_from_image(atlas)


var world: VoxelWorld

var _positions := PackedVector3Array()
var _previous := PackedVector3Array()
var _velocities := PackedVector3Array()
var _ages := PackedInt32Array()
var _lives := PackedInt32Array()
var _gravity := PackedFloat32Array()
var _custom := PackedColorArray()   # layer, u, v, size
var _colors := PackedColorArray()
var _fade := PackedByteArray()      # 1 = fades out (smoke)
var _anim := PackedInt32Array()     # index into ANIMS, -1 = a still picture
var _min_light := PackedFloat32Array() # < 0: drawn at full color; else lit, never darker
var _light := PackedFloat32Array()  # brightness where it is (lit particles)
var _native: Object
var _multimesh: MultiMesh
var _material: ShaderMaterial
var _rng := RandomNumberGenerator.new()
## Explosion clouds still going off: [center, power, ticks left].
var _bursts: Array[Array] = []


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/particle.gdshader")
	_material.set_shader_parameter("tiles", BlockMaterials.tiles())
	_material.set_shader_parameter("items", Items.icons_texture())
	_material.set_shader_parameter("atlas", atlas_texture())
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = _multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	add_child(instance)
	if ClassDB.class_exists("NativeParticles"):
		_native = ClassDB.instantiate("NativeParticles")
		var frames := []
		for anim: Array in ANIMS:
			var list := PackedVector2Array()
			for frame: Array in anim[1]:
				list.append(Vector2(frame[0] / ATLAS_SIZE.x, frame[1] / ATLAS_SIZE.y))
			frames.append(list)
		_native.call("setup", Blocks.collision_table, frames, MAX_PARTICLES)
	TickLoop.add_listener(_tick, TickLoop.Phase.ENTITIES)


func _exit_tree() -> void:
	TickLoop.remove_listener(_tick)


func count() -> int:
	return _native.call("count") if _native else _ages.size()


# --- Effects ---------------------------------------------------------------------

## A block broken at `pos`: 4 x 4 x 4 bits flying out from its middle.
func break_block(pos: Vector3i, block_id: int) -> void:
	var tile := _tile_of(block_id)
	var tint := _tint_of(block_id, pos)
	for x in 4:
		for y in 4:
			for z in 4:
				var offset := (Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5)) / 4.0
				var start := Vector3(pos) + offset
				var velocity := _burst(offset - Vector3(0.5, 0.5, 0.5))
				_add_tile(start, velocity, tile, tint, 1.0)


## A chip off the face of a block being broken (one per tick).
func hit_block(pos: Vector3i, normal: Vector3i, block_id: int) -> void:
	var start := Vector3(pos) + Vector3(_rng.randf_range(0.1, 0.9), _rng.randf_range(0.1, 0.9), _rng.randf_range(0.1, 0.9))
	for axis in 3:
		if normal[axis] != 0:
			start[axis] = pos[axis] + (1.1 if normal[axis] > 0 else -0.1)
	if normal.y > 0:
		start.y = pos.y + Blocks.height_table[block_id] + 0.1
	var velocity := _burst(Vector3.ZERO) * 0.2
	velocity.y = (velocity.y - 0.1) * 0.2 + 0.02
	_add_tile(start, velocity, _tile_of(block_id), _tint_of(block_id, pos), 0.6)


## Crumbs of an item (eating), from `origin` along `direction`.
func item_crumbs(item_id: int, origin: Vector3, direction: Vector3, amount: int = 5, scale: float = 1.0) -> void:
	for i in amount:
		var velocity := direction * 0.1 + Vector3(_rng.randf_range(-0.05, 0.05), _rng.randf_range(0.05, 0.1), _rng.randf_range(-0.05, 0.05))
		if Items.is_block(item_id):
			_add_tile(origin, velocity, _tile_of(item_id), _tint_of(item_id), scale)
		else:
			var item := Items.get_type(item_id)
			var u := ((item.icon % 16) + _rng.randi_range(0, 3) / 4.0) / 16.0
			var v := ((item.icon / 16) + _rng.randi_range(0, 3) / 4.0) / 16.0
			_add(origin, velocity, Color(-1, u, v, _size(scale)), Color.WHITE, _life(), 1.0, false, -1, 0.0)


## A puff of smoke (lava hardening, items burning, a creature gone): the
## game's smoke, shrinking as it rises.
func smoke(point: Vector3, amount: int = 8) -> void:
	for i in amount:
		var start := point + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.2, 0.2), _rng.randf_range(-0.4, 0.4))
		var gray := _rng.randf_range(0.3, 0.6)
		_add_anim(start, Vector3(0, _rng.randf_range(0.02, 0.05), 0), Anim.GENERIC, _rng.randf_range(0.15, 0.3),
			Color(gray, gray, gray), _rng.randi_range(15, 30), -0.01, 0.0)


## A poof (a creature gone): 20 puffs of white-gray smoke over its box,
## drifting up and shrinking, like the game's "explode" particle.
func poof(box: AABB, amount: int = 20) -> void:
	for i in amount:
		var start := box.position + Vector3(_rng.randf() * 2.0 - 0.5, _rng.randf(), _rng.randf() * 2.0 - 0.5) * box.size
		var velocity := Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * 0.02
		_puff(start, velocity)


## One of the game's "explode" puffs: gray 0.7..1, 0.2..1.4 blocks, lives
## 18..82 ticks, slows down and drifts up.
func _puff(start: Vector3, velocity: Vector3) -> void:
	var gray := _rng.randf() * 0.3 + 0.7
	var size := 0.2 * (_rng.randf() * _rng.randf() * 6.0 + 1.0)
	var life := int(16.0 / (_rng.randf() * 0.8 + 0.2)) + 2
	velocity += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.01
	_add_anim(start, velocity, Anim.POOF, size, Color(gray, gray, gray), life, -0.02, 0.1)


## Steam: rain or snow hissing on lava, fire or a torch: pale puffs rising
## fast and fading.
func steam(point: Vector3, amount: int = 3) -> void:
	for i in amount:
		var start := point + Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf_range(0.0, 0.15), _rng.randf_range(-0.25, 0.25))
		var gray := _rng.randf_range(0.75, 0.95)
		_add_anim(start, Vector3(_rng.randf_range(-0.01, 0.01), _rng.randf_range(0.05, 0.09), _rng.randf_range(-0.01, 0.01)),
			Anim.GENERIC, _rng.randf_range(0.12, 0.22), Color(gray, gray, gray, 0.85), _rng.randi_range(8, 16), -0.02, 0.15, true)


## Embers: tiny orange specks jumping out of bubbling lava (or a burning
## item) and falling back.
func embers(point: Vector3, amount: int = 1) -> void:
	for i in amount:
		var velocity := Vector3(_rng.randf_range(-0.03, 0.03), _rng.randf_range(0.04, 0.12), _rng.randf_range(-0.03, 0.03))
		_add_picture(point, velocity, LAVA, _rng.randf_range(0.03, 0.06), Color.WHITE, _rng.randi_range(8, 18), 0.5)


## An item burning up in lava or fire: smoke, a flame and (in lava) embers.
func burn(point: Vector3, in_lava: bool) -> void:
	smoke(point + Vector3(0, 0.2, 0), 5)
	for i in 2:
		var start := point + Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf_range(0.0, 0.25), _rng.randf_range(-0.15, 0.15))
		_add_picture(start, Vector3(0, 0.01, 0), FLAME, 0.12, Color.WHITE, _rng.randi_range(6, 12), 0.0)
	if in_lava:
		embers(point + Vector3(0, 0.1, 0), 4)


## An explosion: big bright clouds going off around the middle for 8
## ticks (the game's "hugeexplosion"), white puffs and dark smoke thrown
## out of the blast (Beta's "explode" and "smoke").
func explosion(center: Vector3, power: float) -> void:
	_bursts.append([center, power, 8])
	_burst_clouds(_bursts[-1])
	for i in int(power * 40):
		var point := center + _in_ball() * power
		var away := point - center
		var distance := maxf(away.length(), 0.01)
		var speed := minf(0.5 / (distance / power + 0.1) * (_rng.randf() * _rng.randf() + 0.3), 0.5) * 0.2
		var velocity := away / distance * speed
		_puff((point + center) / 2.0, velocity)
		var gray := _rng.randf() * 0.3
		_add_anim(point, velocity * 0.5, Anim.GENERIC, _size(0.75), Color(gray, gray, gray),
			int(8.0 / (_rng.randf() * 0.8 + 0.2)), -0.02, 0.0)


## One tick of an explosion's clouds: big unlit puffs at random around the
## middle, smaller as it ends; false when it is over.
func _burst_clouds(burst: Array) -> bool:
	var center: Vector3 = burst[0]
	var power: float = burst[1]
	var left: int = burst[2]
	for i in 6:
		var offset := Vector3(_rng.randf() - _rng.randf(), _rng.randf() - _rng.randf(), _rng.randf() - _rng.randf()) * power
		var gray := _rng.randf() * 0.6 + 0.4
		var size := 4.0 * (1.0 - (8 - left) / 8.0 * 0.5) * clampf(power / 4.0, 0.5, 1.0)
		_add_anim(center + offset, Vector3.ZERO, Anim.EXPLOSION, size, Color(gray, gray, gray),
			6 + _rng.randi_range(0, 3), 0.0)
	burst[2] = left - 1
	return left > 1


## A random point in a ball of radius 1.
func _in_ball() -> Vector3:
	while true:
		var point := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		if point.length_squared() <= 1.0:
			return point
	return Vector3.ZERO


## Redstone dust glowing (wire, torches, lit ore): a red speck, brighter
## with more power, like the game's "reddust".
func redstone(point: Vector3, power: int) -> void:
	var f := power / 15.0
	var color := Color(f * 0.6 + 0.4, maxf(f * f * 0.7 - 0.5, 0.0), maxf(f * f * 0.6 - 0.7, 0.0), 1.0)
	_add_anim(point, Vector3(0, 0.005, 0), Anim.GENERIC, 0.1, color, _rng.randi_range(10, 20), 0.0)


## An air bubble rising (drowning).
func bubble(point: Vector3) -> void:
	_add(point, Vector3(0, 0.05, 0), Color(-2, 0, 0, 0.06), Color(0.75, 0.85, 1.0, 0.9), _rng.randi_range(8, 20), -0.002, false)


## Rain hitting the ground: the game's splash, a droplet thrown up; on water
## a smaller splash with a ring of droplets.
func rain_splash(point: Vector3, on_water: bool) -> void:
	var velocity := Vector3(_rng.randf_range(-0.02, 0.02), _rng.randf_range(0.03, 0.06), _rng.randf_range(-0.02, 0.02))
	if on_water:
		_add_anim(point, velocity * 0.3, Anim.SPLASH, 0.08, Color(0.75, 0.85, 1.0), _rng.randi_range(4, 7), 0.02, 0.0)
		for i in 2:
			var out := Vector3(_rng.randf_range(-0.03, 0.03), _rng.randf_range(0.02, 0.05), _rng.randf_range(-0.03, 0.03))
			_add(point, out, Color(-2, 0, 0, 0.03), Color(0.7, 0.8, 1.0, 0.8), _rng.randi_range(3, 6), 0.04, false, -1, 0.0)
		return
	_add_anim(point, velocity, Anim.SPLASH, 0.1, Color(0.8, 0.88, 1.0), _rng.randi_range(4, 8), 0.04, 0.0)


## Snow landing on water: the flake melts in a few white specks sinking in.
func snow_melt(point: Vector3) -> void:
	for i in 2:
		var velocity := Vector3(_rng.randf_range(-0.01, 0.01), _rng.randf_range(-0.01, 0.01), _rng.randf_range(-0.01, 0.01))
		_add(point, velocity, Color(-2, 0, 0, _rng.randf_range(0.03, 0.05)), Color(0.95, 0.97, 1.0, 0.9),
			_rng.randi_range(6, 12), 0.05, true, -1, 0.0)


## A splash on water (a fish biting): droplets thrown up.
func splash(point: Vector3) -> void:
	for i in 12:
		var velocity := Vector3(_rng.randf_range(-0.08, 0.08), _rng.randf_range(0.08, 0.2), _rng.randf_range(-0.08, 0.08))
		_add_anim(point, velocity, Anim.SPLASH, 0.15, Color.WHITE, _rng.randi_range(8, 16), 0.04, 0.0)


## Dust of the void near the bedrock: a dark speck drifting slowly (the
## game's "depthsuspend").
func void_speck(point: Vector3) -> void:
	var gray := _rng.randf() * 0.1 + 0.2
	var velocity := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.004
	var life := int(20.0 / (_rng.randf() * 0.8 + 0.2))
	_add_picture(point, velocity, SPECK, _size(_rng.randf() * 0.6 + 0.5) * 0.5, Color(gray, gray, gray), life, 0.0)


## A note floating up from a note block, colored by its pitch like the game.
func note(point: Vector3, pitch: int) -> void:
	var f := pitch / 24.0
	var color := Color(maxf(sin(f * TAU) * 0.65 + 0.35, 0.0), maxf(sin((f + 1.0 / 3.0) * TAU) * 0.65 + 0.35, 0.0),
		maxf(sin((f + 2.0 / 3.0) * TAU) * 0.65 + 0.35, 0.0), 1.0)
	_add_picture(point, Vector3(0, 0.02, 0), NOTE, 0.25, color, 20, 0.0)


## Hearts rising (a wolf tamed).
func hearts(point: Vector3) -> void:
	for i in 7:
		var start := point + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(0, 0.5), _rng.randf_range(-0.5, 0.5))
		_add_picture(start, Vector3(0, 0.02, 0), HEART, 0.2, Color.WHITE, 25, 0.0)


## A torch's tip: a wisp of smoke and a small flame.
func torch(tip: Vector3) -> void:
	var gray := _rng.randf_range(0.15, 0.3)
	_add_anim(tip, Vector3(0, 0.01, 0), Anim.GENERIC, 0.12, Color(gray, gray, gray), _rng.randi_range(8, 16), -0.02, 0.0)
	_add_picture(tip, Vector3.ZERO, FLAME, 0.1, Color.WHITE, _rng.randi_range(5, 10), 0.0)


## A lava pop: an orange spark jumps up and falls back.
func lava_pop(point: Vector3) -> void:
	var velocity := Vector3(_rng.randf_range(-0.04, 0.04), _rng.randf_range(0.15, 0.3), _rng.randf_range(-0.04, 0.04))
	_add_picture(point, velocity, LAVA, _rng.randf_range(0.1, 0.2), Color.WHITE, _rng.randi_range(16, 30), 0.75)


## Smoke and sometimes a flame in front of a lit furnace.
func furnace(pos: Vector3i, facing: int) -> void:
	var front := Vector3(Blocks.FACING_DIRECTIONS[facing])
	var side := Vector3(-front.z, 0, front.x)
	var start := Vector3(pos) + Vector3(0.5, 0.0, 0.5) + front * 0.52 \
		+ side * _rng.randf_range(-0.3, 0.3) + Vector3(0, _rng.randf_range(0.1, 0.45), 0)
	var gray := _rng.randf_range(0.15, 0.3)
	_add_anim(start, Vector3(0, 0.01, 0), Anim.GENERIC, 0.15, Color(gray, gray, gray), _rng.randi_range(10, 20), -0.02, 0.0)
	if _rng.randf() < 0.5:
		_add_picture(start, Vector3.ZERO, FLAME, 0.12, Color.WHITE, _rng.randi_range(8, 14), 0.0)


## Hurt hearts: dark hearts spilling out of a creature that was hit (one
## per 2 points of damage), like the modern game.
func damage(point: Vector3, amount: int) -> void:
	for i in clampi(amount / 2, 1, 10):
		var velocity := Vector3(_rng.randf_range(-0.1, 0.1), _rng.randf_range(0.1, 0.2), _rng.randf_range(-0.1, 0.1))
		_add_picture(point, velocity, DAMAGE, 0.15, Color.WHITE, _rng.randi_range(14, 22), 0.6)


## A critical hit: white stars bursting out of the creature.
func crit(point: Vector3) -> void:
	for i in 16:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		var velocity := dir.normalized() * _rng.randf_range(0.15, 0.35) + Vector3(0, 0.1, 0)
		_add_picture(point + dir * 0.3, velocity, CRIT, _rng.randf_range(0.08, 0.14), Color(0.9, 0.85, 0.75), _rng.randi_range(8, 16), 0.5)


## A sword's sweep in front of the player: the swinging arc.
func sweep(point: Vector3) -> void:
	_add_anim(point, Vector3.ZERO, Anim.SWEEP, 0.55, Color.WHITE, 8, 0.0, 0.4)


# --- Simulation ----------------------------------------------------------------------

func _tick(_tick_index: int) -> void:
	var b := 0
	while b < _bursts.size():
		if _burst_clouds(_bursts[b]):
			b += 1
		else:
			_bursts.remove_at(b)
	if _native:
		var cells: PackedInt32Array = _native.call("cells_needed")
		var looked_up := world.cells_for_particles(cells) if world else [PackedInt32Array(), PackedFloat32Array()]
		_native.call("tick", looked_up[0], looked_up[1])
		return
	var i := 0
	while i < _ages.size():
		_ages[i] += 1
		if _ages[i] >= _lives[i]:
			_remove(i)
			continue
		if _anim[i] >= 0:
			# The next frame of its animation.
			var frames: Array = ANIMS[_anim[i]][1]
			var frame: Array = frames[mini(_ages[i] * frames.size() / _lives[i], frames.size() - 1)]
			var custom := _custom[i]
			custom.g = frame[0] / ATLAS_SIZE.x
			custom.b = frame[1] / ATLAS_SIZE.y
			_custom[i] = custom
		var position := _positions[i]
		_previous[i] = position
		var velocity := _velocities[i]
		velocity.y -= GRAVITY * _gravity[i]
		var on_ground := false
		if world and _gravity[i] > 0.0:
			# Stop on blocks, axis by axis.
			for axis in [1, 0, 2]:
				var next := position
				next[axis] += velocity[axis]
				if _solid(next):
					if axis == 1 and velocity.y < 0.0:
						on_ground = true
					velocity[axis] = 0.0
				else:
					position = next
		else:
			position += velocity
		velocity *= 0.98
		if on_ground:
			velocity.x *= 0.7
			velocity.z *= 0.7
		_positions[i] = position
		_velocities[i] = velocity
		if _min_light[i] >= 0.0:
			_light[i] = _brightness(position)
		i += 1


func _solid(point: Vector3) -> bool:
	var cell := Vector3i(point.floor())
	var id := world.get_block(cell)
	return Blocks.blocks_point(id, point - Vector3(cell))


func _process(_delta: float) -> void:
	if _native:
		_native.call("draw", _multimesh, TickLoop.alpha)
		return
	var total := _ages.size()
	if _multimesh.instance_count != total:
		_multimesh.instance_count = total
	var alpha := TickLoop.alpha
	for i in total:
		var position := _previous[i].lerp(_positions[i], alpha)
		_multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, position))
		var color := _colors[i]
		if _min_light[i] >= 0.0:
			var light := maxf(_light[i], _min_light[i])
			color = Color(color.r * light, color.g * light, color.b * light, color.a)
		if _fade[i] == 1:
			color.a *= 1.0 - float(_ages[i]) / _lives[i]
		_multimesh.set_instance_color(i, color)
		_multimesh.set_instance_custom_data(i, _custom[i])


# --- Helpers --------------------------------------------------------------------------

## The classic burst: away from the middle at a random speed, a bit upward.
func _burst(direction: Vector3) -> Vector3:
	var velocity := direction + Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4))
	var speed := (_rng.randf() + _rng.randf() + 1.0) * 0.15
	velocity = velocity.normalized() * speed * 0.4 if velocity.length_squared() > 1e-6 else Vector3.ZERO
	velocity.y += 0.1
	return velocity


## A bit of a block's texture, lit where it is.
func _add_tile(start: Vector3, velocity: Vector3, tile: int, color: Color, scale: float) -> void:
	color.a = 1.0
	var u := _rng.randi_range(0, 3) / 4.0
	var v := _rng.randi_range(0, 3) / 4.0
	_add(start, velocity, Color(tile, u, v, _size(scale)), color, _life(), 1.0, false, -1, 0.0)


## A still picture of the particle atlas ([x, y, size code]), drawn at full
## color (flames, hearts...).
func _add_picture(start: Vector3, velocity: Vector3, picture: Array, size: float, color: Color, life: int, gravity: float) -> void:
	_add(start, velocity, Color(-10 - picture[2], picture[0] / ATLAS_SIZE.x, picture[1] / ATLAS_SIZE.y, size),
		color, life, gravity, false)


## An animated picture (ANIMS), its frames played over its life; `min_light`
## >= 0: lit where it is (smoke), never darker than that.
func _add_anim(start: Vector3, velocity: Vector3, anim: int, size: float, color: Color, life: int, gravity: float,
		min_light: float = -1.0, fade: bool = false) -> void:
	var first: Array = ANIMS[anim][1][0]
	_add(start, velocity, Color(-10 - ANIMS[anim][0], first[0] / ATLAS_SIZE.x, first[1] / ATLAS_SIZE.y, size),
		color, life, gravity, fade, anim, min_light)


## Adds a particle; false when there are too many already. `anim`: index
## into ANIMS or -1; `min_light`: < 0 drawn at full color, else lit.
func _add(start: Vector3, velocity: Vector3, custom: Color, color: Color, life: int, gravity: float, fade: bool,
		anim: int = -1, min_light: float = -1.0) -> bool:
	var light := _brightness(start) if min_light >= 0.0 else 1.0
	if _native:
		return _native.call("add", start, velocity, custom, color, life, gravity, fade, anim, min_light, light)
	if _ages.size() >= MAX_PARTICLES:
		return false
	_min_light.append(min_light)
	_light.append(light)
	_anim.append(anim)
	_positions.append(start)
	_previous.append(start)
	_velocities.append(velocity)
	_ages.append(0)
	_lives.append(life)
	_gravity.append(gravity)
	_custom.append(custom)
	_colors.append(color)
	_fade.append(1 if fade else 0)
	return true


func _size(scale: float) -> float:
	return 0.1 * (_rng.randf() * 0.5 + 0.5) * 2.0 * scale


func _life() -> int:
	return int(4.0 / (_rng.randf() * 0.9 + 0.1))


func _remove(index: int) -> void:
	var last := _ages.size() - 1
	_positions[index] = _positions[last]
	_previous[index] = _previous[last]
	_velocities[index] = _velocities[last]
	_ages[index] = _ages[last]
	_lives[index] = _lives[last]
	_gravity[index] = _gravity[last]
	_custom[index] = _custom[last]
	_colors[index] = _colors[last]
	_fade[index] = _fade[last]
	_anim[index] = _anim[last]
	_min_light[index] = _min_light[last]
	_light[index] = _light[last]
	_anim.resize(last)
	_min_light.resize(last)
	_light.resize(last)
	_positions.resize(last)
	_previous.resize(last)
	_velocities.resize(last)
	_ages.resize(last)
	_lives.resize(last)
	_gravity.resize(last)
	_custom.resize(last)
	_colors.resize(last)
	_fade.resize(last)


## The texture bits come from the block's bottom face, like the classic game
## (grass gives dirt bits, logs their rings).
static func _tile_of(block_id: int) -> int:
	return Blocks.face_tiles[block_id * 6 + 1]


## The bits' color: the biome's grass or foliage color where the block is
## for blocks tinted by it all over (tall grass, ferns, leaves: gray in
## terrain.png, like Beta's), the block's own tint otherwise; grass blocks
## give plain dirt bits (their bottom).
func _tint_of(block_id: int, pos: Variant = null) -> Color:
	var block := Blocks.get_type(block_id)
	var kind := Blocks.biome_tint_table[block_id]
	if kind > 0 and block.overlays[2] < 0:
		if pos is Vector3i and world:
			return world.biome_color(pos, kind)
		return (BetaGenerator.GRASS_DRY.lerp(BetaGenerator.GRASS_WET, 0.5) if kind == 1 else BetaGenerator.FOLIAGE_DRY.lerp(BetaGenerator.FOLIAGE_WET, 0.5)).srgb_to_linear()
	return block.tint.srgb_to_linear() if block.overlays[2] < 0 else Color.WHITE


## Brightness of the light at a point, like the blocks (night darkness too;
## inside a block the brightest light next to it).
func _brightness(point: Vector3) -> float:
	return world.brightness_at(point) if world else 1.0