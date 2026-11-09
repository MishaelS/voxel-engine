extends Node
## Autoload "ShaderPacks": the list of shader packs and the selected one.
##
## Built-in packs: "Classic" (lighting like the original game; the default)
## and "Dynamic Lighting" (real-time sun with shadows). Players' packs live
## in user://shaderpacks/<name>.cfg (base + option values) and can be
## edited by hand too; changes to built-in packs are kept as overrides in
## user://shaderpacks/shaderpacks.cfg, which also remembers the selection.
## `changed` fires when the selected pack or one of its options changes.

signal changed

const DIR := "user://shaderpacks"
const CONFIG := "user://shaderpacks/shaderpacks.cfg"
const DEFAULT_PACK := "Classic"

var packs: Array[ShaderPack] = []
var current: ShaderPack


func _ready() -> void:
	reload()


## Reads the packs from disk (built-ins first, then players' packs by name).
func reload() -> void:
	packs.clear()
	var config := ConfigFile.new()
	config.load(CONFIG)
	for pack in [ShaderPack.create("Classic", ShaderPack.Base.CLASSIC, true),
			ShaderPack.create("Dynamic Lighting", ShaderPack.Base.DYNAMIC, true)]:
		pack.values = config.get_value("builtin", pack.name, {})
		packs.append(pack)
	var players: Array[ShaderPack] = []
	var dir := DirAccess.open(DIR)
	if dir:
		for file in dir.get_files():
			if file.ends_with(".cfg") and file != CONFIG.get_file():
				var pack := _load_pack(file)
				if pack:
					players.append(pack)
	players.sort_custom(func(a: ShaderPack, b: ShaderPack) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
	packs.append_array(players)
	current = find(config.get_value("selection", "pack", DEFAULT_PACK))
	if current == null:
		current = packs[0]


func find(pack_name: String) -> ShaderPack:
	for pack in packs:
		if pack.name == pack_name:
			return pack
	return null


func select(pack: ShaderPack) -> void:
	current = pack
	_save_config()
	changed.emit()


## Saves a pack after one of its options changed and applies it if selected.
func pack_changed(pack: ShaderPack) -> void:
	save(pack)
	if pack == current:
		changed.emit()


## A player's copy of `pack` (named "<name> Copy", "<name> Copy 2"...).
func create_copy(pack: ShaderPack) -> ShaderPack:
	var copy_name := "%s Copy" % pack.name
	var n := 2
	while find(copy_name):
		copy_name = "%s Copy %d" % [pack.name, n]
		n += 1
	var copy := pack.copy_as(copy_name)
	copy.file = _file_for(copy_name)
	packs.append(copy)
	save(copy)
	return copy


func rename(pack: ShaderPack, new_name: String) -> void:
	new_name = new_name.strip_edges()
	if pack.builtin or new_name.is_empty() or new_name == pack.name or find(new_name):
		return
	DirAccess.remove_absolute(DIR.path_join(pack.file))
	pack.name = new_name
	pack.file = _file_for(new_name)
	save(pack)
	_save_config()


func delete(pack: ShaderPack) -> void:
	if pack.builtin:
		return
	DirAccess.remove_absolute(DIR.path_join(pack.file))
	packs.erase(pack)
	if pack == current:
		select(find(DEFAULT_PACK))


func save(pack: ShaderPack) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	if pack.builtin:
		_save_config()
		return
	var file := ConfigFile.new()
	file.set_value("pack", "name", pack.name)
	file.set_value("pack", "base", ShaderPack.BASE_NAMES[pack.base])
	file.set_value("pack", "values", pack.values)
	file.save(DIR.path_join(pack.file))


## The folder with players' packs, for the file manager.
func folder() -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	return ProjectSettings.globalize_path(DIR)


func _load_pack(file_name: String) -> ShaderPack:
	var file := ConfigFile.new()
	if file.load(DIR.path_join(file_name)) != OK:
		return null
	var base_index := ShaderPack.BASE_NAMES.find(file.get_value("pack", "base", "classic"))
	var pack := ShaderPack.create(file.get_value("pack", "name", file_name.get_basename()),
		maxi(base_index, 0) as ShaderPack.Base)
	pack.values = file.get_value("pack", "values", {})
	pack.file = file_name
	return pack


func _save_config() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var config := ConfigFile.new()
	config.set_value("selection", "pack", current.name if current else DEFAULT_PACK)
	for pack in packs:
		if pack.builtin and not pack.values.is_empty():
			config.set_value("builtin", pack.name, pack.values)
	config.save(CONFIG)


func _file_for(pack_name: String) -> String:
	var base := pack_name.validate_filename().replace(" ", "_")
	var candidate := base + ".cfg"
	var n := 2
	while FileAccess.file_exists(DIR.path_join(candidate)) or candidate == CONFIG.get_file():
		candidate = "%s_%d.cfg" % [base, n]
		n += 1
	return candidate
