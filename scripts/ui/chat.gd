class_name Chat
extends Control
## Chat and command line in the style of the classic game.
## T opens the chat, / opens it with "/" typed. Text starting with "/" runs
## a command (Commands.dispatcher), anything else is a chat message.
##
## While typing a command:
## - suggestions for the current word appear above the cursor;
##   Up/Down choose one, Tab inserts it;
## - the rest of the chosen suggestion is shown in gray after the cursor;
## - with nothing to suggest, the expected argument ("<time>") or the
##   parse error is shown instead.
## Up/Down without suggestions browse sent messages; Page Up/Down scroll the
## log; Esc closes. Closed, the chat shows new messages for 10 seconds.

const FONT_SIZE := UiTheme.FONT_SIZE
const LOG_WIDTH := 640.0
const MARGIN := 4.0
const INPUT_HEIGHT := 24.0
const PADDING := 4.0
const VISIBLE_SECONDS := 10.0
const FADE_SECONDS := 1.0
const MAX_MESSAGES := 200
const CLOSED_LINES := 10
const OPEN_LINES := 20
const MAX_SUGGESTIONS := 10
const HISTORY_SIZE := 100
## Bottom edge of the suggestion list / hint, just above the input line.
const POPUP_BOTTOM := -(MARGIN + INPUT_HEIGHT + 2.0)

const KIND_COLORS := {
	CommandSource.MessageKind.INFO: Color("aaaaaa"),
	CommandSource.MessageKind.SUCCESS: Color("ffffff"),
	CommandSource.MessageKind.ERROR: Color("ff5555"),
	CommandSource.MessageKind.CHAT: Color("ffffff"),
}
const SUGGESTION_COLOR := Color("aaaaaa")
const SELECTED_COLOR := Color("ffff55")
const GHOST_COLOR := Color("808080")

## World the commands act on.
@export var world: VoxelWorld
## The player (origin of ~ ~ ~ and target of /tp).
@export var player: Node3D

var source := CommandSource.new()

var _font: Font
var _messages: Array[Dictionary] = [] # {text, kind, time}
var _history := PackedStringArray()
var _history_index := -1
var _draft := ""
var _open := false
var _scroll := 0
var _suggestions := {}
var _selected := 0
var _last_text := ""
var _last_caret := -1
## True after recalling history: no suggestions until the user edits.
var _suggestions_suppressed := false

var _log_panel: PanelContainer
var _log: RichTextLabel
var _input: LineEdit
var _ghost: Label
var _popup: PanelContainer
var _popup_list: VBoxContainer
var _hint: Label


func _ready() -> void:
	source.world = world
	source.origin = player
	source.output = add_message
	_build_ui()
	if player:
		(player as Player).message.connect(func(text: String) -> void:
			add_message(text, CommandSource.MessageKind.INFO))
	add_message(Lang.t("Press T to chat, / to enter a command (Tab completes, /help lists commands)"), CommandSource.MessageKind.INFO)


func is_open() -> bool:
	return _open


# --- Opening / closing -----------------------------------------------------

func open(initial_text: String = "") -> void:
	if _open:
		return
	_open = true
	GameInput.lock()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_input.visible = true
	_input.text = initial_text
	_input.caret_column = initial_text.length()
	_input.grab_focus()
	_history_index = -1
	_scroll = 0
	_selected = 0
	_suggestions_suppressed = false
	_refresh_log()
	_update_suggestions()


func close() -> void:
	if not _open:
		return
	_open = false
	GameInput.unlock()
	_input.release_focus()
	_input.visible = false
	_popup.visible = false
	_hint.visible = false
	_ghost.visible = false
	_refresh_log()


func _unhandled_input(event: InputEvent) -> void:
	if _open:
		return
	if event.is_action_pressed("open_chat"):
		open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_command"):
		open("/")
		get_viewport().set_input_as_handled()


# --- Messages --------------------------------------------------------------

func add_message(text: String, kind: int = CommandSource.MessageKind.CHAT) -> void:
	for line in text.split("\n"):
		_messages.append({"text": line, "kind": kind, "time": _now()})
	while _messages.size() > MAX_MESSAGES:
		_messages.pop_front()
	_refresh_log()


func _submit(text: String) -> void:
	var message := text.strip_edges()
	close()
	if message.is_empty():
		return
	if _history.is_empty() or _history[-1] != message:
		_history.append(message)
		if _history.size() > HISTORY_SIZE:
			_history.remove_at(0)
	if message.begins_with("/"):
		Commands.dispatcher.execute(message, source)
	else:
		add_message("<%s> %s" % [source.name, message], CommandSource.MessageKind.CHAT)


