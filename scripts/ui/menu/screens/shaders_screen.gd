class_name ShadersScreen
extends MenuScreen
## "Shaders": the shader packs (ShaderPacks). Click a pack to use it (it
## applies at once). Pack Options edits the selected pack's options; New
## Pack copies it into a pack of your own; Delete removes your pack; Open
## Folder shows where packs are saved (they are plain text files).

var _buttons: Array[Button] = []
var _delete: Button


func _init() -> void:
	title = "Shaders"
	columns = 1


func build() -> void:
	for pack in ShaderPacks.packs:
		var button := add_list_wide_button("", func() -> void:
			ShaderPacks.select(pack)
			_update())
		button.set_meta("pack", pack)
		_buttons.append(button)
	var info := Label.new()
	info.text = "Classic: lighting like the original game. Dynamic Lighting: sun, moon and shadows."
	info.add_theme_color_override("font_color", Color("a0a0a0"))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_list_item(info)
	add_bottom_row([
		["Pack Options...", func() -> void: menu.push(ShaderPackScreen.new(ShaderPacks.current))],
		["New Pack", func() -> void:
			var copy := ShaderPacks.create_copy(ShaderPacks.current)
			ShaderPacks.select(copy)
			_reopen()
			menu.push(ShaderPackScreen.new(copy))],
	])
	var row := add_bottom_row([
		["Delete Pack", func() -> void:
			var pack := ShaderPacks.current
			menu.push(ConfirmScreen.new("Delete the shader pack?", Lang.t("'%s' will be deleted.") % pack.name, "Delete",
				func() -> void:
					ShaderPacks.delete(pack)
					_reopen()))],
		["Open Folder", func() -> void: OS.shell_open(ShaderPacks.folder())],
	])
	_delete = row[0]
	add_done_button()
	_update()


func refresh() -> void:
	super()
	if not _buttons.is_empty():
		_update()


func _update() -> void:
	for button in _buttons:
		var pack: ShaderPack = button.get_meta("pack")
		var selected := pack == ShaderPacks.current
		var pack_name := Lang.t(pack.name) if pack.builtin else pack.name
		button.text = "%s%s (%s)%s" % ["> " if selected else "", pack_name, Lang.t(pack.base_label()), " <" if selected else ""]
	_delete.disabled = ShaderPacks.current.builtin


## Rebuilds the screen (the list of packs changed).
func _reopen() -> void:
	menu.back()
	menu.push(ShadersScreen.new())
