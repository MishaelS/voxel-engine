#include "native_texture_fx.h"

#include <godot_cpp/core/class_db.hpp>

#include <algorithm>
#include <cmath>

using namespace godot;

namespace voxel {

void NativeTextureFx::setup(int p_kind, int64_t seed) {
	kind = p_kind;
	rng.seed(uint64_t(seed));
	const size_t cells = size_t(SIZE) * (kind == FIRE ? FIRE_ROWS : SIZE);
	current.assign(cells, 0.0f);
	next.assign(cells, 0.0f);
	heat.assign(cells, 0.0f);
	speed.assign(cells, 0.0f);
}

// FireAnimation._step: heat rises from the random bottom row, spreads and fades.
void NativeTextureFx::step_fire() {
	for (int y = 0; y < FIRE_ROWS; y++) {
		for (int x = 0; x < SIZE; x++) {
			int count = 18;
			float sum = current[x + ((y + 1) % FIRE_ROWS) * SIZE] * 18.0f;
			for (int nx = x - 1; nx <= x + 1; nx++) {
				for (int ny = y; ny <= y + 1; ny++) {
					if (nx >= 0 && ny >= 0 && nx < SIZE && ny < FIRE_ROWS) {
						sum += current[nx + ny * SIZE];
						count++;
					}
				}
			}
			float value = sum / (float(count) * 1.06f);
			if (y >= FIRE_ROWS - 1) {
				value = rng.randf() * rng.randf() * rng.randf() * 4.0f + rng.randf() * 0.1f + 0.2f;
			}
			next[x + y * SIZE] = value;
		}
	}
	current.swap(next);
}

// LavaAnimation._Heat.step: hot spots appear at random, spread and cool.
void NativeTextureFx::step_lava() {
	for (int y = 0; y < SIZE; y++) {
		const int wobble_x = int(std::sin(double(y) * Math_PI * 2.0 / SIZE) * 1.2);
		for (int x = 0; x < SIZE; x++) {
			const int wobble_y = int(std::sin(double(x) * Math_PI * 2.0 / SIZE) * 1.2);
			float sum = 0.0f;
			for (int nx = x - 1; nx <= x + 1; nx++) {
				for (int ny = y - 1; ny <= y + 1; ny++) {
					sum += current[((nx + wobble_x) & 15) + ((ny + wobble_y) & 15) * SIZE];
				}
			}
			const int x1 = (x + 1) & 15;
			const int y1 = (y + 1) & 15;
			next[x + y * SIZE] = sum / 10.0f +
					(heat[x + y * SIZE] + heat[x1 + y * SIZE] + heat[x1 + y1 * SIZE] + heat[x + y1 * SIZE]) / 4.0f * 0.8f;
			const int i = x + y * SIZE;
			heat[i] = std::max(heat[i] + speed[i] * 0.01f, 0.0f);
			speed[i] -= 0.06f;
			if (rng.randf() < 0.005f) {
				speed[i] = 1.5f;
			}
		}
	}
	current.swap(next);
}

// WaterAnimation._Ripples.step: ripples spread (sideways, or along the
// flow), random drops add energy.
void NativeTextureFx::step_water() {
	const bool flowing = kind == WATER_FLOWING;
	for (int y = 0; y < SIZE; y++) {
		for (int x = 0; x < SIZE; x++) {
			float sum = 0.0f;
			if (flowing) {
				for (int k = y - 2; k <= y; k++) {
					sum += current[x + (k & 15) * SIZE];
				}
				next[x + y * SIZE] = sum / 3.2f + heat[x + y * SIZE] * 0.8f;
			} else {
				for (int k = x - 1; k <= x + 1; k++) {
					sum += current[(k & 15) + y * SIZE];
				}
				next[x + y * SIZE] = sum / 3.3f + heat[x + y * SIZE] * 0.8f;
			}
		}
	}
	const float decay = flowing ? 0.3f : 0.1f;
	const float chance = flowing ? 0.2f : 0.05f;
	for (int i = 0; i < SIZE * SIZE; i++) {
		heat[i] = std::max(heat[i] + speed[i] * 0.05f, 0.0f);
		speed[i] -= decay;
		if (rng.randf() < chance) {
			speed[i] = 0.5f;
		}
	}
	current.swap(next);
}

PackedByteArray NativeTextureFx::step(int shift) {
	PackedByteArray data;
	data.resize(SIZE * SIZE * 4);
	if (current.empty()) {
		return data;
	}
	uint8_t *out = data.ptrw();
	switch (kind) {
		case FIRE: {
			step_fire();
			for (int i = 0; i < SIZE * SIZE; i++) {
				const float f = std::clamp(current[i] * 1.8f, 0.0f, 1.0f);
				out[i * 4] = uint8_t(f * 155.0f + 100.0f);
				out[i * 4 + 1] = uint8_t(f * f * 255.0f);
				out[i * 4 + 2] = uint8_t(std::pow(f, 10.0f) * 255.0f);
				out[i * 4 + 3] = f < 0.5f ? 0 : 255;
			}
		} break;
		case LAVA: {
			step_lava();
			for (int i = 0; i < SIZE * SIZE; i++) {
				const float f = std::clamp(current[(i - shift * SIZE) & 255] * 2.0f, 0.0f, 1.0f);
				out[i * 4] = uint8_t(f * 100.0f + 155.0f);
				out[i * 4 + 1] = uint8_t(f * f * 255.0f);
				out[i * 4 + 2] = uint8_t(f * f * f * f * 128.0f);
				out[i * 4 + 3] = 255;
			}
		} break;
		default: {
			step_water();
			for (int i = 0; i < SIZE * SIZE; i++) {
				float energy = std::clamp(current[(i - shift * SIZE) & 255], 0.0f, 1.0f);
				energy *= energy;
				out[i * 4] = uint8_t(32.0f + energy * 32.0f);
				out[i * 4 + 1] = uint8_t(50.0f + energy * 64.0f);
				out[i * 4 + 2] = 255;
				out[i * 4 + 3] = uint8_t(146.0f + energy * 50.0f);
			}
		} break;
	}
	return data;
}

void NativeTextureFx::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "kind", "seed"), &NativeTextureFx::setup);
	ClassDB::bind_method(D_METHOD("step", "shift"), &NativeTextureFx::step);
}

} // namespace voxel
