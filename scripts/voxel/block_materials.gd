class_name BlockMaterials
extends RefCounted
## Builds the block tile Texture2DArray from the atlas and one material per
## render layer (Blocks.Layer). Shared by all chunks.
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

static var _materials: Array[ShaderMaterial] = []


static func get_material(layer: int) -> ShaderMaterial:
	if _materials.is_empty():
		_build()
	return _materials[layer]


static func _build() -> void:
	var tiles := build_tile_array(Blocks.ATLAS_PATH)
	for layer in Blocks.LAYER_COUNT:
		var material := ShaderMaterial.new()
		material.shader = SHADERS[layer]
		material.set_shader_parameter("tiles", tiles)
		_materials.append(material)


## Slices the atlas into TILE_SIZE tiles; layer index = atlas tile index.
static func build_tile_array(atlas_path: String) -> Texture2DArray:
	var atlas: Image = load(atlas_path).get_image()
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
