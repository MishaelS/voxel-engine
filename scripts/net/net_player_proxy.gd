class_name NetPlayerProxy
extends RefCounted
## A client's player for the host's creatures (Net._client_interact): what
## Mob.interact and Minecart.interact use of a Player: the item in its hand
## (an inventory of the held slot and one more for what it gets), creative,
## where it stands, whether it rides, and getting on.

var inventory := Inventory.new(2)
var selected_slot := 0
## Not null while it rides something (what, the host need not know).
var vehicle: Object = null
var global_position := Vector3.ZERO
## The creature it got on (mount), for the host to seat it there.
var mounted: Entity = null
var _creative := false


func _init(held: PackedInt32Array, creative: bool, riding: bool, at: Vector3) -> void:
	if held.size() == 3:
		inventory.set_slot(0, held[0], held[1], held[2])
	_creative = creative
	global_position = at
	if riding:
		vehicle = RefCounted.new()


func is_creative() -> bool:
	return _creative


func mount(creature: Entity) -> void:
	mounted = creature


func open_container(_entity: Dictionary) -> void:
	pass
