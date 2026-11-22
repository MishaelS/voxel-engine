class_name OptionsScreen
extends MenuScreen
## "Options": the classic look (dirt header and footer, the darker list band,
## stone buttons) with a modern layout. On the left the categories, each with
## a small picture of a block or item; on the right the chosen category's
## settings, one per row: the name, a thin line, a reset arrow (when changed)
## and the control: a switch for toggles, a button for choices, a slider for
## numbers. Groups in a category ("Quality", "Mouse"...) fold away on click.
##
## Categories: General, Player, Audio, Video (with the Quality, Details,
## Performance and Animations groups and the shader pack), Controls (mouse
## and every key binding), Texture Packs, Language, World (in a world) and
## Search (any setting by name). The settings come from Settings categories,
## so a new setting there appears here by itself.

const P := UiTheme.PIXEL
const SIDEBAR_WIDTH := 112 * P
## The sidebar in a narrow window (long names end with "...").
const NARROW_SIDEBAR_WIDTH := 84 * P
const SIDEBAR_GAP := 8 * P
const MAX_LIST_WIDTH := 300 * P
const SIDE_MARGIN := 8 * P
const ROW_HEIGHT := UiTheme.BUTTON_HEIGHT
const HEADER_HEIGHT := 14 * P
const ICON_SIZE := 16 * P
const RESET_SIZE := 12 * P
const LINE_COLOR := Color(0.5, 0.5, 0.5, 0.55)
const DIM_TEXT := Color("a0a0a0")

## [id, English name, icon: block/item name, or "@head" for the player's face]
const CATEGORIES := [
	["general", "General", "grass_plains"],
	["player", "Player", "@head"],
	["audio", "Audio", "jukebox"],
	["video", "Video", "iron_pickaxe"],
	["controls", "Controls", "piston"],
	["texture_packs", "Texture Packs", "painting"],
	["language", "Language", "book"],
	["world", "World", "map"],
	["search", "Search", "sign"],
]
## Settings categories shown as groups of the Video category.
const VIDEO_GROUPS := [
	["video", "General"], ["quality", "Quality"], ["details", "Details"],
	["performance", "Performance"], ["animations", "Animations"],
]
## Settings of the "general" store category shown under Audio instead.
const AUDIO_KEYS := ["master_volume", "music_volume", "records_volume", "weather_volume", "blocks_volume",
	"hostile_volume", "friendly_volume", "players_volume", "ambient_volume", "cave_echo"]

## The category shown last (opening the screen again shows it).
static var _last_category := "general"
## Folded groups by name (kept while the game runs).
static var _folded := {}
## The search text (kept while the game runs).
static var _query := ""

var _category := ""
var _body: HBoxContainer
var _sidebar: VBoxContainer
var _side_scroll: ScrollContainer
var _sidebar_buttons := {} # id -> Button
var _rows: VBoxContainer
var _updaters: Array[Callable] = []
var _waiting_action := ""
var _search_results: VBoxContainer
var _reset_icon: Texture2D
var _skin_error := ""


func _init(category: String = "") -> void:
	title = "Options"
	_category = category if category != "" else _last_category


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reset_icon = _make_reset_icon()
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_top = 16 * P
	layout.offset_bottom = -8 * P
	layout.add_theme_constant_override("separation", 10 * P)
	add_child(layout)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", UiTheme.TITLE_COLOR)
	layout.add_child(title_label)

	var band := Control.new() # holds the body, centered by _layout()
	band.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(band)
	if menu.in_game:
		# No dirt behind the menu in a world: a dark band keeps text readable.
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.35)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.offset_top = -4 * P
		shade.offset_bottom = 4 * P
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(shade)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", SIDEBAR_GAP)
	band.add_child(_body)
	band.resized.connect(func() -> void: _layout(band))

	_side_scroll = ScrollContainer.new()
	_side_scroll.custom_minimum_size.x = SIDEBAR_WIDTH
	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_side_scroll)
	_sidebar = VBoxContainer.new()
	_sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sidebar.add_theme_constant_override("separation", P)
	_side_scroll.add_child(_sidebar)

	var scroll := ScrollContainer.new()
	list_area = scroll # Menu draws the darker dirt band behind it
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_body.add_child(scroll)
	var padding := MarginContainer.new() # (room for the scroll bar)
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.add_theme_constant_override("margin_right", 4 * P)
	scroll.add_child(padding)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2 * P)
	padding.add_child(_rows)

	_bottom = VBoxContainer.new()
	_bottom.add_theme_constant_override("separation", ROW_GAP)
	var bottom_center := CenterContainer.new()
	bottom_center.add_child(_bottom)
	layout.add_child(bottom_center)
	add_done_button()

	for entry: Array in CATEGORIES:
		if entry[0] == "world" and menu.world == null:
			continue
		_sidebar.add_child(_category_button(entry[0], entry[1], entry[2]))
	if not _sidebar_buttons.has(_category):
		_category = "general"
	show_category(_category)


