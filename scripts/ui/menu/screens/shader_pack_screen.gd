class_name ShaderPackScreen
extends MenuScreen
## Options of one shader pack, built from the pack's settings (toggles,
## choices, sliders). Changes apply at once and are saved. Your own packs
## can be renamed here.

var _pack: ShaderPack


func _init(pack: ShaderPack) -> void:
	_pack = pack
	title = "%s (%s)" % [Lang.t(pack.name) if pack.builtin else pack.name, Lang.t(pack.base_label())]


func build() -> void:
	if not _pack.builtin:
		var field := LineEdit.new()
		field.text = _pack.name
		field.max_length = 32
		field.custom_minimum_size = Vector2(UiTheme.HALF_BUTTON, UiTheme.BUTTON_HEIGHT)
		field.tooltip_text = "Pack name (Enter to rename)"
		field.text_submitted.connect(func(text: String) -> void: ShaderPacks.rename(_pack, text))
		field.focus_exited.connect(func() -> void: ShaderPacks.rename(_pack, field.text))
		add_list_item(field)
		var spacer := Control.new()
		add_list_item(spacer)
	for setting in _pack.settings(func() -> void: ShaderPacks.pack_changed(_pack)):
		add_option(setting)
	add_bottom_button("Reset to Defaults", func() -> void:
		_pack.reset()
		ShaderPacks.pack_changed(_pack)
		refresh())
	add_done_button()
