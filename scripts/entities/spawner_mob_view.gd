class_name SpawnerMobView
extends Node3D
## The little mob turning inside a mob spawner, like the game's spawner
## renderer: the spawner's mob at 7/16 of its size, tilted 30 degrees,
## spinning around fast (faster as the next spawn nears: 10000 / (delay +
## 200) degrees a tick) while the player is near enough to wake it up.

const SCALE := 0.4375
const LIFT := 0.4
const TILT := -30.0

var world: VoxelWorld
var pos: Vector3i
var mob_type := ""
var _model := {}
var _held: MeshInstance3D
var _yaw := 0.0


static func create(owner: VoxelWorld, at: Vector3i, type: String) -> SpawnerMobView:
	var view := SpawnerMobView.new()
	view.world = owner
	view.pos = at
	view.mob_type = type
	view._yaw = randf() * 36.0
	return view


func _ready() -> void:
	position = Vector3(pos) + Vector3(0.5, 0.0, 0.5)
	_model = MobModels.build(mob_type)
	add_child(_model.root)
	if mob_type == "skeleton":
		_held = MobModels.held_item(mob_type, Items.id_of("bow"))
		(_model.parts.right_arm as Node3D).add_child(_held)
	# Arms ahead like the walking undead.
	if mob_type == "zombie" or mob_type == "skeleton":
		for arm: String in ["right_arm", "left_arm"]:
			(_model.parts[arm] as Node3D).rotation.x = -PI / 2.0
	_update_brightness()


func _process(delta: float) -> void:
	var spawner := world.entities.spawner if world and world.entities else null
	var player := world.player as Player if world else null
	if spawner and player and player.global_position.distance_to(Vector3(pos) + Vector3(0.5, 0.5, 0.5)) <= DungeonBehavior.RANGE:
		var delay: int = spawner.block_spawners.get(pos, 200)
		_yaw = fmod(_yaw + 1000.0 / (delay + 200.0) * delta * 20.0, 36.0)
	var size := float(MobModels.model(mob_type).get("scale", 1.0)) / 16.0 * SCALE
	var turn := Basis(Vector3.UP, deg_to_rad(_yaw * 10.0)) * Basis(Vector3.RIGHT, deg_to_rad(TILT))
	_model.root.transform = Transform3D(Basis.IDENTITY, Vector3(0, LIFT, 0)) \
		* Transform3D(turn, Vector3.ZERO) * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), Vector3(0, -LIFT, 0))
	if Engine.get_process_frames() % 10 == 0:
		_update_brightness()


func _update_brightness() -> void:
	var brightness := world.brightness_at(Vector3(pos) + Vector3(0.5, 0.5, 0.5)) if world else 1.0
	for mesh: MeshInstance3D in _model.meshes:
		mesh.set_instance_shader_parameter("brightness", brightness)
	if _held:
		_held.set_instance_shader_parameter("brightness", brightness)