## Centers the sidebar and list, at most MAX_LIST_WIDTH wide; a narrow
## window gets a narrower sidebar.
func _layout(band: Control) -> void:
	_side_scroll.custom_minimum_size.x = SIDEBAR_WIDTH if band.size.x >= 400 * P else NARROW_SIDEBAR_WIDTH
	var width := minf(band.size.x - 2.0 * SIDE_MARGIN, SIDEBAR_WIDTH + SIDEBAR_GAP + MAX_LIST_WIDTH)
	_body.position = Vector2(floorf((band.size.x - width) / 2.0), 0)
	_body.size = Vector2(width, band.size.y)


## Shows a category's settings on the right.
func show_category(id: String) -> void:
	_category = id
	_last_category = id
	_waiting_action = ""
	for key: String in _sidebar_buttons:
		_style_category_button(_sidebar_buttons[key], key == id)
	_updaters.clear()
	_search_results = null
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if id == "search":
		_build_search()
	else:
		_add_entries(_rows, _entries(id), true)
	refresh()
	(list_area as ScrollContainer).scroll_vertical = 0


func refresh() -> void:
	super.refresh()
	for updater in _updaters:
		updater.call()


func capture_key(event: InputEventKey) -> bool:
	if _waiting_action == "":
		return false
	if event.keycode != KEY_ESCAPE:
		KeyBindings.rebind(_waiting_action, event.physical_keycode)
		Settings.save_settings()
	_waiting_action = ""
	refresh()
	return true


# --- What each category holds --------------------------------------------------

