class_name BlockMaterials
extends RefCounted
## Builds the block tile Texture2DArray from the atlas and one material per
## render layer (Blocks.Layer). Shared by all chunks.
## The selected shader pack (ShaderPacks) decides the shaders: Classic
## (lighting like the original game) or the dynamic, lit ones; switching
## packs swaps the shaders of these shared materials, so every chunk
## follows at once.
##
## A texture array instead of sampling the atlas directly: no bleeding between
## neighboring tiles at mip levels, and tiles can repeat across merged faces
## (needed for greedy meshing later).

const TILE_SIZE := 16

const SHADERS := {
	Blocks.Layer.OPAQUE: preload("res://shaders/block_opaque.gdshader"),
	Blocks.Layer.CUTOUT: preload("res://shaders/block_cutout.gdshader"),
	Blocks.Layer.TRANSLUCENT: preload("res://shaders/block_translucent.gdshader"),
}
const CLASSIC_SHADERS := {
	Blocks.Layer.OPAQUE: preload("res://shaders/block_classic_opaque.gdshader"),
	Blocks.Layer.CUTOUT: preload("res://shaders/block_classic_cutout.gdshader"),
	Blocks.Layer.TRANSLUCENT: preload("res://shaders/block_classic_translucent.gdshader"),
}

static var _materials: Array[ShaderMaterial] = []
## The materials that draw color (for translucent blocks: the second pass).
static var _color_materials: Array[ShaderMaterial] = []
static var _tiles: Texture2DArray


static func get_material(layer: int) -> ShaderMaterial:
	if _materials.is_empty():
		_build()
	return _materials[layer]


## The shared tile array (animated textures write into it).
static func tiles() -> Texture2DArray:
	if _materials.is_empty():
		_build()
	return _tiles


static func _build() -> void:
	_tiles = build_tile_array(Blocks.ATLAS_PATH)
	for layer in Blocks.LAYER_COUNT:
		var material := ShaderMaterial.new()
		material.shader = SHADERS[layer]
		material.set_shader_parameter("tiles", _tiles)
		_color_materials.append(material)
		if layer == Blocks.Layer.TRANSLUCENT:
			# Depth first, then color: see block_translucent_depth.gdshader.
			var depth := ShaderMaterial.new()
			depth.shader = preload("res://shaders/block_translucent_depth.gdshader")
			depth.next_pass = material
			material = depth
		_materials.append(material)
	# Light and AO constants come from ChunkMesher (one place for both).
	set_parameter("ao_levels", ChunkMesher.ao_levels())
	set_parameter("shadow_contrast", ChunkMesher.SHADOW_CONTRAST)
	apply_pack(ShaderPacks.current)
	ShaderPacks.changed.connect(func() -> void: apply_pack(ShaderPacks.current))


## Uses the shaders and block options of a shader pack.
static func apply_pack(pack: ShaderPack) -> void:
	if pack == null or _color_materials.is_empty():
		return
	var classic := pack.base == ShaderPack.Base.CLASSIC
	for layer in Blocks.LAYER_COUNT:
		var material := _color_materials[layer]
		material.shader = CLASSIC_SHADERS[layer] if classic else SHADERS[layer]
		material.set_shader_parameter("tiles", _tiles)
		material.set_shader_parameter("ao_levels", ChunkMesher.ao_levels())
		material.set_shader_parameter("shadow_contrast", ChunkMesher.SHADOW_CONTRAST)
	if classic:
		set_parameter("face_shading", pack.value("face_shading"))
	else:
		set_parameter("specular_strength", 1.0 if pack.value("water_shine") else 0.0)


## Sets a shader parameter on every block material (unknown names are
## ignored by shaders that don't have them).
static func set_parameter(parameter: String, value: Variant) -> void:
	for material in _color_materials:
		material.set_shader_parameter(parameter, value)


## Slices the atlas into TILE_SIZE tiles; layer index = atlas tile index.
static func build_tile_array(atlas_path: String) -> Texture2DArray:
	var atlas: Image = TexturePacks.load_texture(atlas_path).get_image()
	if atlas.is_compressed():
		atlas.decompress()
	atlas.convert(Image.FORMAT_RGBA8)

	var per_row := atlas.get_width() / TILE_SIZE
	var rows := atlas.get_height() / TILE_SIZE
	var images: Array[Image] = []
	for row in rows:
		for column in per_row:
			var tile := atlas.get_region(Rect2i(column * TILE_SIZE, row * TILE_SIZE, TILE_SIZE, TILE_SIZE))
			tile.generate_mipmaps()
			images.append(tile)

	var array := Texture2DArray.new()
	array.create_from_images(images)
	return array
