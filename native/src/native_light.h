#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

namespace voxel {

// A column's sky light and block light, the same as SkyLight.compute_column()
// and BlockLight.compute_column() in GDScript, in one call. Thread-safe (no
// state): called from the light jobs on worker threads.
class NativeLight : public godot::RefCounted {
	GDCLASS(NativeLight, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// `chunks`: 9 arrays (index (dx + 1) * 3 + (dz + 1)) of a column's chunk
	// block arrays (PackedInt32Array, 4096 each), bottom to top; `heights`: the
	// 9 heightmaps (PackedInt32Array, 256); `glowing`: 9 PackedByteArray flags,
	// a chunk has glowing blocks; `opacity` / `emission`: Blocks' tables.
	// Returns [sky, block]: two arrays of the center column's light arrays
	// (PackedByteArray, 4096 each), bottom to top.
	static godot::Array compute_column(const godot::Array &chunks, const godot::Array &heights,
			const godot::Array &glowing, const godot::PackedByteArray &opacity,
			const godot::PackedByteArray &emission);

	// The light around one changed block (VoxelWorld._relight() for sky
	// light, `sky`, or _relight_block_light()), removal and spreading to the
	// end at once. The area is the 3x3 columns around the block's column:
	// `blocks` / `light` are 9 arrays (index (dx + 1) * 3 + (dz + 1)) of 16
	// chunk arrays each, empty where nothing is loaded; `pos` is the block in
	// area coordinates (x, z 16..31). Returns [chunks (PackedInt32Array of
	// c * 16 + k), their new light arrays, PackedInt32Array of bits (dx + 1) * 9
	// + (dy + 1) * 3 + (dz + 1): the chunks whose meshes see the change].
	static godot::Array relight_edit(bool sky, const godot::Vector3i &pos, const godot::Array &blocks,
			const godot::Array &light, const godot::PackedByteArray &opacity,
			const godot::PackedByteArray &emission);

	// relight_edit() for many changed blocks at once (a batch of block
	// changes: a network packet, /fill, an explosion), each in turn, with the
	// arrays passed once: the area is columns_x x columns_z columns (`blocks` /
	// `light` indexed cx * columns_z + cz), `positions` x, y, z triples in area
	// coordinates. Returns the same as relight_edit() (chunks are slots
	// (cx * columns_z + cz) * 16 + k; their masks' bits as there).
	// WorldGenerator.heightmap(): the highest block with opacity > 0 of each
	// of a column's 256 block columns (-1: none), from the column's blocks.
	static godot::PackedInt32Array heightmap(const godot::PackedInt32Array &blocks,
			const godot::PackedByteArray &opacity);

	// ChunkData.count_tickable() for the 16 chunks of a column: [air, tickable,
	// glowing] for each, from Blocks' tables.
	static godot::PackedInt32Array chunk_counts(const godot::PackedInt32Array &blocks,
			const godot::PackedByteArray &ticks, const godot::PackedByteArray &emission);

	static godot::Array relight_edits(bool sky, const godot::PackedInt32Array &positions, int columns_x,
			int columns_z, const godot::Array &blocks, const godot::Array &light,
			const godot::PackedByteArray &opacity, const godot::PackedByteArray &emission);
};

} // namespace voxel
