class_name HelpScreen
extends MenuScreen
## "Help & News" from the title screen, laid out like Options: the sections
## with their pictures on the left, the chosen one's text on the right (it
## wraps, scrolls and can be selected and copied), Done at the bottom.
##
## Sections: What's New (CHANGELOG.md, read at runtime; it is exported with
## the game), Features, Play Together (hosting on LAN and over the
## internet), Controls (the current keys) and Game Folder (what is kept
## where, with a button that opens it).

const P := UiTheme.PIXEL
const CHANGELOG := "res://CHANGELOG.md"
const HEADING_COLOR := "ffffa0"
const SUBHEADING_COLOR := "a0a0a0"
const CODE_COLOR := "a0c8ff"
const KEY_COLOR := "ffffa0"
## The sidebar in a narrow window (a bit wider than Options': the names
## are longer and the text needs less room).
const NARROW_SIDEBAR_WIDTH := 96 * P
const ICONS_ONLY_WIDTH := 24 * P

## [id, English name, icon: block/item name]
const SECTIONS := [
	["news", "What's New", "paper"],
	["features", "Features", "diamond"],
	["together", "Play Together", "cake"],
	["controls", "Controls", "piston"],
	["folder", "Game Folder", "chest"],
]

## Section texts: [kind, English text]. Kinds: "h" heading, "p" paragraph,
## "li" bullet, "step" numbered step, "file" a name and what it is.
const FEATURES := [
	["h", "Worlds"],
	["li", "World types: Default (Beta 1.7.3 terrain, 128 blocks high), Tall Mountains, Floating Islands, Island and Debug Mode (every block laid out in rows)."],
	["li", "Game modes: Survival, Creative and Hardcore (Hard difficulty, no cheats, one life: on death the world is deleted)."],
	["li", "Bonus Chest: a chest with wood, wooden tools, apples and bread next to the spawn."],
	["li", "Day and night with moon phases, rain and snow, 3D clouds, smooth lighting and far terrain."],
	["h", "Playing together"],
	["li", "Open any world to your network from the pause menu: friends on the same network see it in the Multiplayer list."],
	["li", "Over the internet: an invite code (like VE-XXXX-XXXX) that a friend pastes into Direct Connect."],
	["li", "Create Server: a server for friends in the background, started from Multiplayer; or a dedicated server with the start-server files next to the game."],
	["li", "Chat (T), the player list (Tab), shared chests, furnaces, signs, beds and creatures; skins and name colors."],
	["h", "Commands"],
	["li", "Press / to type a command; /help lists them all, Tab completes names and arguments."],
	["li", "Target selectors @p, @a, @r, @s and @e with filters (type, distance, limit and more), relative ~ and local ^ coordinates."],
	["li", "/give, /summon, /kill, /tp, /time, /weather, /gamemode, /gamerule, /difficulty, /setblock, /fill, /clone, /seed, /setworldspawn, /tick, /say and /execute (as, at, positioned, facing, if, unless, run)."],
	["h", "Look and sound"],
	["li", "World Diorama (F6): the land around you as a miniature you can turn, zoom and take a picture of."],
	["li", "Texture packs from Beta 1.7.3 (.zip) and shader packs: Classic lighting or Dynamic Lighting with the sun's shadows."],
	["li", "Sounds like Beta's: footsteps, the echo in caves (stone rings, wool soaks it up), muffled sound under water and the surf by the sea."],
	["h", "Life in the world"],
	["li", "Achievements and statistics for each world (pause menu)."],
	["li", "Breeding: feed two animals their food and they have a baby; animals follow you while you hold it."],
	["li", "Monsters hide from the sun in the shade, hurt animals panic, sneaking players are noticed later."],
]

