#pragma once

#include <cmath>
#include <cstdint>
#include <cstdlib>

namespace voxel {

// Godot's RandomNumberGenerator (RandomPCG: PCG32 with Godot's default
// increment), number for number: seed, randi, randf, randi_range. Checked
// against the engine's own generator (NativeBetaGenerator.check_random).
class Pcg {
	uint64_t state = 0;
	uint64_t inc = 0;

	static constexpr uint64_t DEFAULT_INC = 1442695040888963407ULL;

public:
	explicit Pcg(uint64_t seed_value) { seed(seed_value); }

	void seed(uint64_t seed_value) {
		state = 0;
		inc = (DEFAULT_INC << 1u) | 1u;
		next();
		state += seed_value;
		next();
	}

	uint32_t next() {
		const uint64_t old = state;
		state = old * 6364136223846793005ULL + inc;
		const uint32_t xorshifted = uint32_t(((old >> 18u) ^ old) >> 27u);
		const uint32_t rot = uint32_t(old >> 59u);
		return (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
	}

	uint32_t bounded(uint32_t bound) {
		const uint32_t threshold = -bound % bound;
		for (;;) {
			const uint32_t r = next();
			if (r >= threshold)
				return r % bound;
		}
	}

	// randi(): 0 .. 2^32 - 1.
	int64_t randi() { return int64_t(next()); }

	// randf(): 0..1 as Godot's float, widened to double like GDScript.
	double randf() {
		const uint32_t proto_exp_offset = next();
		if (proto_exp_offset == 0)
			return 0.0;
		return double(std::ldexp(float(next() | 0x80000001u), -32 - __builtin_clz(proto_exp_offset)));
	}

	// randi_range(from, to), both ends included.
	int64_t randi_range(int64_t from, int64_t to) {
		const int f = int(from), t = int(to);
		if (f == t)
			return f;
		return int64_t(int(bounded(uint32_t(std::abs(f - t)) + 1)) + (f < t ? f : t));
	}
};

} // namespace voxel
