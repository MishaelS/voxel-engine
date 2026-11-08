class_name CommandSource
extends RefCounted
## Who runs a command and where its output goes (like the command source of
## the classic game: the player, the console, a command block).

enum MessageKind { INFO, SUCCESS, ERROR, CHAT }

var name := "Player"
var world: VoxelWorld
## Node whose position is the origin of relative coordinates (~ ~ ~).
var origin: Node3D
## Called as output(text: String, kind: MessageKind).
var output := Callable()


func position() -> Vector3:
	return origin.global_position if origin else Vector3.ZERO


func send(text: String, kind: MessageKind = MessageKind.INFO) -> void:
	if output.is_valid():
		output.call(text, kind)
	else:
		print(text)
