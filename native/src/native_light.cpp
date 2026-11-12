#include "native_light.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <vector>

using namespace godot;

namespace voxel {

namespace {

constexpr int MAX = 15;
constexpr int W = 48; // area width in blocks (3 columns)
constexpr int H = 256; // WorldGenerator.HEIGHT
constexpr int WW = W * W;
constexpr int CHUNKS = H / 16;
constexpr int VOLUME = 16 * 16 * 16;

// The area as opacities (one byte a cell instead of a block id looked up in
// the table every time), index x + W * (z + W * y). Unknown ids let no light
// through.
void fill_opacity(const Array &chunks, const uint8_t *opacity, int64_t table_size, uint8_t *area) {
	for (int c = 0; c < 9; c++) {
		const int x0 = (c / 3) * 16;
		const int z0 = (c % 3) * 16;
		const Array column = chunks[c];
		for (int k = 0; k < CHUNKS; k++) {
			if (k >= column.size()) {
				// Missing: solid.
				for (int ly = 0; ly < 16; ly++)
					for (int lz = 0; lz < 16; lz++)
						memset(area + x0 + W * (z0 + lz + W * (k * 16 + ly)), MAX, 16);
				continue;
			}
			const PackedInt32Array blocks = column[k];
			const int32_t *ids = blocks.ptr();
			const bool full = blocks.size() >= VOLUME;
			for (int i = 0; i < VOLUME; i++) {
				const int32_t id = full ? ids[i] : 1;
				const int cell = x0 + (i & 15) + W * (z0 + ((i >> 4) & 15) + W * (k * 16 + (i >> 8)));
				area[cell] = (id >= 0 && id < table_size) ? opacity[id] : MAX;
			}
		}
	}
}

// The center column's 16 light arrays out of the area's stored light.
Array center_light(const std::vector<uint8_t> &stored) {
	Array result;
	for (int k = 0; k < CHUNKS; k++) {
		PackedByteArray light;
		light.resize(VOLUME);
		uint8_t *out = light.ptrw();
		for (int ly = 0; ly < 16; ly++) {
			const int y = k * 16 + ly;
			for (int lz = 0; lz < 16; lz++) {
				const int base = 16 + W * (16 + lz + W * y);
				memcpy(out + 16 * (lz + 16 * ly), stored.data() + base, 16);
			}
		}
		result.append(light);
	}
	return result;
}

// One step from `cell` in direction `d` (0..5: +x, -x, +z, -z, +y, -y), or -1
// off the area.
inline int step(int cell, int d, int x, int y, int z) {
	switch (d) {
		case 0: return x == W - 1 ? -1 : cell + 1;
		case 1: return x == 0 ? -1 : cell - 1;
		case 2: return z == W - 1 ? -1 : cell + W;
		case 3: return z == 0 ? -1 : cell - W;
		case 4: return y == H - 1 ? -1 : cell + WW;
		default: return y == 0 ? -1 : cell - WW;
	}
}

// SkyLight.compute_column().
Array sky_light(const uint8_t *area, const Array &heights) {
	std::vector<uint8_t> stored(WW * H, 0);
	std::vector<int32_t> tops(WW, H - 1);
	for (int c = 0; c < 9; c++) {
		const int ox = (c / 3) * 16;
		const int oz = (c % 3) * 16;
		const PackedInt32Array column = heights[c];
		if (column.size() < 256)
			continue;
		const int32_t *h = column.ptr();
		for (int z = 0; z < 16; z++)
			for (int x = 0; x < 16; x++)
				tops[(ox + x) + W * (oz + z)] = std::min(h[x + 16 * z], H - 1);
	}

	// 1. Straight down from the sky through leaves / water.
	for (int column_index = 0; column_index < WW; column_index++) {
		int y = tops[column_index];
		int level = MAX;
		int cell = column_index + WW * y;
		while (y >= 0) {
			const int op = area[cell];
			if (op >= MAX)
				break;
			level -= op;
			if (level <= 0)
				break;
			stored[cell] = level;
			y--;
			cell -= WW;
		}
	}

	// 2. Seeds: lit cells next to a neighbor column's darker cells at the same
	// height (terrain steps, cliffs, cave mouths).
	std::vector<int32_t> queue;
	queue.reserve(1 << 16);
	static const int DX[4] = { 1, -1, 0, 0 };
	static const int DZ[4] = { 0, 0, 1, -1 };
	for (int z = 0; z < W; z++) {
		for (int x = 0; x < W; x++) {
			const int column_index = x + W * z;
			const int top = tops[column_index];
			for (int d = 0; d < 4; d++) {
				const int nx = x + DX[d];
				const int nz = z + DZ[d];
				if (nx < 0 || nz < 0 || nx >= W || nz >= W)
					continue;
				const int neighbor_index = nx + W * nz;
				for (int y = std::min(tops[neighbor_index], H - 1); y >= 0; y--) {
					const int cell = column_index + WW * y;
					const int level = y > top ? MAX : stored[cell];
					if (level <= 1)
						break;
					const int target = neighbor_index + WW * y;
					if (stored[target] < level - 1 && area[target] < MAX)
						queue.push_back(cell);
				}
			}
		}
	}

	// 3. Flood fill (cells above a column's top are open sky: always 15).
	for (size_t head = 0; head < queue.size(); head++) {
		const int cell = queue[head];
		const int column_index = cell % WW;
		const int x = column_index % W;
		const int z = column_index / W;
		const int y = cell / WW;
		const int level = y > tops[column_index] ? MAX : stored[cell];
		if (level <= 1)
			continue;
		for (int d = 0; d < 6; d++) {
			const int target = step(cell, d, x, y, z);
			if (target < 0)
				continue;
			const int ny = target / WW;
			if (ny > tops[target % WW])
				continue; // open sky: already full
			const int op = area[target];
			if (op >= MAX)
				continue;
			const int candidate = level - (op > 1 ? op : 1);
			if (candidate > stored[target]) {
				stored[target] = candidate;
				queue.push_back(target);
			}
		}
	}

	// 4. Open sky above the center column's tops.
	for (int lz = 0; lz < 16; lz++) {
		for (int lx = 0; lx < 16; lx++) {
			const int column_index = (16 + lx) + W * (16 + lz);
			for (int cell = column_index + WW * (tops[column_index] + 1); cell < WW * H; cell += WW)
				stored[cell] = MAX;
		}
	}
	return center_light(stored);
}

// BlockLight.compute_column() with its sources (BlockLight.sources_of()):
// the glowing blocks of the chunks flagged in `glowing`.
Array block_light(const uint8_t *area, const Array &chunks, const Array &glowing,
		const uint8_t *emission, int64_t emission_size) {
	std::vector<uint8_t> stored(WW * H, 0);
	std::vector<int32_t> queue;
	for (int c = 0; c < 9; c++) {
		const int x0 = (c / 3) * 16;
		const int z0 = (c % 3) * 16;
		const PackedByteArray flags = glowing[c];
		const Array column = chunks[c];
		for (int k = 0; k < std::min<int64_t>(flags.size(), column.size()); k++) {
			if (flags[k] == 0)
				continue;
			const PackedInt32Array blocks = column[k];
			const int32_t *ids = blocks.ptr();
			for (int i = 0; i < std::min<int64_t>(blocks.size(), VOLUME); i++) {
				const int32_t id = ids[i];
				if (id <= 0 || id >= emission_size || emission[id] == 0)
					continue;
				const int cell = x0 + (i & 15) + W * (z0 + ((i >> 4) & 15) + W * (k * 16 + (i >> 8)));
				stored[cell] = emission[id];
				queue.push_back(cell);
			}
		}
	}
	for (size_t head = 0; head < queue.size(); head++) {
		const int cell = queue[head];
		const int level = stored[cell];
		if (level <= 1)
			continue;
		const int column_index = cell % WW;
		const int x = column_index % W;
		const int z = column_index / W;
		const int y = cell / WW;
		for (int d = 0; d < 6; d++) {
			const int target = step(cell, d, x, y, z);
			if (target < 0)
				continue;
			const int op = area[target];
			if (op >= MAX)
				continue;
			const int candidate = level - (op > 1 ? op : 1);
			if (candidate > stored[target]) {
				stored[target] = candidate;
				queue.push_back(target);
			}
		}
	}
	return center_light(stored);
}

} // namespace

Array NativeLight::compute_column(const Array &chunks, const Array &heights, const Array &glowing,
		const PackedByteArray &opacity, const PackedByteArray &emission) {
	Array result;
	if (chunks.size() < 9 || heights.size() < 9 || glowing.size() < 9)
		return result;
	std::vector<uint8_t> area(WW * H);
	fill_opacity(chunks, opacity.ptr(), opacity.size(), area.data());
	result.append(sky_light(area.data(), heights));
	result.append(block_light(area.data(), chunks, glowing, emission.ptr(), emission.size()));
	return result;
}

void NativeLight::_bind_methods() {
	ClassDB::bind_static_method("NativeLight", D_METHOD("compute_column", "chunks", "heights", "glowing", "opacity", "emission"),
			&NativeLight::compute_column);
}

} // namespace voxel
