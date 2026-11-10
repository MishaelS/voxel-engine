class_name MusicBehavior
extends RefCounted
## Jukeboxes and note blocks like the classic game.
## - Jukebox: right-click with a music disc puts it in and plays its track
##   (assets/records/<disc>.mp3, our own music: tools/make_music.py), heard
##   up to 64 blocks around; right-click again throws the disc out and stops
##   it; breaking the jukebox drops the disc.
## - Note block: right-click raises its note a semitone (25 notes, two
##   octaves from F#3, then back to the lowest), left-click plays it. The
##   block under it picks the instrument: stone-like = bass drum, sand and
##   gravel = snare, glass = clicks, wood = bass, anything else = harp. It
##   only sounds with air above it. A colored note floats up.
## Both keep their state in a block entity ("jukebox": record, "note_block":
## note).

const RECORDS_DIR := "res://assets/records/"
const RECORD_RANGE := 64.0
const NOTES := 25


## Right-click on a jukebox with `held` in hand. Returns true if used.
static func use_jukebox(world: VoxelWorld, pos: Vector3i, player: Player, held: int) -> bool:
	var entity := world.block_entity(pos)
	var record: int = entity.get("record", 0)
	if record != 0:
		eject(world, pos)
		return true
	var name := Items.name_of(held) if held != Blocks.AIR else ""
	if not name.begins_with("music_disc_"):
		return false
	entity.record = held
	if not player.is_creative():
		player.inventory.take(player.selected_slot)
	play_record(world, pos, name.trim_prefix("music_disc_"))
	return true


## Throws the disc out of the jukebox (and stops the music).
static func eject(world: VoxelWorld, pos: Vector3i) -> void:
	var entity := world.block_entity(pos)
	var record: int = entity.get("record", 0)
	stop_record(world, pos)
	if record == 0:
		return
	entity.record = 0
	world.items.spawn(record, 1, Vector3(pos) + Vector3(0.5, 1.1, 0.5), Vector3(randf_range(-0.05, 0.05), 0.2, randf_range(-0.05, 0.05)))


static func play_record(world: VoxelWorld, pos: Vector3i, track: String) -> void:
	stop_record(world, pos)
	var stream := load(RECORDS_DIR + track + ".mp3") as AudioStream
	if stream == null:
		return
	var speaker := AudioStreamPlayer3D.new()
	speaker.stream = stream
	speaker.bus = "Music"
	speaker.max_distance = RECORD_RANGE
	speaker.unit_size = 8.0
	world.add_child(speaker)
	speaker.global_position = Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	speaker.play()
	speaker.finished.connect(func() -> void: stop_record(world, pos))
	world.record_players[pos] = speaker


static func stop_record(world: VoxelWorld, pos: Vector3i) -> void:
	var speaker: AudioStreamPlayer3D = world.record_players.get(pos)
	if speaker:
		speaker.queue_free()
		world.record_players.erase(pos)


## Right-click on a note block: one semitone up, then plays it.
static func tune(world: VoxelWorld, pos: Vector3i) -> void:
	var entity := world.block_entity(pos)
	entity.note = (int(entity.get("note", 0)) + 1) % NOTES
	play_note(world, pos)


## Plays the note block's note (left-click), if there is air above it.
static func play_note(world: VoxelWorld, pos: Vector3i) -> void:
	if world.get_block(pos + Vector3i.UP) != Blocks.AIR:
		return
	var note: int = world.block_entity(pos).get("note", 0)
	var pitch := pow(2.0, (note - 12) / 12.0)
	var point := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	Sounds.play("note/" + instrument(world.get_block(pos + Vector3i.DOWN)), point, 3.0, pitch)
	world.particles.note(point + Vector3(0, 0.7, 0), note)


## The instrument the block under a note block gives.
static func instrument(below: int) -> String:
	if below == Blocks.AIR:
		return "harp"
	var block := Blocks.get_type(below)
	var name := block.name
	if name in ["sand", "gravel"]:
		return "snare"
	if name.contains("glass") or name == "glowstone":
		return "hat"
	if block.tool == "axe" or name.contains("planks") or name.contains("_log"):
		return "bass"
	if block.tool == "pickaxe":
		return "bd"
	return "harp"
