class_name WorldIcon
extends RefCounted
## A world's picture in Select World (ours: not in Beta, the modern game has
## one): the middle of the view, square, 64 x 64, in the world's folder
## (icon.png). Taken a few seconds after a new world first shows (Game) and
## again every time the player leaves the world, without the HUD, the hand
## or the menus. Worlds without one show missing_world_icon.png.

const SIZE := 64
const FILE := "icon.png"
const MISSING := "res://assets/textures/extra/unused/missing_world_icon.png"


static func has_icon(save: WorldSave) -> bool:
	return save != null and FileAccess.file_exists(save.path(FILE))


## The world's picture, or the missing one.
static func texture_of(save: WorldSave) -> Texture2D:
	if has_icon(save):
		var image := Image.load_from_file(save.path(FILE))
		if image and not image.is_empty():
			return ImageTexture.create_from_image(image)
	return load(MISSING) as Texture2D


## Takes the picture now (await it): every canvas layer (HUD, menus) and the
## hand hidden for a frame, then shown again.
static func capture(tree: SceneTree, save: WorldSave, hand: Node3D = null) -> void:
	if save == null or save.remote or tree == null:
		return
	var hidden: Array[CanvasLayer] = []
	for layer: CanvasLayer in tree.root.find_children("*", "CanvasLayer", true, false):
		if layer.visible:
			layer.visible = false
			hidden.append(layer)
	# (the hand sets its own visibility every frame from its "hidden" flag)
	var hand_shown := hand != null and hand.visible
	var hand_flag: Variant = hand.get("hidden") if hand else null
	if hand:
		hand.visible = false
		if hand_flag != null:
			hand.set("hidden", true)
	for i in 2:
		await RenderingServer.frame_post_draw
	var image := tree.root.get_viewport().get_texture().get_image()
	for layer in hidden:
		if is_instance_valid(layer):
			layer.visible = true
	if hand and is_instance_valid(hand):
		if hand_flag != null:
			hand.set("hidden", hand_flag)
		hand.visible = hand_shown
	if image == null or image.is_empty():
		return
	var side := mini(image.get_width(), image.get_height())
	var square := image.get_region(Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side))
	square.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	square.save_png(save.path(FILE))
