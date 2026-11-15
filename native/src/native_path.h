#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>

namespace voxel {

// Pathfinder.find() (A* on the block grid) and the random ticks' picking,
// the same as the GDScript, step by step. Main thread only (it reads the
// world's chunks).
class NativePath : public godot::RefCounted {
	GDCLASS(NativePath, godot::RefCounted)

protected:
	static void _bind_methods();

public:
	// `chunks`: VoxelWorld._chunks (Vector3i -> ChunkData, its `blocks`
	// read once per chunk); the tables are Pathfinder's _solid, _floor,
	// _harmful and Blocks.liquid_table. Returns [visited, x, y, z, ...]: the
	// number of cells searched, then the path's cells (empty if nothing
	// better than standing still).
	static godot::PackedInt32Array find(const godot::Dictionary &chunks, const godot::Vector3i &start,
			const godot::Vector3i &goal, int tall, int max_nodes, const godot::PackedByteArray &solid,
			const godot::PackedByteArray &floor, const godot::PackedByteArray &harmful,
			const godot::PackedByteArray &liquid);

	// Random ticks of a round: `blocks` the chunks' block arrays, `count`
	// tries in each, a block index 0..4095 from a PCG32 stream seeded by
	// `seed`. Returns [chunk, index, ...] for the tries that hit a block
	// that ticks (`ticks`: Blocks.ticks_randomly).
	static godot::PackedInt32Array random_ticks(const godot::Array &blocks, int count,
			const godot::PackedByteArray &ticks, int64_t seed);
};

} // namespace voxel