## A category's rows: {"group": name} starts a group; {"label": name,
## "build": f() -> Control} is a row found by Search; {"build": ...} alone is
## a row Search skips (pictures, pack lists).
func _entries(id: String) -> Array:
	var result := []
	match id:
		"general":
			for setting: Setting in Settings.in_category("general"):
				if not setting.key in AUDIO_KEYS:
					result.append(_setting_entry(setting))
			result.append({"group": "Other"})
			for setting: Setting in Settings.in_category("other"):
				result.append(_setting_entry(setting))
			result.append({"label": "Open Game Folder", "build": func() -> Control:
				return _wide_button("Open Game Folder", GameFolder.open)})
		"audio":
			result.append({"group": "Volume"})
			for key: String in AUDIO_KEYS:
				result.append(_setting_entry(Settings.get_setting(key)))
		"video":
			for group: Array in VIDEO_GROUPS:
				result.append({"group": group[1]})
				for setting: Setting in Settings.in_category(group[0]):
					result.append(_setting_entry(setting))
			result.append({"group": "Shaders"})
			result.append({"label": "Shader Pack", "build": _shader_pack_row})
		"controls":
			if Settings.phone_mode_available: # (debug builds only for now)
				result.append(_setting_entry(Settings.get_setting("control_mode")))
				result.append({"group": "Touch Screen"})
				result.append(_setting_entry(Settings.get_setting("touch_button_size")))
			result.append({"group": "Mouse"})
			for setting: Setting in Settings.in_category("controls"):
				if not setting.key in ["control_mode", "touch_button_size"]:
					result.append(_setting_entry(setting))
			var category := ""
			for binding: Array in KeyBindings.ACTIONS:
				if binding[2] != category:
					category = binding[2]
					result.append({"group": category})
				result.append({"label": binding[1], "build": _key_row.bind(binding[0], binding[1])})
			result.append({"build": func() -> Control:
				return _wide_button("Reset Keys", func() -> void:
					KeyBindings.reset_all()
					Settings.save_settings()
					_waiting_action = ""
					refresh())})
		"player":
			result.append({"build": func() -> Control:
				var preview := PlayerSettingsScreen.SkinPreview.new()
				preview.custom_minimum_size = Vector2(0, 84 * P)
				return preview})
			result.append({"label": "Name", "build": _name_row})
			result.append({"label": "Name Color", "build": _name_color_row})
			result.append({"label": "Skin", "build": _skin_row})
			result.append({"build": func() -> Control:
				var status := Label.new()
				status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				status.add_theme_color_override("font_color", Color("ff7070"))
				_updaters.append(func() -> void:
					status.text = _skin_error
					status.visible = _skin_error != "")
				return status})
		"texture_packs":
			result.append({"build": _texture_pack_list})
		"language":
			result.append({"build": _language_list})
		"world":
			var world := menu.world
			if world:
				result.append({"group": "Game Rules"})
				for rule_name in GameRules.names():
					result.append(_setting_entry(WorldSettingsScreen._rule_setting(world, rule_name)))
				result.append({"group": "World Generation"})
				if world.save == null:
					result.append(_setting_entry(Setting.choice("generator", "Generator",
						PackedStringArray(WorldSettingsScreen.GENERATORS), 0).bind(
							func() -> Variant: return int(world.generator),
							func(value: Variant) -> void: world.generator = value)))
				result.append({"label": "Seed", "build": func() -> Control:
					var value := Label.new()
					value.text = str(world.world_seed)
					value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
					return _row("Seed", value)})
				if world.save == null:
					result.append({"build": func() -> Control:
						return _wide_button("Regenerate World (same seed)", func() -> void:
							world.generate()
							menu.close())})
					result.append({"build": func() -> Control:
						return _wide_button("New World (random seed)", func() -> void:
							world.world_seed = randi()
							world.generate()
							menu.close())})
	return result


func _setting_entry(setting: Setting) -> Dictionary:
	return {"label": setting.label, "build": _setting_row.bind(setting)}


## Adds rows to `parent`; with `groups`, each group's rows go under a header
## that folds them away.
func _add_entries(parent: VBoxContainer, entries: Array, groups: bool) -> void:
	var target := parent
	for entry: Dictionary in entries:
		if entry.has("group"):
			if not groups:
				continue
			var group_name: String = entry["group"]
			var content := VBoxContainer.new()
			content.add_theme_constant_override("separation", 2 * P)
			content.visible = not _folded.get(group_name, false)
			parent.add_child(_group_header(group_name, content))
			parent.add_child(content)
			target = content
		else:
			target.add_child((entry["build"] as Callable).call())


func _build_search() -> void:
	var field := LineEdit.new()
	field.text = _query
	field.placeholder_text = Lang.t("Search...")
	field.custom_minimum_size.y = ROW_HEIGHT
	field.clear_button_enabled = true
	field.text_changed.connect(func(text: String) -> void:
		_query = text
		_fill_search())
	_rows.add_child(field)
	_search_results = VBoxContainer.new()
	_search_results.add_theme_constant_override("separation", 2 * P)
	_rows.add_child(_search_results)
	_fill_search()
	field.call_deferred("grab_focus")


## The rows of every category whose name has the search text, under the
## category's name.
func _fill_search() -> void:
	_updaters.clear()
	for child in _search_results.get_children():
		_search_results.remove_child(child)
		child.queue_free()
	var query := _query.strip_edges().to_lower()
	if query == "":
		return
	var found := false
	for category: Array in CATEGORIES:
		if category[0] == "search" or not _sidebar_buttons.has(category[0]):
			continue
		var matches := []
		for entry: Dictionary in _entries(category[0]):
			if entry.has("label") and Lang.t(entry["label"]).to_lower().contains(query):
				matches.append(entry)
		if matches.is_empty():
			continue
		found = true
		var header := Label.new()
		header.text = category[1]
		header.custom_minimum_size.y = HEADER_HEIGHT
		header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		header.add_theme_color_override("font_color", DIM_TEXT)
		_search_results.add_child(header)
		_add_entries(_search_results, matches, false)
	if not found:
		var none := Label.new()
		none.text = "Nothing found"
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.add_theme_color_override("font_color", DIM_TEXT)
		_search_results.add_child(none)
	refresh()


