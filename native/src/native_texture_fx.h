#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <vector>

#include "pcg.h"

namespace voxel {

// The animated block textures' little simulations (FireAnimation,
// LavaAnimation, WaterAnimation), the same steps as their GDScript: one
// object per texture keeps its fields; step() runs one step and returns
// the texture's 16 x 16 RGBA pixels. 20 steps a second each, they were a
// good part of a frame's script time.
class NativeTextureFx : public godot::RefCounted {
	GDCLASS(NativeTextureFx, godot::RefCounted)

public:
	enum Kind { FIRE = 0, LAVA = 1, WATER_STILL = 2, WATER_FLOWING = 3 };

private:
	static constexpr int SIZE = 16;
	static constexpr int FIRE_ROWS = 20;

	int kind = FIRE;
	std::vector<float> current, next, heat, speed;
	Pcg rng{ 1 };

	void step_fire();
	void step_lava();
	void step_water();

protected:
	static void _bind_methods();

public:
	// `kind`: FIRE, LAVA, WATER_STILL or WATER_FLOWING; `seed` its own
	// random numbers.
	void setup(int p_kind, int64_t seed);
	// One step; the pixels with the pattern slid down `shift` rows (lava's
	// and water's flowing textures).
	godot::PackedByteArray step(int shift);
};

} // namespace voxel
