#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

namespace voxel {

// A chunk's mesh arrays and cave-culling connectivity, the same as
// ChunkMesher.pad_blocks() / pad_light() / build() / connectivity() in
// GDScript, in one call. Runs on worker threads: the block tables are set once
// on the main thread (set_tables) and only read by build_chunk.
class NativeMesher : public godot::RefCounted {
	GDCLASS(NativeMesher, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// `tables`: Blocks' tables by name ("is_opaque", "layer", "cull_self",
	// "face_tiles", "face_overlays", "tints", "collides", "liquid",
	// "biome_tint", "random_rotation", "height", "uv_mode", "cull_group",
	// "liquid_level", "shape", "model") and "models" (BlockModel's quads).
	static void set_tables(const godot::Dictionary &tables);
	static bool has_tables();

	// The chunk at `coord` from its blocks, sky light and block light and the
	// 26 neighbors' (Dictionaries Vector3i offset -> array; missing: air, full
	// sky light, no block light). `grass` / `foliage`: the column's colors
	// (empty: the blocks' tints). `smooth`: ChunkMesher.smooth_lighting,
	// `rotate`: ChunkMesher.random_rotation.
	// Returns [surfaces {layer: mesh arrays}, connectivity].
	static godot::Array build_chunk(const godot::Vector3i &coord,
			const godot::PackedInt32Array &center, const godot::Dictionary &neighbors,
			const godot::PackedByteArray &center_light, const godot::Dictionary &neighbor_light,
			const godot::PackedByteArray &center_block_light, const godot::Dictionary &neighbor_block_light,
			const godot::PackedColorArray &grass, const godot::PackedColorArray &foliage,
			int smooth, bool rotate);
};

} // namespace voxel