# --- Rows ----------------------------------------------------------------------

## A row: the name, a thin line, the reset arrow and the control.
## `is_default` / `reset` drive the arrow (no arrow without them).
func _row(label_text: String, control: Control, is_default := Callable(), reset := Callable()) -> SettingRow:
	var row := SettingRow.new()
	row.custom_minimum_size.y = ROW_HEIGHT
	var label := Label.new()
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.label = label
	row.add_child(label)
	if reset.is_valid():
		var button := Button.new()
		button.icon = _reset_icon
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = "Reset"
		button.add_theme_color_override("icon_normal_color", DIM_TEXT)
		button.add_theme_color_override("icon_hover_color", UiTheme.HOVER_TEXT_COLOR)
		button.add_theme_color_override("icon_pressed_color", UiTheme.HOVER_TEXT_COLOR)
		button.pressed.connect(func() -> void:
			reset.call()
			refresh())
		row.reset = button
		row.add_child(button)
		_updaters.append(func() -> void: button.visible = not is_default.call())
	row.control = control
	row.add_child(control)
	return row


func _setting_row(setting: Setting) -> Control:
	var control: Control
	match setting.kind:
		Setting.Kind.BOOL:
			# One stone button saying ON / OFF (clearer than a sliding switch).
			var toggle := Button.new()
			toggle.focus_mode = Control.FOCUS_NONE
			toggle.clip_text = true
			toggle.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			toggle.pressed.connect(func() -> void:
				setting.set_value(not setting.get_value())
				refresh())
			_updaters.append(func() -> void: toggle.text = Lang.t("ON" if bool(setting.get_value()) else "OFF"))
			control = toggle
		Setting.Kind.CHOICE:
			var button := Button.new()
			button.focus_mode = Control.FOCUS_NONE
			button.clip_text = true
			button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # (display_value translates)
			button.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
			button.gui_input.connect(func(event: InputEvent) -> void:
				# Right click: the previous choice.
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
					button.set_meta("back", true))
			button.pressed.connect(func() -> void:
				var step := -1 if button.get_meta("back", false) else 1
				button.set_meta("back", false)
				setting.set_value(posmod(int(setting.get_value()) + step, setting.choices.size()))
				refresh())
			_updaters.append(func() -> void: button.text = setting.display_value())
			control = button
		_:
			var slider := _make_slider(setting)
			var label := slider.get_node("Text") as Label
			slider.value_changed.connect(func(_value: float) -> void:
				label.text = setting.display_value()
				refresh())
			_updaters.append(func() -> void:
				(slider as HSlider).set_value_no_signal(setting.get_value())
				label.text = setting.display_value())
			control = slider
	if setting.tooltip:
		control.tooltip_text = setting.tooltip
	return _row(setting.label, control,
		func() -> bool: return setting.get_value() == setting.sanitize(setting.default_value),
		func() -> void: setting.set_value(setting.default_value))


func _key_row(action: String, label_text: String) -> Control:
	var key := _make_button("", func() -> void:
		_waiting_action = action
		refresh())
	_updaters.append(func() -> void:
		if action == _waiting_action:
			key.text = "> %s <" % KeyBindings.key_name(action)
			key.add_theme_color_override("font_color", UiTheme.HOVER_TEXT_COLOR)
		else:
			key.text = KeyBindings.key_name(action)
			if KeyBindings.has_conflict(action):
				key.add_theme_color_override("font_color", UiTheme.WARNING_COLOR)
			else:
				key.remove_theme_color_override("font_color"))
	return _row(label_text, key,
		func() -> bool: return KeyBindings.is_default(action),
		func() -> void:
			KeyBindings.reset(action)
			Settings.save_settings())