const TOGETHER := [
	["p", "Three ways, from the quickest to the biggest:"],
	["h", "1. Open to LAN"],
	["step", "In your world press Esc, click Open to LAN, then Start LAN World."],
	["step", "Friends on the same network see it in Multiplayer. Over the internet: turn on Allow Internet Access and send them the invite code (Invite Friends, or /invite)."],
	["p", "The world is open while you play in it."],
	["h", "2. Create Server"],
	["step", "Multiplayer > Create Server: choose a world, a password if you like, Start Server."],
	["step", "The game starts a server in the background and joins it. Friends join it the same way (My Server shows the code and the addresses)."],
	["p", "When you leave, the game asks whether to stop the server (the world is saved)."],
	["h", "3. A dedicated server"],
	["step", "Next to the game are start-server files: start-server.bat (Windows), start-server.command (macOS), start-server.sh (Linux). Start it: no window, the world runs on its own. Type stop in it to save and stop."],
	["step", "Its settings are in server.properties next to the game (made on the first start): the world, the port, a password, the whitelist, the most players."],
	["step", "For the internet: open UDP ports 25565 and 25566 on the router (or upnp=true). A domain name (your own, or a free one from DuckDNS) goes in public-address: friends then connect to the name."],
	["p", "Everything is explained in SERVER.md next to the game."],
	["h", "If friends can't connect"],
	["p", "The Disconnected screen shows why and a code (like E402): tell it when asking for help. If the router can't open the port, install Radmin VPN or ZeroTier on both computers, join one network in it and play as on LAN."],
	["p", "A slow connection only shows Bad connection in the corner: the game waits for it, nobody is kicked for lag."],
]

const FOLDER_INTRO := "Everything the game keeps is in one folder:"
## [name, English description]
const FOLDER_FILES := [
	["saves", "Your worlds, a folder each."],
	["texturepacks", "Texture packs (.zip files or folders)."],
	["shaderpacks", "Your shader packs and the shader settings."],
	["screenshots", "Screenshots and diorama pictures."],
	["mods", "For mods: they are not supported yet, they are planned."],
	["skins", "Your own skin."],
	["settings.cfg", "The options and the keys."],
	["player.cfg", "Your name, its color and the skin."],
	["multiplayer.cfg, servers.cfg", "The multiplayer name and the server list."],
	["server.cfg, bans.cfg", "Your server's settings and bans."],
	["server", "The settings and the log of the server Create Server starts."],
	["ops.cfg, whitelist.cfg, banned-ips.cfg", "Your server's operators, whitelist and banned addresses."],
	["window.cfg", "The window's size and place."],
	["logs", "The game's logs (useful when something goes wrong)."],
]
const FOLDER_NOTE := "Close the game before copying or deleting worlds."

## The section shown last (opening the screen again shows it).
static var _last_section := "news"

var _section := ""
var _body: HBoxContainer
var _side_scroll: ScrollContainer
var _sidebar_buttons := {} # id -> Button
var _content: VBoxContainer


func _init(section: String = "") -> void:
	title = "Help & News"
	_section = section if section != "" else _last_section


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.35)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.offset_top = -4 * P
		shade.offset_bottom = 4 * P
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(shade)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", OptionsScreen.SIDEBAR_GAP)
	band.add_child(_body)
	band.resized.connect(func() -> void: _layout(band))

	_side_scroll = ScrollContainer.new()
	_side_scroll.custom_minimum_size.x = OptionsScreen.SIDEBAR_WIDTH
	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_side_scroll)
	var sidebar := VBoxContainer.new()
	sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sidebar.add_theme_constant_override("separation", P)
	_side_scroll.add_child(sidebar)

	var scroll := ScrollContainer.new()
	list_area = scroll # Menu draws the darker dirt band behind it
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var padding := MarginContainer.new() # (room for the scroll bar)
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.add_theme_constant_override("margin_left", 2 * P)
	padding.add_theme_constant_override("margin_right", 6 * P)
	padding.add_theme_constant_override("margin_top", 2 * P)
	padding.add_theme_constant_override("margin_bottom", 4 * P)
	scroll.add_child(padding)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 4 * P)
	padding.add_child(_content)

	_bottom = VBoxContainer.new()
	_bottom.add_theme_constant_override("separation", ROW_GAP)
	var bottom_center := CenterContainer.new()
	bottom_center.add_child(_bottom)
	layout.add_child(bottom_center)
	add_done_button()

	for entry: Array in SECTIONS:
		sidebar.add_child(_section_button(entry[0], entry[1], entry[2]))
	if not _sidebar_buttons.has(_section):
		_section = "news"
	show_section(_section)


