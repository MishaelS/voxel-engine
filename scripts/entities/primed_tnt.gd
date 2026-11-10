class_name PrimedTnt
extends Entity
## Lit TNT like the classic game (EntityTNTPrimed): the block hops up a
## little, falls and slides like any block, flashes white while its fuse
## burns (80 ticks, 4 seconds; 10..30 when another explosion lit it),
## smokes, then explodes with power 4. TNT is lit by flint and steel, by
## fire burning it, by an explosion, and in Beta by hitting it (breaking it
## lights it instead of dropping it).

const FUSE := 80
const POWER := 4.0

var fuse := FUSE
var _mesh: Node3D
var _flash: MeshInstance3D


## Lights the TNT block at `pos` (it becomes a primed TNT entity).
static func light(world: VoxelWorld, pos: Vector3i, short_fuse: bool = false) -> PrimedTnt:
	world.set_block(pos, Blocks.AIR)
	var tnt := PrimedTnt.new()
	if short_fuse:
		tnt.fuse = randi_range(FUSE / 4, FUSE / 4 * 3) / 2
	world.entities.spawn(tnt, Vector3(pos) + Vector3(0.5, 0, 0.5))
	var angle := randf() * TAU
	tnt.velocity = Vector3(-sin(angle) * 0.02, 0.2, -cos(angle) * 0.02)
	Sounds.play("random/fuse", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 1.0, 1.0)
	return tnt


func type_name() -> String:
	return "tnt"


func can_be_hit() -> bool:
	return false


func _ready() -> void:
	half_width = 0.49
	height = 0.98
	gravity = 0.04
	_mesh = Node3D.new()
	add_child(_mesh)
	var block := MeshInstance3D.new()
	block.mesh = FallingBlocks.block_mesh(Blocks.id_of("tnt")) # drawn like the block in the world
	block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.add_child(block)
	# The white flash: a see-through white box over it.
	_flash = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.01
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	white.albedo_color = Color(1, 1, 1, 0.55)
	box.material = white
	_flash.mesh = box
	_flash.position = Vector3(0.5, 0.5, 0.5)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.add_child(_flash)


func tick() -> void:
	_prev = Vector3(_x, _y, _z)
	age += 1
	move(velocity)
	velocity.y -= gravity
	velocity *= 0.98
	if on_ground:
		velocity *= Vector3(0.7, -0.5, 0.7)
	fuse -= 1
	if fuse <= 0:
		removed = true
		Explosion.explode(world, feet() + Vector3(0, 0.5, 0), POWER, self)
		return
	world.particles.smoke(feet() + Vector3(0, 1.1, 0), 1)


func _process(delta: float) -> void:
	super(delta)
	# Swells just before it goes, and flashes white every 8 ticks.
	var scale_factor := 1.0
	if fuse < 10:
		var t := clampf(1.0 - (fuse - TickLoop.alpha) / 10.0, 0.0, 1.0)
		scale_factor = 1.0 + t * t * t * t * 0.3
	_mesh.scale = Vector3.ONE * scale_factor
	_mesh.position = Vector3(-0.5, 0, -0.5) * scale_factor
	_flash.visible = (fuse / 5) % 2 == 0


func save_state() -> Dictionary:
	var state := super()
	state["fuse"] = fuse
	return state


func load_state(saved: Dictionary) -> void:
	super(saved)
	fuse = saved.get("fuse", FUSE)