func _shader_pack_row() -> Control:
	var button := _make_button("", func() -> void: menu.push(ShadersScreen.new()))
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_updaters.append(func() -> void:
		var pack := ShaderPacks.current
		button.text = Lang.t(pack.name) if pack.builtin else pack.name)
	return _row("Shader Pack", button)


func _name_row() -> Control:
	var field := LineEdit.new()
	field.text = Net.player_name
	field.max_length = 16
	field.placeholder_text = Lang.t("Your Name")
	field.text_changed.connect(func(text: String) -> void:
		var clean := text.strip_edges()
		if clean != "":
			Net.player_name = clean
			Net.save_config())
	return _row("Name", field)


func _name_color_row() -> Control:
	var button := _make_button("", func() -> void:
		PlayerProfile.name_color = (PlayerProfile.name_color + 1) % PlayerProfile.COLORS.size()
		PlayerProfile.save_profile()
		Net.send_look()
		refresh())
	_updaters.append(func() -> void:
		button.text = Lang.t(PlayerProfile.COLORS[PlayerProfile.name_color][0])
		button.add_theme_color_override("font_color", PlayerProfile.color_of(PlayerProfile.name_color)))
	return _row("Name Color", button,
		func() -> bool: return PlayerProfile.name_color == 0,
		func() -> void:
			PlayerProfile.name_color = 0
			PlayerProfile.save_profile()
			Net.send_look())


func _skin_row() -> Control:
	var button := _make_button("Choose Skin...", _choose_skin)
	return _row("Skin", button,
		func() -> bool: return not FileAccess.file_exists(PlayerProfile.SKIN_PATH),
		func() -> void:
			PlayerProfile.reset_skin()
			_skin_error = "")


func _choose_skin() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.png ; PNG"])
	dialog.use_native_dialog = true
	dialog.title = Lang.t("Choose Skin...")
	dialog.file_selected.connect(func(path: String) -> void:
		var error := PlayerProfile.load_skin_file(path)
		_skin_error = Lang.t(error) if error != "" else ""
		refresh()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


## The texture packs: the ones on first (framed, numbered: the first one's
## files win, then the next one's, then the game's), with arrows to move
## them; then the others. Clicking a pack puts it on (on top) or off; the
## game's own textures ("Default") are always under them. Used from the
## next start.
func _texture_pack_list() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2 * P)
	var on := Settings.texture_packs.duplicate()
	var there := TexturePacks.names()
	for pack in on.duplicate():
		if not there.has(pack):
			on.remove_at(on.find(pack)) # (taken out of the folder)
	var change := func(list: PackedStringArray) -> void:
		Settings.set_texture_packs(list)
		show_category("texture_packs")
	for i in on.size():
		var pack := on[i]
		var row := _pack_row(pack, true, func() -> void:
			var list := on.duplicate()
			list.remove_at(i)
			change.call(list))
		row.get_child(1).text = "%d. %s" % [i + 1, row.get_child(1).text]
		var arrows := HBoxContainer.new()
		arrows.anchor_left = 1.0
		arrows.anchor_right = 1.0
		arrows.anchor_top = 0.5
		arrows.anchor_bottom = 0.5
		arrows.offset_left = -(ROW_HEIGHT * 2 + 5 * P)
		arrows.offset_right = -3 * P
		arrows.offset_top = -ROW_HEIGHT / 2.0
		arrows.offset_bottom = ROW_HEIGHT / 2.0
		arrows.add_theme_constant_override("separation", 2 * P)
		for step in [-1, 1]:
			var to: int = i + step
			var arrow := _make_button("▲" if step < 0 else "▼", func() -> void:
				var list := on.duplicate()
				list[i] = list[to]
				list[to] = pack
				change.call(list))
			arrow.custom_minimum_size = Vector2(ROW_HEIGHT, ROW_HEIGHT)
			arrow.disabled = to < 0 or to >= on.size()
			arrow.tooltip_text = Lang.t("Higher: its files win") if step < 0 else Lang.t("Lower")
			arrows.add_child(arrow)
		row.add_child(arrows)
		row.get_child(1).offset_right = -(ROW_HEIGHT * 2 + 7 * P)
		column.add_child(row)
	for pack in there:
		if on.has(pack):
			continue
		column.add_child(_pack_row(pack, false, func() -> void:
			var list := PackedStringArray([pack])
			list.append_array(on)
			change.call(list)))
	column.add_child(_pack_row("", on.is_empty(), func() -> void: change.call(PackedStringArray())))
	var note := Label.new()
	note.text = "Click a pack to put it on or off; several can be on: the higher one's files win, the game's fill in the rest. Used from the next start. Beta 1.7.3 texture packs (.zip or a folder) go into the pack folder."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", DIM_TEXT)
	column.add_child(note)
	column.add_child(_wide_button("Open Pack Folder", func() -> void:
		DirAccess.make_dir_recursive_absolute(TexturePacks.folder)
		OS.shell_open(ProjectSettings.globalize_path(TexturePacks.folder))))
	return column