## Centers the sidebar and text like Options; a narrow window gets a
## narrower sidebar, a very narrow one only the pictures.
func _layout(band: Control) -> void:
	var icons_only := band.size.x < 300 * P
	if icons_only:
		_side_scroll.custom_minimum_size.x = ICONS_ONLY_WIDTH
	else:
		_side_scroll.custom_minimum_size.x = OptionsScreen.SIDEBAR_WIDTH if band.size.x >= 400 * P else NARROW_SIDEBAR_WIDTH
	for entry: Array in SECTIONS:
		var button: Button = _sidebar_buttons[entry[0]]
		button.text = "" if icons_only else entry[1]
		button.tooltip_text = entry[1] if icons_only else ""
	var width := minf(band.size.x - 2.0 * OptionsScreen.SIDE_MARGIN,
		OptionsScreen.SIDEBAR_WIDTH + OptionsScreen.SIDEBAR_GAP + OptionsScreen.MAX_LIST_WIDTH)
	_body.position = Vector2(floorf((band.size.x - width) / 2.0), 0)
	_body.size = Vector2(width, band.size.y)


## Shows a section's text on the right.
func show_section(id: String) -> void:
	_section = id
	_last_section = id
	for key: String in _sidebar_buttons:
		_style_section_button(_sidebar_buttons[key], key == id)
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	match id:
		"news":
			_content.add_child(_text(changelog_entries()))
		"features":
			_content.add_child(_text(_translated(FEATURES)))
		"together":
			_content.add_child(_text(_translated(TOGETHER)))
		"controls":
			_content.add_child(_text(controls_entries()))
			_content.add_child(_wide_button("Change Keys...", func() -> void: menu.push(OptionsScreen.new("controls"))))
		"folder":
			_content.add_child(_text(folder_entries()))
			_content.add_child(_wide_button("Open Game Folder", GameFolder.open))
	(list_area as ScrollContainer).scroll_vertical = 0


## Coming back from Options: the keys may have changed.
func refresh() -> void:
	if _section == "controls" and _content:
		show_section(_section)


# --- What each section says ----------------------------------------------------

static func _translated(entries: Array) -> Array:
	var result := []
	for entry: Array in entries:
		result.append([entry[0], Lang.t(entry[1])])
	return result


## The versions in CHANGELOG.md, newest first, with their Added / Changed /
## Fixed / Removed lists (an empty Unreleased is left out). The entries are
## in English like the file; "`code`" is colored.
static func changelog_entries() -> Array:
	var result := [["p", "[color=#%s]%s[/color]" % [SUBHEADING_COLOR, _escape(Lang.t("The list of changes is kept in English."))], true]]
	var file := FileAccess.open(CHANGELOG, FileAccess.READ)
	if file == null:
		result.append(["p", Lang.t("The list of changes is not available.")])
		return result
	var started := false
	var version_at := -1 # index of the last version's heading
	for raw: String in file.get_as_text().split("\n"):
		var line := raw.strip_edges()
		if raw.begins_with("## "):
			if version_at >= 0 and version_at == result.size() - 1:
				result.pop_back() # a version with nothing in it
			started = true
			var version := line.substr(3).replace("[", "").replace("]", "")
			if version == "Unreleased":
				version = Lang.t("Unreleased")
			version_at = result.size()
			result.append(["h", version])
		elif not started or line == "":
			continue
		elif raw.begins_with("### "):
			result.append(["sub", Lang.t(line.substr(4))])
		elif line.begins_with("- "):
			result.append(["li2" if raw.begins_with(" ") else "li", _markdown(line.substr(2)), true])
		elif not result.is_empty() and result[-1].size() > 2:
			result[-1][1] += " " + _markdown(line) # a wrapped line of the item
	if version_at == result.size() - 1:
		result.pop_back()
	return result


## Every key binding by group with its current key, and the mouse.
static func controls_entries() -> Array:
	var result := [["h", Lang.t("Mouse")]]
	for pair: Array in [["Break blocks, attack", "Left Button"], ["Place blocks, use items", "Right Button"],
			["Pick the block you look at", "Middle Button"], ["Change the hotbar slot", "Wheel"],
			["Pause menu, close a screen", "Esc"], ["Fly in Creative", "Space twice"]]:
		result.append(_key_row(Lang.t(pair[0]), Lang.t(pair[1])))
	var category := ""
	for binding: Array in KeyBindings.ACTIONS:
		if binding[2] != category:
			category = binding[2]
			result.append(["h", Lang.t(category)])
		result.append(_key_row(Lang.t(binding[1]), KeyBindings.key_name(binding[0])))
	return result


static func _key_row(action: String, key: String) -> Array:
	return ["row", _escape(action), "[color=#%s]%s[/color]" % [KEY_COLOR, _escape(key)]]


