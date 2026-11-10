class_name PlayerModel
extends Node3D
## The player's body, seen in the third-person view (F5): the "player"
## model from assets/models/mobs.json with its skin, and the worn armor
## drawn over it like the game's armor layers (helmet, chestplate and boots
## 1 pixel bigger than the parts, leggings half a pixel; textures
## armor_<material>_1 / _2 from tools/make_armor_textures.py). Legs and
## arms swing with the steps, the head follows the view, the right arm
## swings with the held item, the body bends when sneaking.

## Armor slot -> [[model part, texture layer, inflate, uv, mirrored], ...]
## (the left limbs use the right ones' texture, mirrored, like the game).
const ARMOR_PARTS := [
	[["head", 1, 1.0, [0, 0], false]],
	[["body", 1, 1.0, [16, 16], false], ["right_arm", 1, 1.0, [40, 16], false], ["left_arm", 1, 1.0, [40, 16], true]],
	[["body", 2, 0.5, [16, 16], false], ["right_leg", 2, 0.5, [0, 16], false], ["left_leg", 2, 0.5, [0, 16], true]],
	[["right_leg", 1, 1.0, [0, 16], false], ["left_leg", 1, 1.0, [0, 16], true]],
]

var player: Player
var _model := {}
var _armor_meshes: Array[MeshInstance3D] = []
var _limb_swing := 0.0
var _limb_amount := 0.0
var _last := Vector3.INF


func _ready() -> void:
	_model = MobModels.build("player")
	_model.root.rotation.y = PI # the model faces +Z, the player looks along -Z
	add_child(_model.root)
	if player:
		player.armor.changed.connect(_update_armor)
	_update_armor()


## Rebuilds the armor pieces over the body from what the player wears.
func _update_armor() -> void:
	for mesh in _armor_meshes:
		mesh.queue_free()
	_armor_meshes.clear()
	if player == null:
		return
	var spec: Dictionary = _model.spec
	for slot in player.armor.size():
		var item := Items.get_type(player.armor.id_at(slot))
		if player.armor.count_at(slot) <= 0 or item == null or item.armor_slot != slot:
			continue
		for piece: Array in ARMOR_PARTS[slot]:
			var part: Dictionary = {}
			for candidate: Dictionary in spec.parts:
				if candidate.name == piece[0]:
					part = candidate.duplicate()
			part.texture = "armor_%s_%d" % [item.armor_material, piece[1]]
			part.inflate = piece[2]
			part.uv = piece[3]
			part.mirror = piece[4]
			var instance := MeshInstance3D.new()
			instance.mesh = MobModels.part_mesh("player", part)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			(_model.parts[piece[0]] as Node3D).add_child(instance)
			_armor_meshes.append(instance)


func _process(delta: float) -> void:
	if player == null or not visible:
		_last = Vector3.INF
		return
	var here := player.global_position
	var moved := 0.0 if _last == Vector3.INF else Vector2(here.x - _last.x, here.z - _last.z).length()
	_last = here
	var speed := moved / maxf(delta, 1e-4) / 20.0 # blocks per tick
	_limb_amount = lerpf(_limb_amount, minf(speed * 4.0, 1.0), minf(delta * 10.0, 1.0))
	_limb_swing += speed * 4.0 * delta * 20.0
	var swing := cos(_limb_swing * 0.6662) * 1.4 * _limb_amount
	var parts: Dictionary = _model.parts
	var bend := 0.5 if player.sneaking else 0.0
	(parts.right_leg as Node3D).rotation.x = swing
	(parts.left_leg as Node3D).rotation.x = -swing
	(parts.left_arm as Node3D).rotation.x = swing * 0.7 + bend * 0.8
	var arm := -swing * 0.7 + bend * 0.8
	var hit := player.held_item.swing_progress() if player.held_item else -1.0
	if hit >= 0.0:
		arm -= sin(sqrt(hit) * PI) * 1.6
	(parts.right_arm as Node3D).rotation.x = arm
	(parts.head as Node3D).rotation.x = -player.pitch()
	(parts.body as Node3D).rotation.x = bend
	_model.root.position.y = -0.2 if player.sneaking else 0.0
	var brightness := player.world.brightness_at(here + Vector3(0, 1, 0)) if player.world else 1.0
	var hurt := 1.0 if player.hurt_ticks > 0 or player.dead else 0.0
	for mesh: MeshInstance3D in _model.meshes + _armor_meshes:
		mesh.set_instance_shader_parameter("brightness", brightness)
		mesh.set_instance_shader_parameter("hurt", hurt)