func _pack_row(pack: String, picked: bool, on_pressed: Callable) -> Control:
	const PACK_ICON := 32 * P
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, PACK_ICON + 4 * P)
	button.flat = not picked
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_pressed)
	var icon := TextureRect.new()
	icon.texture = TexturePacks.icon(pack)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.position = Vector2(2, 2) * P
	icon.size = Vector2(PACK_ICON, PACK_ICON)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	var text := Label.new()
	text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var about := TexturePacks.description(pack) if pack != "" else Lang.t("The default look of Voxel Engine")
	text.text = (Lang.t("Default") if pack == "" else pack) + ("\n" + about if about != "" else "")
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left = PACK_ICON + 6 * P
	text.offset_top = 3 * P
	text.offset_right = -2 * P
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(text)
	return button


## The languages, the current one marked; a click switches at once.
func _language_list() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2 * P)
	var current: int = Settings.get_value("language")
	for i in Lang.all().size():
		var language_name: String = Lang.all()[i][1]
		var button := _wide_button(("> %s <" % language_name) if i == current else language_name, func() -> void:
			Settings.set_value("language", i)
			menu.replace(OptionsScreen.new("language"))) # rebuilt in the new language
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		column.add_child(button)
	return column


func _wide_button(text: String, on_pressed: Callable) -> Button:
	var button := _make_button(text, on_pressed)
	button.custom_minimum_size.y = ROW_HEIGHT
	return button


func _group_header(group_name: String, content: Control) -> Control:
	var header := GroupHeader.new()
	header.text = group_name
	header.folded = not content.visible
	header.custom_minimum_size.y = HEADER_HEIGHT
	header.pressed.connect(func() -> void:
		content.visible = not content.visible
		header.folded = not content.visible
		_folded[group_name] = header.folded
		header.queue_redraw())
	return header


# --- Sidebar -------------------------------------------------------------------

func _category_button(id: String, text: String, icon_name: String) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = _category_icon(icon_name)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", ICON_SIZE)
	button.add_theme_constant_override("h_separation", 4 * P)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = ROW_HEIGHT
	button.pressed.connect(func() -> void: show_category(id))
	_sidebar_buttons[id] = button
	return button


