class_name BlockIcons
extends RefCounted
## Inventory icons of blocks, rendered like the classic game: the block
## mesh (the same one the world uses) seen from above at an isometric angle
## through an orthographic camera, with fixed face shading (top bright,
## south face on the left, east face on the right). Rasterized by the GPU at
## exactly the pixel size of a slot on screen, so texture pixels stay sharp
## and even at any GUI scale.
##
## Each icon is a small SubViewport that renders once; its texture stays
## valid afterwards. Icons are cached per block and re-made when the GUI
## scale changes.

## Ortho camera height in blocks: the cube (1.57 high at this angle) nearly
## fills the icon.
const VIEW_SIZE := 1.65
## Slot size in UI units.
const SLOT := 16 * UiTheme.PIXEL

static var _cache := {} # id -> Texture2D
static var _holder: Node
static var _pixels := 0
static var _material: ShaderMaterial


static func get_icon(id: int) -> Texture2D:
	if id == Blocks.AIR:
		return null
	if not Items.is_block(id):
		return Items.icon(id) # flat items: their items.png tile
	if Blocks.shape_table[id] == BlockType.Shape.CROSS or Blocks.get_type(id).flat_item:
		return _flat_icon(id) # plants: their picture, like the classic game
	var pixels := icon_pixels()
	if pixels != _pixels:
		clear()
		_pixels = pixels
	if not _cache.has(id):
		_cache[id] = _render(id, pixels)
	return _cache[id]


## Icon size in screen pixels: a slot (16 texture pixels) at the GUI scale.
static func icon_pixels() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var scale := tree.root.content_scale_factor if tree else 1.0
	return maxi(roundi(SLOT * scale), 16)


## Drops cached icons (GUI scale changed, atlas replaced).
static func clear() -> void:
	_cache.clear()
	if is_instance_valid(_holder):
		_holder.queue_free()
	_holder = null


## A plant's tile from the block atlas, colored like in the world.
static func _flat_icon(id: int) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var atlas: Image = (load(Blocks.ATLAS_PATH) as Texture2D).get_image()
	if atlas.is_compressed():
		atlas.decompress()
	var tile := Blocks.face_tiles[id * 6 + 2]
	var image := atlas.get_region(Rect2i((tile % 16) * 16, (tile / 16) * 16, 16, 16))
	image.convert(Image.FORMAT_RGBA8)
	var block := Blocks.get_type(id)
	if block.biome_tint != 0:
		for y in 16:
			for x in 16:
				image.set_pixel(x, y, image.get_pixel(x, y) * Color(block.tint, 1.0))
	_cache[id] = ImageTexture.create_from_image(image)
	return _cache[id]


static func _render(id: int, pixels: int) -> Texture2D:
	if not is_instance_valid(_holder):
		_holder = Node.new()
		_holder.name = "BlockIcons"
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_holder)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(pixels, pixels)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = VIEW_SIZE
	camera.near = 0.1
	camera.far = 10.0
	viewport.add_child(camera)
	# 45 degrees around, 30 degrees down: top, +Z (left) and +X (right) faces.
	var center := Vector3(0.5, 0.5, 0.5)
	var pitch := deg_to_rad(30.0)
	var direction := Vector3(sin(PI / 4) * cos(pitch), sin(pitch), cos(PI / 4) * cos(pitch))
	camera.look_at_from_position(center + direction * 4.0, center, Vector3.UP)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _block_mesh(id)
	viewport.add_child(mesh_instance)
	_holder.add_child(viewport)
	return viewport.get_texture()


static func _block_mesh(id: int) -> ArrayMesh:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://shaders/block_icon.gdshader")
		_material.set_shader_parameter("tiles",
			BlockMaterials.tiles())
	return ChunkMesher.block_mesh(id, _material)