## What lives where in the game's folder.
static func folder_entries() -> Array:
	var result := [["p", Lang.t(FOLDER_INTRO)],
		["p", "[color=#%s]%s[/color]" % [CODE_COLOR, _escape(GameFolder.path())], true]]
	for pair: Array in FOLDER_FILES:
		result.append(["p", "[color=#%s]%s[/color]: %s" % [KEY_COLOR, _escape(pair[0]), _escape(Lang.t(pair[1]))], true])
	result.append(["p", Lang.t(FOLDER_NOTE)])
	return result


# --- Text ----------------------------------------------------------------------

## The text of entries as one selectable, wrapping label. An entry's third
## item (true) says its text is BBCode already.
static func entries_bbcode(entries: Array) -> String:
	const OPEN := {"ul": "[ul bullet=-]", "ol": "[ol type=1]", "table": "[table=2]"}
	const BLOCKS := {"li": "ul", "li2": "ul", "step": "ol", "row": "table"}
	var result := ""
	var block := "" # the open list or table
	for i in entries.size():
		var entry: Array = entries[i]
		var kind: String = entry[0]
		var want: String = BLOCKS.get(kind, "")
		if want != block:
			if block != "":
				result = result.trim_suffix("\n") + "[/%s]\n" % block
			if want != "":
				result += OPEN[want]
			block = want
		if kind == "row":
			result += "[cell expand=1]%s[/cell][cell]%s[/cell]" % [entry[1], entry[2]]
			continue
		var text: String = entry[1] if entry.size() > 2 and entry[2] else _escape(entry[1])
		match kind:
			"h":
				result += ("\n" if i > 0 else "") + "[color=#%s]%s[/color]\n" % [HEADING_COLOR, text]
			"sub":
				result += "[color=#%s]%s[/color]\n" % [SUBHEADING_COLOR, text]
			"li2":
				result += "[ul bullet=-]%s[/ul]\n" % text
			_:
				result += text + "\n"
	if block != "":
		result = result.trim_suffix("\n") + "[/%s]" % block
	return result.strip_edges(false, true)


func _text(entries: Array) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = true
	label.context_menu_enabled = true
	label.focus_mode = Control.FOCUS_CLICK
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # (translated above)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("default_color", UiTheme.TEXT_COLOR)
	label.add_theme_color_override("font_shadow_color", UiTheme.SHADOW_COLOR)
	label.add_theme_color_override("selection_color", Color(0.2, 0.3, 0.8, 0.6))
	label.add_theme_constant_override("shadow_offset_x", P)
	label.add_theme_constant_override("shadow_offset_y", P)
	label.add_theme_constant_override("line_separation", P)
	label.add_theme_constant_override("paragraph_separation", 3 * P)
	label.add_theme_constant_override("table_h_separation", 6 * P)
	label.add_theme_constant_override("table_v_separation", P)
	label.text = entries_bbcode(entries)
	return label


## Text shown as is (BBCode's "[" escaped).
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


## A changelog line: "`code`" colored, "**" dropped.
static func _markdown(text: String) -> String:
	var parts := _escape(text.replace("**", "")).split("`")
	for i in range(1, parts.size(), 2):
		parts[i] = "[color=#%s]%s[/color]" % [CODE_COLOR, parts[i]]
	return "".join(parts)


func _wide_button(text: String, on_pressed: Callable) -> Button:
	var button := _make_button(text, on_pressed)
	button.custom_minimum_size.y = UiTheme.BUTTON_HEIGHT
	return button


# --- Sidebar -------------------------------------------------------------------

func _section_button(id: String, text: String, icon_name: String) -> Button:
	var button := Button.new()
	button.text = text
	if Items.has_name(icon_name):
		button.icon = BlockIcons.get_icon(Items.id_of(icon_name))
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", OptionsScreen.ICON_SIZE)
	button.add_theme_constant_override("h_separation", 4 * P)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = UiTheme.BUTTON_HEIGHT
	button.pressed.connect(func() -> void: show_section(id))
	_sidebar_buttons[id] = button
	return button


## Selected: white text on a dark framed box; others gray, yellow on hover
## (like Options' categories).
func _style_section_button(button: Button, selected: bool) -> void:
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
	var color := UiTheme.TITLE_COLOR if selected else OptionsScreen.DIM_TEXT
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_pressed_color", color)
	button.add_theme_color_override("font_hover_color", UiTheme.TITLE_COLOR if selected else UiTheme.HOVER_TEXT_COLOR)