## Selected: white text on a dark framed box; others gray, yellow on hover.
func _style_category_button(button: Button, selected: bool) -> void:
	var box := StyleBoxFlat.new()
	box.set_content_margin_all(2 * P)
	box.content_margin_left = 3 * P
	if selected:
		box.bg_color = Color(0, 0, 0, 0.45)
		box.border_color = Color(1, 1, 1, 0.6)
		box.set_border_width_all(P)
	else:
		box.bg_color = Color(0, 0, 0, 0)
	var hover := box.duplicate() as StyleBoxFlat
	if not selected:
		hover.bg_color = Color(1, 1, 1, 0.08)
	for state in ["normal", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("hover_pressed", hover)
	var color := UiTheme.TITLE_COLOR if selected else DIM_TEXT
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_pressed_color", color)
	button.add_theme_color_override("font_hover_color", UiTheme.TITLE_COLOR if selected else UiTheme.HOVER_TEXT_COLOR)


## A category's picture: a block or item icon like in the inventory, or the
## player's face (with the hat layer).
func _category_icon(icon_name: String) -> Texture2D:
	if icon_name == "@head":
		var skin := PlayerProfile.skin_texture()
		if skin == null:
			return null
		var image := skin.get_image()
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		var face := image.get_region(Rect2i(8, 8, 8, 8))
		face.blend_rect(image, Rect2i(40, 8, 8, 8), Vector2i.ZERO)
		return ImageTexture.create_from_image(face)
	if not Items.has_name(icon_name):
		return null
	return BlockIcons.get_icon(Items.id_of(icon_name))


## The small "reset" arrow (white; tinted by the button's icon colors).
static func _make_reset_icon() -> Texture2D:
	const SHAPE := [
		"X.XXX..",
		"XX...X.",
		"XXX...X",
		"......X",
		"X.....X",
		".X...X.",
		"..XXX..",
	]
	var image := Image.create(SHAPE[0].length() * P, SHAPE.size() * P, false, Image.FORMAT_RGBA8)
	for y in SHAPE.size():
		for x in (SHAPE[y] as String).length():
			if SHAPE[y][x] == "X":
				image.fill_rect(Rect2i(x * P, y * P, P, P), Color.WHITE)
	return ImageTexture.create_from_image(image)


## A setting's row: the name on the left, the control on the right, the
## reset arrow before it and a thin line between.
class SettingRow:
	extends Container

	const P := UiTheme.PIXEL
	const GAP := 4 * P
	const RESET_SLOT := 12 * P
	## The control's width: wide, or less in a narrow list.
	const CONTROL_WIDTH := 110 * P
	const NARROW_CONTROL_WIDTH := 76 * P

	var label: Label
	var reset: Button
	var control: Control

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			_arrange()
			queue_redraw()

	func _get_minimum_size() -> Vector2:
		return Vector2(0, UiTheme.BUTTON_HEIGHT)

	func _arrange() -> void:
		var h := size.y
		var width := CONTROL_WIDTH if size.x >= 260 * P else NARROW_CONTROL_WIDTH
		var control_x := size.x - width
		fit_child_in_rect(control, Rect2(control_x, 0, width, h))
		if reset:
			var icon := reset.get_combined_minimum_size()
			fit_child_in_rect(reset, Rect2(control_x - RESET_SLOT - P, (h - icon.y) / 2.0, RESET_SLOT, icon.y))
		var room := control_x - RESET_SLOT - GAP * 2
		var text_width := label.get_theme_font("font").get_string_size(tr(label.text),
			HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x + P * 2
		fit_child_in_rect(label, Rect2(0, 0, minf(text_width, room), h))
		if text_width > room:
			label.tooltip_text = label.text
		set_meta("line", Vector2(minf(text_width, room) + GAP, control_x - RESET_SLOT - GAP))

	func _draw() -> void:
		var line: Vector2 = get_meta("line", Vector2.ZERO)
		if line.y - line.x > P * 2:
			draw_rect(Rect2(line.x, floorf(size.y / 2.0), line.y - line.x, P), OptionsScreen.LINE_COLOR)


## A group's header: a small triangle (down when open, right when folded)
## and the name; a click folds the group.
class GroupHeader:
	extends Button

	var folded := false

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		var box := StyleBoxEmpty.new()
		box.content_margin_left = 10 * UiTheme.PIXEL
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			add_theme_stylebox_override(state, box)
		add_theme_color_override("font_color", OptionsScreen.DIM_TEXT)

	func _draw() -> void:
		var p := float(UiTheme.PIXEL)
		var c := Vector2(4 * p, floorf(size.y / 2.0))
		var color := UiTheme.HOVER_TEXT_COLOR if is_hovered() else OptionsScreen.DIM_TEXT
		var points: PackedVector2Array
		if folded:
			points = [c + Vector2(-p, -3 * p), c + Vector2(2 * p, 0), c + Vector2(-p, 3 * p)]
		else:
			points = [c + Vector2(-3 * p, -p), c + Vector2(3 * p, -p), c + Vector2(0, 2 * p)]
		draw_colored_polygon(points, color)
