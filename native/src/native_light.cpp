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

namespace {

// The columns around edits (3x3 for one, more for a batch), read in place
// (chunk arrays are not copied: a chunk's light is copied only when it
// changes). Columns are indexed cx * columns_z + cz.
struct EditArea {
	int columns_x = 3;
	int columns_z = 3;
	std::vector<const int32_t *> blocks;
	std::vector<const uint8_t *> light;
	std::vector<std::vector<uint8_t>> changed;
	std::vector<int32_t> dirty;
	const uint8_t *opacity;
	int64_t opacity_size;
	bool sky;

	void resize(int cx, int cz) {
		columns_x = cx;
		columns_z = cz;
		const size_t slots = size_t(cx) * cz * CHUNKS;
		blocks.assign(slots, nullptr);
		light.assign(slots, nullptr);
		changed.assign(slots, {});
		dirty.assign(slots, 0);
	}
	size_t slots() const {
		return light.size();
	}
	int slot(int x, int y, int z) const {
		return ((x >> 4) * columns_z + (z >> 4)) * CHUNKS + (y >> 4);
	}
	static int local(int x, int y, int z) {
		return (x & 15) + ((z & 15) << 4) + ((y & 15) << 8);
	}
	bool in_area(int x, int z) const {
		return x >= 0 && z >= 0 && x < columns_x * 16 && z < columns_z * 16;
	}
	// VoxelWorld.is_inside(): a loaded chunk.
	bool inside(int x, int y, int z) const {
		return y >= 0 && y < H && in_area(x, z) && light[slot(x, y, z)] != nullptr;
	}
	int block(int x, int y, int z) const {
		if (!inside(x, y, z))
			return 0;
		const int32_t *b = blocks[slot(x, y, z)];
		return b ? b[local(x, y, z)] : 0;
	}
	int op(int x, int y, int z) const {
		const int id = block(x, y, z);
		return (id >= 0 && id < opacity_size) ? opacity[id] : MAX;
	}
	// get_light() / get_block_light(): 15 (sky) or 0 above the world, 0
	// below it and where nothing is loaded.
	int get(int x, int y, int z) const {
		if (y >= H)
			return sky ? MAX : 0;
		if (!inside(x, y, z))
			return 0;
		const int s = slot(x, y, z);
		return changed[s].empty() ? light[s][local(x, y, z)] : changed[s][local(x, y, z)];
	}
	// _set_light() / _set_block_light() with _mark_dirty_around().
	void set(int x, int y, int z, int level) {
		if (!inside(x, y, z))
			return;
		const int s = slot(x, y, z);
		const int i = local(x, y, z);
		if (get(x, y, z) == level)
			return;
		if (changed[s].empty())
			changed[s].assign(light[s], light[s] + VOLUME);
		changed[s][i] = uint8_t(level);
		const int lx = x & 15, ly = y & 15, lz = z & 15;
		for (int dx = lx == 0 ? -1 : 0; dx <= (lx == 15 ? 1 : 0); dx++)
			for (int dy = ly == 0 ? -1 : 0; dy <= (ly == 15 ? 1 : 0); dy++)
				for (int dz = lz == 0 ? -1 : 0; dz <= (lz == 15 ? 1 : 0); dz++)
					dirty[s] |= 1 << ((dx + 1) * 9 + (dy + 1) * 3 + (dz + 1));
	}
};

// NEIGHBORS: up, down, +x, -x, +z, -z.
const int OFFSETS[6][3] = { { 0, 1, 0 }, { 0, -1, 0 }, { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };
constexpr int UP = 0, DOWN = 1;

struct Cell {
	int x, y, z;
};

// _run_light_spread() for one kind, to the end.
void spread(EditArea &a, std::vector<Cell> &queue) {
	for (size_t head = 0; head < queue.size(); head++) {
		const Cell c = queue[head];
		const int level = a.get(c.x, c.y, c.z);
		if (level <= 1)
			continue;
		for (int d = 0; d < 6; d++) {
			const int nx = c.x + OFFSETS[d][0], ny = c.y + OFFSETS[d][1], nz = c.z + OFFSETS[d][2];
			if (ny < 0 || ny >= H || !a.inside(nx, ny, nz))
				continue;
			const int nop = a.op(nx, ny, nz);
			if (nop >= MAX)
				continue;
			const int candidate = (a.sky && d == DOWN && level == MAX) ? level - nop : level - std::max(nop, 1);
			if (candidate > a.get(nx, ny, nz)) {
				a.set(nx, ny, nz, candidate);
				queue.push_back({ nx, ny, nz });
			}
		}
	}
}

// VoxelWorld._relight().
void relight_sky(EditArea &a, int px, int py, int pz) {
	struct Entry {
		Cell cell;
		int level;
	};
	std::vector<Entry> removal = { { { px, py, pz }, a.get(px, py, pz) } };
	std::vector<Cell> queue;
	a.set(px, py, pz, 0);
	for (size_t head = 0; head < removal.size(); head++) {
		const Entry e = removal[head];
		for (int d = 0; d < 6; d++) {
			const int nx = e.cell.x + OFFSETS[d][0], ny = e.cell.y + OFFSETS[d][1], nz = e.cell.z + OFFSETS[d][2];
			const int nl = a.get(nx, ny, nz);
			if (nl == 0 || ny >= H)
				continue;
			if (nl < e.level || (d == DOWN && e.level == MAX && nl == MAX)) {
				a.set(nx, ny, nz, 0);
				removal.push_back({ { nx, ny, nz }, nl });
			} else {
				queue.push_back({ nx, ny, nz });
			}
		}
	}
	const int opacity = a.op(px, py, pz);
	if (opacity < MAX) {
		int best = 0;
		for (int d = 0; d < 6; d++) {
			const int nl = a.get(px + OFFSETS[d][0], py + OFFSETS[d][1], pz + OFFSETS[d][2]);
			const int candidate = (d == UP && nl == MAX) ? nl - opacity : nl - std::max(opacity, 1);
			best = std::max(best, candidate);
		}
		if (best > 0) {
			a.set(px, py, pz, best);
			queue.push_back({ px, py, pz });
		}
	}
	spread(a, queue);
}

// VoxelWorld._relight_block_light().
void relight_block(EditArea &a, const uint8_t *emission, int64_t emission_size, int px, int py, int pz) {
	auto glow_of = [&](int x, int y, int z) -> int {
		const int id = a.block(x, y, z);
		return (id >= 0 && id < emission_size) ? emission[id] : 0;
	};
	const int here = a.get(px, py, pz);
	const int glow = glow_of(px, py, pz);
	std::vector<Cell> queue;
	if (glow == 0 && here == 0) {
		bool lit_near = false;
		for (int d = 0; d < 6 && !lit_near; d++)
			lit_near = a.get(px + OFFSETS[d][0], py + OFFSETS[d][1], pz + OFFSETS[d][2]) > 1;
		if (!lit_near)
			return;
	}
	if (glow >= here && glow > 0) {
		a.set(px, py, pz, glow);
		queue.push_back({ px, py, pz });
		spread(a, queue);
		return;
	}
	struct Entry {
		Cell cell;
		int level;
	};
	std::vector<Entry> removal = { { { px, py, pz }, here } };
	a.set(px, py, pz, 0);
	for (size_t head = 0; head < removal.size(); head++) {
		const Entry e = removal[head];
		for (int d = 0; d < 6; d++) {
			const int nx = e.cell.x + OFFSETS[d][0], ny = e.cell.y + OFFSETS[d][1], nz = e.cell.z + OFFSETS[d][2];
			const int nl = a.get(nx, ny, nz);
			if (nl == 0)
				continue;
			if (nl < e.level && glow_of(nx, ny, nz) < nl) {
				a.set(nx, ny, nz, 0);
				removal.push_back({ { nx, ny, nz }, nl });
			} else {
				queue.push_back({ nx, ny, nz });
			}
		}
	}
	int best = glow_of(px, py, pz);
	const int opacity = a.op(px, py, pz);
	if (opacity < MAX)
		for (int d = 0; d < 6; d++)
			best = std::max(best, a.get(px + OFFSETS[d][0], py + OFFSETS[d][1], pz + OFFSETS[d][2]) - std::max(opacity, 1));
	if (best > 0) {
		a.set(px, py, pz, best);
		queue.push_back({ px, py, pz });
	}
	spread(a, queue);
}

} // namespace

namespace {

// Points the area at the columns' chunk arrays (kept referenced in `refs`).
void read_area(EditArea &area, const Array &blocks, const Array &light, std::vector<PackedInt32Array> &block_refs,
		std::vector<PackedByteArray> &light_refs) {
	const int columns = area.columns_x * area.columns_z;
	block_refs.reserve(size_t(columns) * CHUNKS);
	light_refs.reserve(size_t(columns) * CHUNKS);
	for (int c = 0; c < columns; c++) {
		const Array column_blocks = blocks[c];
		const Array column_light = light[c];
		for (int k = 0; k < CHUNKS && k < column_light.size() && k < column_blocks.size(); k++) {
			block_refs.push_back(column_blocks[k]);
			light_refs.push_back(column_light[k]);
			if (block_refs.back().size() >= VOLUME && light_refs.back().size() >= VOLUME) {
				area.blocks[c * CHUNKS + k] = block_refs.back().ptr();
				area.light[c * CHUNKS + k] = light_refs.back().ptr();
			}
		}
	}
}

// [chunks (slots), their new light arrays, dirty masks].
Array area_result(const EditArea &area) {
	PackedInt32Array chunks;
	Array arrays;
	PackedInt32Array masks;
	for (size_t s = 0; s < area.slots(); s++) {
		if (area.changed[s].empty())
			continue;
		PackedByteArray out;
		out.resize(VOLUME);
		memcpy(out.ptrw(), area.changed[s].data(), VOLUME);
		chunks.append(int32_t(s));
		arrays.append(out);
		masks.append(area.dirty[s]);
	}
	Array result;
	result.append(chunks);
	result.append(arrays);
	result.append(masks);
	return result;
}

} // namespace

Array NativeLight::relight_edit(bool sky, const Vector3i &pos, const Array &blocks, const Array &light,
		const PackedByteArray &opacity, const PackedByteArray &emission) {
	ERR_FAIL_COND_V(blocks.size() < 9 || light.size() < 9, Array());
	PackedInt32Array one;
	one.append(pos.x);
	one.append(pos.y);
	one.append(pos.z);
	return relight_edits(sky, one, 3, 3, blocks, light, opacity, emission);
}

Array NativeLight::relight_edits(bool sky, const PackedInt32Array &positions, int columns_x, int columns_z,
		const Array &blocks, const Array &light, const PackedByteArray &opacity, const PackedByteArray &emission) {
	ERR_FAIL_COND_V(columns_x < 1 || columns_z < 1 || columns_x * columns_z > 1024, Array());
	ERR_FAIL_COND_V(blocks.size() < columns_x * columns_z || light.size() < columns_x * columns_z, Array());
	EditArea area;
	area.resize(columns_x, columns_z);
	area.sky = sky;
	area.opacity = opacity.ptr();
	area.opacity_size = opacity.size();
	std::vector<PackedInt32Array> block_refs;
	std::vector<PackedByteArray> light_refs;
	read_area(area, blocks, light, block_refs, light_refs);
	// One after another, like the edits made one by one: each removes the
	// light its change took away (stale light of edits not done yet goes
	// when their turn comes) and lets the light around flow in again.
	for (int64_t i = 0; i + 2 < positions.size(); i += 3) {
		const int x = positions[i], y = positions[i + 1], z = positions[i + 2];
		if (!area.inside(x, y, z))
			continue;
		if (sky)
			relight_sky(area, x, y, z);
		else
			relight_block(area, emission.ptr(), emission.size(), x, y, z);
	}
	return area_result(area);
}

void NativeLight::_bind_methods() {
	ClassDB::bind_static_method("NativeLight", D_METHOD("compute_column", "chunks", "heights", "glowing", "opacity", "emission"),
			&NativeLight::compute_column);
	ClassDB::bind_static_method("NativeLight", D_METHOD("relight_edit", "sky", "pos", "blocks", "light", "opacity", "emission"),
			&NativeLight::relight_edit);
	ClassDB::bind_static_method("NativeLight",
			D_METHOD("relight_edits", "sky", "positions", "columns_x", "columns_z", "blocks", "light", "opacity", "emission"),
			&NativeLight::relight_edits);
}

} // namespace voxel
