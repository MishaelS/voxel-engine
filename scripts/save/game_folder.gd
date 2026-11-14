class_name GameFolder
extends RefCounted
## The game's own folder (user://): worlds, packs, screenshots, settings.
## The mods/ folder is made at startup with a note that mods are planned.

const MODS := "user://mods"
const MODS_README := "user://mods/README.txt"
const README_TEXT := "Voxel Engine: mods folder\n\nMods are not supported yet - they are planned.\nThis folder is kept for them; nothing here is loaded for now.\n"


## Makes the folders a player may want to fill (keeps what is there).
static func ensure() -> void:
	for dir: String in [WorldSave.ROOT, TexturePacks.DIR, ShaderPacks.DIR, Screenshots.FOLDER, MODS]:
		DirAccess.make_dir_recursive_absolute(dir)
	if not FileAccess.file_exists(MODS_README):
		var file := FileAccess.open(MODS_README, FileAccess.WRITE)
		if file:
			file.store_string(README_TEXT)


## The folder's path on this computer.
static func path() -> String:
	return ProjectSettings.globalize_path("user://")


## Shows the folder in the system's file manager.
static func open() -> void:
	ensure()
	OS.shell_open(path())
