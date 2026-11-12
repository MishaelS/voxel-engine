#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

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
};

} // namespace voxel
