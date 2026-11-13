class_name CommandSource
extends RefCounted
## Who runs a command and where its output goes (like the command source of
## the classic game: the player, the console, a command block).
## /execute makes changed copies: another executor ("as"), another place
## or facing ("at", "positioned", "rotated").

enum MessageKind { INFO, SUCCESS, ERROR, CHAT }

var name := "Player"
var world: VoxelWorld
## The executor (@s): the player, a creature (/execute as) or null. Its
## position is the origin of relative coordinates (~ ~ ~) unless
## position_override is set.
var origin: Node3D
## Called as output(text: String, kind: MessageKind).
var output := Callable()
## Where and which way the command runs instead of the origin's (/execute
## at, positioned, rotated): Vector3.INF / Vector2.INF when not set.
var position_override := Vector3.INF
## (yaw, pitch) in degrees like the classic game: yaw 0 = south (+z),
## 90 = west; pitch 90 = straight down.
var rotation_override := Vector2.INF


func position() -> Vector3:
	if position_override != Vector3.INF:
		return position_override
	return CommandTargets.position_of(origin) if origin else Vector3.ZERO


## Facing as (yaw, pitch) in degrees (see rotation_override).
func rotation() -> Vector2:
	if rotation_override != Vector2.INF:
		return rotation_override
	return CommandTargets.rotation_of(origin) if origin else Vector2.ZERO


## The player on this computer running the command, or null.
func player() -> Player:
	return origin as Player


func send(text: String, kind: MessageKind = MessageKind.INFO) -> void:
	if output.is_valid():
		output.call(text, kind)
	else:
		print(text)


## A copy to change (/execute).
func copy() -> CommandSource:
	var result := CommandSource.new()
	result.name = name
	result.world = world
	result.origin = origin
	result.output = output
	result.position_override = position_override
	result.rotation_override = rotation_override
	return result
