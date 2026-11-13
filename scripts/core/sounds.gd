extends Node
## Autoload: sound effects and music, like the classic game.
## - play("dig/stone", position): a random variant of a sound group
##   (assets/sounds/dig/stone1.wav, stone2.wav...), in 3D at a world
##   position (heard up to ~16 blocks, quieter with distance) or, without a
##   position, straight to the ears (menus, picking up items);
## - volume and pitch per call, like the game's (pitch varies a little);
## - two buses: Sound and Music, with the Sound and Music settings;
## - every menu button clicks;
## - music: a track from assets/music now and then (every 10-20 minutes,
##   like the game), one for the time of day (MUSIC_TIMES: at dawn, by day,
##   in the evening and at night; tracks not listed play any time; in the
##   menus, as by day).
## Sounds are found by listing the folders (also in exported games, where
## the files are imported).

const SOUNDS_DIR := "res://assets/sounds"
const MUSIC_DIR := "res://assets/music"
const VOICES_3D := 24
const VOICES_2D := 8
## Distance (blocks) where a sound is at half volume, and the farthest.
const UNIT_SIZE := 4.0
const MAX_DISTANCE := 24.0
## Seconds between music tracks (random in this range).
const MUSIC_PAUSE := Vector2(600.0, 1200.0)
## When tracks play (file name without the extension -> part of the day);
## the others any time.
const MUSIC_TIMES := {
	"the_dawn": "dawn",
	"empty_pixel_world": "day", "early_exploration": "day",
	"the_forest_glitches": "night", "deep_cavern_silence": "night",
}
## Parts of the day in the world clock's ticks (0 = sunrise at 06:00, 6000
## noon, 12000 sunset, 18000 midnight): dawn from about 04:30 to 08:00, day
## to 17:30, then evening and night.
const DAWN_START := 22500.0
const DAY_START := 2000.0
const NIGHT_START := 11500.0

var _groups := {} # "dig/stone" -> Array[AudioStream]
var _players_3d: Array[AudioStreamPlayer3D] = []
var _players_2d: Array[AudioStreamPlayer] = []
var _next_3d := 0
var _next_2d := 0
var _music: AudioStreamPlayer
var _tracks: Array[AudioStream] = []
var _track_times: Array[String] = [] # part of the day each track is for ("" = any)
var _music_wait := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_bus("Sound")
	_make_bus("Music")
	_scan(SOUNDS_DIR, "")
	for path in _files(MUSIC_DIR):
		var stream := load(MUSIC_DIR.path_join(path)) as AudioStream
		if stream:
			_tracks.append(stream)
			_track_times.append(MUSIC_TIMES.get(path.get_file().get_basename(), ""))
	for i in VOICES_3D:
		var player := AudioStreamPlayer3D.new()
		player.bus = "Sound"
		player.unit_size = UNIT_SIZE
		player.max_distance = MAX_DISTANCE
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_players_3d.append(player)
	for i in VOICES_2D:
		var player := AudioStreamPlayer.new()
		player.bus = "Sound"
		add_child(player)
		_players_2d.append(player)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_music_wait = randf_range(10.0, 60.0) # the first track comes soon
	Settings.changed.connect(_on_setting)
	for key in ["sound_volume", "music_volume"]:
		_on_setting(key, Settings.get_value(key))
	get_tree().node_added.connect(_on_node_added)


## Plays a random variant of a sound group ("dig/stone", "random/pop").
## `position`: a Vector3 in the world, or null for a sound without place.
## `volume`: 0..1 (more is louder); `pitch`: 1 = as recorded.
func play(group: String, position: Variant = null, volume: float = 1.0, pitch: float = 1.0) -> void:
	var variants: Array = _groups.get(group, [])
	if variants.is_empty() or volume <= 0.0:
		return
	var stream: AudioStream = variants[randi() % variants.size()]
	if position is Vector3:
		var player := _players_3d[_next_3d]
		_next_3d = (_next_3d + 1) % _players_3d.size()
		player.global_position = position
		player.stream = stream
		player.volume_db = linear_to_db(volume)
		player.pitch_scale = pitch
		player.play()
	else:
		var player := _players_2d[_next_2d]
		_next_2d = (_next_2d + 1) % _players_2d.size()
		player.stream = stream
		player.volume_db = linear_to_db(volume)
		player.pitch_scale = pitch
		player.play()


func has_group(group: String) -> bool:
	return _groups.has(group)


## The sounds of a block when broken, placed or walked on (BlockType.sound).
func play_block(kind: String, block_id: int, position: Vector3) -> void:
	var material := Blocks.get_type(block_id).sound
	if material == "":
		return
	match kind:
		"break":
			if material == "glass":
				play("random/glass", position, 1.0, randf_range(0.9, 1.1))
			else:
				play("dig/" + material, position, 1.0, 0.8 * randf_range(0.9, 1.1))
		"place":
			play("dig/" + (material if material != "glass" else "stone"), position, 1.0, 0.8)
		"step":
			play("step/" + (material if material != "glass" else "stone"), position, 0.3, 1.0)
		"hit":
			play("step/" + (material if material != "glass" else "stone"), position, 0.25, 0.5)


func _process(delta: float) -> void:
	if _tracks.is_empty() or _music.playing:
		return
	_music_wait -= delta
	if _music_wait <= 0.0:
		_music.stream = _pick_track()
		_music.play()
		_music_wait = randf_range(MUSIC_PAUSE.x, MUSIC_PAUSE.y)


## The part of the day now: "dawn", "day" or "night" (menus: "day").
func part_of_day() -> String:
	var game := Game.find(get_tree())
	if game == null or game.world == null or game.world.clock == null:
		return "day"
	var time := game.world.clock.time_of_day()
	if time >= DAWN_START or time < DAY_START:
		return "dawn"
	return "day" if time < NIGHT_START else "night"


## A random track for now: one for this part of the day or for any time.
func _pick_track() -> AudioStream:
	var part := part_of_day()
	var fitting: Array[AudioStream] = []
	for i in _tracks.size():
		if _track_times[i] == "" or _track_times[i] == part:
			fitting.append(_tracks[i])
	if fitting.is_empty():
		fitting = _tracks
	return fitting[randi() % fitting.size()]


func _on_setting(key: String, value: Variant) -> void:
	var bus: String = {"sound_volume": "Sound", "music_volume": "Music"}.get(key, "")
	if bus == "":
		return
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(float(value) / 100.0, 0.0001)))
	AudioServer.set_bus_mute(index, float(value) <= 0.0)


## Every button in the game clicks when pressed, like the classic menus.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).pressed.connect(func() -> void: play("random/click"))


func _make_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


## Groups by folder and name without the trailing number: dig/stone1.wav and
## dig/stone2.wav make "dig/stone".
func _scan(dir_path: String, prefix: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan(dir_path.path_join(sub), prefix + sub + "/")
	for file in _files(dir_path):
		var stream := load(dir_path.path_join(file)) as AudioStream
		if stream == null:
			continue
		var base := file.get_basename()
		while base.length() > 0 and base[base.length() - 1].is_valid_int():
			base = base.left(-1)
		var group := prefix + base
		if not _groups.has(group):
			_groups[group] = []
		(_groups[group] as Array).append(stream)


## Sound files in a folder (in an exported game the folder holds the
## .import files: their names without ".import").
func _files(dir_path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	for file in dir.get_files():
		if file.ends_with(".import"):
			file = file.trim_suffix(".import")
		if (file.ends_with(".wav") or file.ends_with(".ogg") or file.ends_with(".mp3")) and not result.has(file):
			result.append(file)
	return result