func _process(_delta: float) -> void:
	if _open:
		if _input.text != _last_text or _input.caret_column != _last_caret:
			_update_suggestions()
	elif not _messages.is_empty() and _now() - _messages[-1].time < VISIBLE_SECONDS + FADE_SECONDS + 0.5:
		_refresh_log() # fade out recent messages


func _refresh_log() -> void:
	var lines := PackedStringArray()
	var max_alpha := 0.0
	if _open:
		var end := _messages.size() - _scroll
		for i in range(maxi(end - OPEN_LINES, 0), end):
			lines.append(_format(_messages[i], 1.0))
		max_alpha = 1.0
	else:
		var now := _now()
		for i in range(maxi(_messages.size() - CLOSED_LINES, 0), _messages.size()):
			var age: float = now - _messages[i].time
			var alpha := clampf(1.0 - (age - VISIBLE_SECONDS) / FADE_SECONDS, 0.0, 1.0)
			if alpha > 0.0:
				lines.append(_format(_messages[i], alpha))
				max_alpha = maxf(max_alpha, alpha)
	_log.text = "\n".join(lines)
	_log_panel.visible = not lines.is_empty()
	(_log_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(0, 0, 0, 0.45 * max_alpha)


func _format(message: Dictionary, alpha: float) -> String:
	var color: Color = KIND_COLORS.get(message.kind, Color.WHITE)
	color.a = alpha
	return "[color=#%s]%s[/color]" % [color.to_html(true), (message.text as String).replace("[", "[lb]")]


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- Keys in the input line -------------------------------------------------

func _on_input_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var handled := true
	match event.keycode:
		KEY_ESCAPE:
			close()
		KEY_UP:
			if _popup.visible:
				_select(_selected - 1)
			else:
				_browse_history(-1)
		KEY_DOWN:
			if _popup.visible:
				_select(_selected + 1)
			else:
				_browse_history(1)
		KEY_TAB:
			_accept_suggestion()
		KEY_PAGEUP:
			_scroll = clampi(_scroll + OPEN_LINES / 2, 0, maxi(_messages.size() - OPEN_LINES, 0))
			_refresh_log()
		KEY_PAGEDOWN:
			_scroll = maxi(_scroll - OPEN_LINES / 2, 0)
			_refresh_log()
		_:
			handled = false
	if handled:
		_input.accept_event()


func _browse_history(direction: int) -> void:
	if _history.is_empty():
		return
	if _history_index == -1:
		if direction > 0:
			return
		_draft = _input.text
		_history_index = _history.size()
	_history_index = clampi(_history_index + direction, 0, _history.size())
	var text := _draft if _history_index == _history.size() else _history[_history_index]
	if _history_index == _history.size():
		_history_index = -1
	_input.text = text
	_input.caret_column = text.length()
	_suggestions_suppressed = true # like the classic game: browsing history shows no list


# --- Suggestions -------------------------------------------------------------

func _items() -> PackedStringArray:
	return _suggestions.get("items", PackedStringArray())


func _update_suggestions() -> void:
	_last_text = _input.text
	_last_caret = _input.caret_column
	var text := _input.text
	if not text.begins_with("/") or _suggestions_suppressed:
		_suggestions = {}
		_popup.visible = false
		_hint.visible = false
		_ghost.visible = false
		return
	_suggestions = Commands.dispatcher.suggest(text, _input.caret_column, source)
	_selected = clampi(_selected, 0, maxi(_items().size() - 1, 0))
	_show_suggestions()


func _select(index: int) -> void:
	var count := _items().size()
	if count == 0:
		return
	_selected = posmod(index, count)
	_show_suggestions()


func _accept_suggestion() -> void:
	var items := _items()
	if items.is_empty():
		return
	var text := _input.text
	var start: int = _suggestions.start
	var chosen := items[_selected]
	var caret := _input.caret_column
	_input.text = text.substr(0, start) + chosen + text.substr(caret)
	_input.caret_column = start + chosen.length()
	_selected = 0
	_update_suggestions()


func _show_suggestions() -> void:
	var items := _items()
	var text := _input.text
	var start: int = _suggestions.get("start", text.length())
	var start_x := _text_x(text.substr(0, start))

	# Popup with a window of up to MAX_SUGGESTIONS items around the selection.
	for child in _popup_list.get_children():
		child.queue_free()
	_popup.visible = not items.is_empty()
	if _popup.visible:
		var first := clampi(_selected - MAX_SUGGESTIONS + 1, 0, maxi(items.size() - MAX_SUGGESTIONS, 0))
		for i in range(first, mini(first + MAX_SUGGESTIONS, items.size())):
			var label := Label.new()
			label.text = items[i]
			label.add_theme_color_override("font_color", SELECTED_COLOR if i == _selected else SUGGESTION_COLOR)
			_popup_list.add_child(label)
		_place_above_input(_popup, start_x - PADDING)

	# Expected argument or error when there is nothing to suggest.
	var error: String = _suggestions.get("error", "")
	var usage: String = _suggestions.get("usage", "")
	_hint.visible = items.is_empty() and (error != "" or usage != "")
	if _hint.visible:
		_hint.text = error if error != "" else usage
		_hint.add_theme_color_override("font_color", KIND_COLORS[CommandSource.MessageKind.ERROR] if error != "" else SUGGESTION_COLOR)
		_place_above_input(_hint, start_x - PADDING)

	# Ghost: the rest of the selected suggestion after the cursor.
	_ghost.visible = false
	if not items.is_empty() and _input.caret_column == text.length():
		var typed := text.substr(start)
		var chosen := items[_selected]
		if chosen.to_lower().begins_with(typed.to_lower()) and chosen.length() > typed.length():
			_ghost.text = chosen.substr(typed.length())
			_ghost.offset_left = _text_x(text)
			_ghost.offset_right = _ghost.offset_left
			_ghost.visible = true


## Collapses the control to a point at (x, POPUP_BOTTOM); its minimum size
## then makes it grow up and to the right (see _anchor_bottom_left).
func _place_above_input(control: Control, x: float) -> void:
	control.offset_left = x
	control.offset_right = x
	control.offset_top = POPUP_BOTTOM
	control.offset_bottom = POPUP_BOTTOM


## X position (in this control) where `text` typed in the input line ends.
func _text_x(text: String) -> float:
	return MARGIN + PADDING + _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x


# --- UI construction ---------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_font = UiTheme.font()
	theme = UiTheme.theme()

	# Message log, growing upward from just above the input line.
	_log_panel = PanelContainer.new()
	_log_panel.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.45)))
	# Above the hotbar (22 texture pixels + margins), like the classic game.
	_anchor_bottom_left(_log_panel, MARGIN, -(24 * UiTheme.PIXEL + MARGIN + INPUT_HEIGHT))
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = true
	_log.scroll_active = false
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.custom_minimum_size.x = LOG_WIDTH
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_constant_override("line_separation", 2)
	_log_panel.add_child(_log)
	add_child(_log_panel)

	# Input line across the bottom.
	_input = LineEdit.new()
	_input.anchor_left = 0.0
	_input.anchor_right = 1.0
	_input.anchor_top = 1.0
	_input.anchor_bottom = 1.0
	_input.offset_left = MARGIN
	_input.offset_right = -MARGIN
	_input.offset_top = -(MARGIN + INPUT_HEIGHT)
	_input.offset_bottom = -MARGIN
	_input.max_length = 256
	_input.context_menu_enabled = false
	_input.caret_blink = true
	var input_box := _box(Color(0, 0, 0, 0.5))
	_input.add_theme_stylebox_override("normal", input_box)
	_input.add_theme_stylebox_override("focus", input_box)
	_input.visible = false
	_input.gui_input.connect(_on_input_key)
	_input.text_submitted.connect(_submit)
	_input.text_changed.connect(func(_text: String) -> void:
		_suggestions_suppressed = false
		_selected = 0)
	add_child(_input)

	# Gray completion after the cursor (not clickable, drawn over the input).
	_ghost = Label.new()
	_ghost.add_theme_color_override("font_color", GHOST_COLOR)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.anchor_top = 1.0
	_ghost.anchor_bottom = 1.0
	_ghost.offset_top = -(MARGIN + INPUT_HEIGHT)
	_ghost.offset_bottom = -MARGIN
	_ghost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ghost.visible = false
	add_child(_ghost)

	# Suggestion list and hint line above the input, at the current word.
	_popup = PanelContainer.new()
	_popup.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.85)))
	_anchor_bottom_left(_popup, MARGIN, POPUP_BOTTOM)
	_popup_list = VBoxContainer.new()
	_popup_list.add_theme_constant_override("separation", 0)
	_popup.add_child(_popup_list)
	_popup.visible = false
	add_child(_popup)

	_hint = Label.new()
	_hint.add_theme_stylebox_override("normal", _box(Color(0, 0, 0, 0.85)))
	_anchor_bottom_left(_hint, MARGIN, POPUP_BOTTOM)
	_hint.visible = false
	add_child(_hint)


## Anchors a control to the bottom-left corner so it grows upward.
static func _anchor_bottom_left(control: Control, left: float, bottom: float) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 0.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = left
	control.offset_right = left
	control.offset_top = bottom
	control.offset_bottom = bottom
	control.grow_horizontal = Control.GROW_DIRECTION_END
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func _box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.content_margin_left = PADDING
	box.content_margin_right = PADDING
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	return box
