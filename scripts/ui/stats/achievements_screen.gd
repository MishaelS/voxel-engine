class_name AchievementsScreen
extends MenuScreen
## Achievements like the classic game's map: each one's icon at its place,
## lines to the one it needs first; gotten ones bright, ones that can be
## gotten now plain, the rest dark. Hovering one shows its name and what to
## do. The list scrolls when the map is taller than the window.

const P := UiTheme.PIXEL
const CELL := 28 * P


func _init() -> void:
	title = "Achievements"
	columns = 1


func build() -> void:
	add_list_item(AchievementMap.new())
	var done := 0
	for id: String in Stats.ACHIEVEMENTS:
		if Stats.has(id):
			done += 1
	var label := Label.new()
	label.text = Lang.t("%d of %d achievements") % [done, Stats.ACHIEVEMENTS.size()]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_list_item(label)
	add_done_button()


class AchievementMap extends Control:
	const P := UiTheme.PIXEL
	const CELL := 28 * UiTheme.PIXEL

	var _min := Vector2i(1000, 1000)
	var _max := Vector2i(-1000, -1000)

	func _init() -> void:
		for id: String in Stats.ACHIEVEMENTS:
			var info: Array = Stats.ACHIEVEMENTS[id]
			_min = Vector2i(mini(_min.x, info[4]), mini(_min.y, info[5]))
			_max = Vector2i(maxi(_max.x, info[4]), maxi(_max.y, info[5]))
		custom_minimum_size = Vector2(_max - _min + Vector2i.ONE) * CELL + Vector2(CELL, CELL)
		for id: String in Stats.ACHIEVEMENTS:
			var info: Array = Stats.ACHIEVEMENTS[id]
			var frame := Panel.new()
			var style := StyleBoxFlat.new()
			var state := _state(id)
			style.bg_color = [Color(0.12, 0.12, 0.14), Color(0.35, 0.35, 0.38), Color(0.55, 0.5, 0.2)][state]
			style.border_color = [Color(0.25, 0.25, 0.28), Color(0.7, 0.7, 0.72), Color(1.0, 0.9, 0.3)][state]
			style.set_border_width_all(P)
			frame.add_theme_stylebox_override("panel", style)
			frame.size = Vector2(24, 24) * P
			frame.position = _cell(id) - frame.size / 2.0
			var text := "%s\n%s" % [Lang.t(info[0]), Lang.t(info[1])]
			if state == 0:
				text += "\n" + Lang.t("Requires") + ": " + Lang.t(Stats.ACHIEVEMENTS[info[2]][0])
			frame.tooltip_text = text
			add_child(frame)
			var icon := ItemSlotView.new()
			icon.set_item(Items.id_of(info[3]), 1, false)
			icon.position = Vector2(4, 4) * P
			icon.modulate = Color(0.35, 0.35, 0.35) if state == 0 else Color.WHITE
			frame.add_child(icon)

	## 0 locked (needs another first), 1 can be gotten, 2 gotten.
	func _state(id: String) -> int:
		if Stats.has(id):
			return 2
		return 1 if Stats.can_get(id) else 0

	func _cell(id: String) -> Vector2:
		var info: Array = Stats.ACHIEVEMENTS[id]
		return (Vector2(int(info[4]) - _min.x, int(info[5]) - _min.y) + Vector2(1, 1)) * CELL

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.07, 0.75))
		for id: String in Stats.ACHIEVEMENTS:
			var parent: String = Stats.ACHIEVEMENTS[id][2]
			if parent == "":
				continue
			var color := Color(0.25, 0.25, 0.25)
			if Stats.has(id):
				color = Color(0.45, 0.8, 0.3)
			elif Stats.can_get(id):
				color = Color(0.85, 0.85, 0.85)
			# Lines go across, then up or down, like the game's map.
			var from := _cell(parent)
			var to := _cell(id)
			var corner := Vector2(to.x, from.y)
			draw_line(from, corner, color, P)
			draw_line(corner, to, color, P)
