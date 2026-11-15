#include "native_path.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <unordered_map>
#include <vector>

#include "pcg.h"

using namespace godot;

namespace voxel {

namespace {

struct Cell {
	int x, y, z;
	bool operator==(const Cell &o) const { return x == o.x && y == o.y && z == o.z; }
	bool operator!=(const Cell &o) const { return !(*this == o); }
};

const Cell NONE{ std::numeric_limits<int>::max(), std::numeric_limits<int>::max(), std::numeric_limits<int>::max() };

inline int64_t key_of(int x, int y, int z) {
	return (int64_t(x) & 0x1FFFFF) | ((int64_t(y) & 0x1FFFFF) << 21) | ((int64_t(z) & 0x1FFFFF) << 42);
}

inline int64_t key_of(const Cell &c) { return key_of(c.x, c.y, c.z); }

// VoxelWorld.get_block(): AIR (0) where no chunk is loaded.
class Blocks {
	const Dictionary &chunks;
	std::unordered_map<int64_t, PackedInt32Array> cache;
	int64_t last_key = std::numeric_limits<int64_t>::min();
	const int32_t *last = nullptr;

public:
	explicit Blocks(const Dictionary &p_chunks) : chunks(p_chunks) {}

	int get(int x, int y, int z) {
		const int cx = x >> 4, cy = y >> 4, cz = z >> 4;
		const int64_t key = key_of(cx, cy, cz);
		if (key != last_key) {
			last_key = key;
			auto found = cache.find(key);
			if (found == cache.end()) {
				PackedInt32Array blocks;
				const Variant chunk = chunks.get(Vector3i(cx, cy, cz), Variant());
				if (chunk.get_type() == Variant::OBJECT) {
					Object *data = chunk;
					if (data) {
						blocks = data->get("blocks");
					}
				}
				found = cache.emplace(key, blocks).first;
			}
			last = found->second.size() == 4096 ? found->second.ptr() : nullptr;
		}
		if (!last) {
			return 0;
		}
		return last[(x & 15) + ((z & 15) << 4) + ((y & 15) << 8)];
	}
};

struct Tables {
	const uint8_t *solid, *floor, *harmful, *liquid;
	int size;
	uint8_t at(const uint8_t *table, int id) const { return id >= 0 && id < size ? table[id] : 0; }
};

// Pathfinder.standable()
bool standable(Blocks &w, const Tables &t, const Cell &c, int tall) {
	for (int dy = 0; dy < tall; dy++) {
		const int id = w.get(c.x, c.y + dy, c.z);
		if (t.at(t.solid, id) == 1 || t.at(t.harmful, id) == 1) {
			return false;
		}
	}
	const int here = w.get(c.x, c.y, c.z);
	if (t.at(t.liquid, here) == 1) {
		return true;
	}
	const int below = w.get(c.x, c.y - 1, c.z);
	return t.at(t.floor, below) == 1 && t.at(t.harmful, below) == 0;
}

// Pathfinder._step()
Cell step_to(Blocks &w, const Tables &t, const Cell &cell, int tx, int tz, int tall) {
	const Cell same{ tx, cell.y, tz };
	if (standable(w, t, same, tall)) {
		return same;
	}
	const Cell up{ tx, cell.y + 1, tz };
	if (standable(w, t, up, tall) && t.at(t.solid, w.get(cell.x, cell.y + tall, cell.z)) == 0) {
		return up;
	}
	for (int dy = 1; dy <= 3; dy++) { // MAX_DROP
		const Cell down{ tx, cell.y - dy, tz };
		const int id = w.get(down.x, down.y + tall - 1, down.z);
		if (t.at(t.solid, id) == 1) {
			return NONE;
		}
		if (standable(w, t, down, tall)) {
			return down;
		}
	}
	return NONE;
}

// Pathfinder._open()
bool open_at(Blocks &w, const Tables &t, int x, int y, int z, int tall) {
	for (int dy = 0; dy < tall; dy++) {
		if (t.at(t.solid, w.get(x, y + dy, z)) == 1) {
			return false;
		}
	}
	return true;
}

// Pathfinder._guess(): int + float + float, left to right like GDScript.
double guess(const Cell &a, const Cell &b) {
	const int dx = std::abs(a.x - b.x);
	const int dz = std::abs(a.z - b.z);
	return (double(std::max(dx, dz)) + 0.41 * double(std::min(dx, dz))) + double(std::abs(a.y - b.y)) * 0.5;
}

// Pathfinder._Heap: the same binary heap (scores as 32-bit floats), so ties
// come out in the same order.
struct Heap {
	std::vector<Cell> cells;
	std::vector<float> scores;

	bool empty() const { return cells.empty(); }

	void swap(size_t a, size_t b) {
		std::swap(cells[a], cells[b]);
		std::swap(scores[a], scores[b]);
	}

	void push(const Cell &cell, double score) {
		cells.push_back(cell);
		scores.push_back(float(score));
		size_t i = cells.size() - 1;
		while (i > 0) {
			const size_t parent = (i - 1) / 2;
			if (scores[parent] <= scores[i]) {
				break;
			}
			swap(i, parent);
			i = parent;
		}
	}

	Cell pop() {
		const Cell top = cells[0];
		const size_t last = cells.size() - 1;
		swap(0, last);
		cells.resize(last);
		scores.resize(last);
		size_t i = 0;
		while (true) {
			size_t smallest = i;
			for (size_t child : { 2 * i + 1, 2 * i + 2 }) {
				if (child < last && scores[child] < scores[smallest]) {
					smallest = child;
				}
			}
			if (smallest == i) {
				break;
			}
			swap(i, smallest);
			i = smallest;
		}
		return top;
	}
};

const int NEIGHBORS[8][2] = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } };

} // namespace

PackedInt32Array NativePath::find(const Dictionary &chunks, const Vector3i &p_start, const Vector3i &p_goal, int tall,
		int max_nodes, const PackedByteArray &solid, const PackedByteArray &floor, const PackedByteArray &harmful,
		const PackedByteArray &liquid) {
	PackedInt32Array result;
	result.push_back(0);
	const Cell start{ p_start.x, p_start.y, p_start.z };
	const Cell goal{ p_goal.x, p_goal.y, p_goal.z };
	if (start == goal) {
		return result;
	}
	const int size = int(std::min(std::min(solid.size(), floor.size()), std::min(harmful.size(), liquid.size())));
	const Tables t{ solid.ptr(), floor.ptr(), harmful.ptr(), liquid.ptr(), size };
	Blocks w(chunks);

	Heap heap;
	heap.push(start, guess(start, goal));
	std::unordered_map<int64_t, bool> closed;
	std::unordered_map<int64_t, Cell> came;
	std::unordered_map<int64_t, double> cost;
	cost[key_of(start)] = 0.0;
	Cell best = start;
	double best_guess = guess(start, goal);
	int visited = 0;
	while (!heap.empty() && visited < max_nodes) {
		const Cell current = heap.pop();
		const int64_t current_key = key_of(current);
		if (closed.count(current_key)) {
			continue;
		}
		closed[current_key] = true;
		visited++;
		if (current == goal) {
			best = goal;
			break;
		}
		const double g = guess(current, goal);
		if (g < best_guess) {
			best_guess = g;
			best = current;
		}
		for (int i = 0; i < 8; i++) {
			const int ox = NEIGHBORS[i][0], oz = NEIGHBORS[i][1];
			if (i >= 4) {
				if (!open_at(w, t, current.x + ox, current.y, current.z, tall) ||
						!open_at(w, t, current.x, current.y, current.z + oz, tall)) {
					continue;
				}
			}
			const Cell next = step_to(w, t, current, current.x + ox, current.z + oz, tall);
			if (next == NONE) {
				continue;
			}
			const int64_t next_key = key_of(next);
			if (closed.count(next_key)) {
				continue;
			}
			double step = i >= 4 ? 1.41 : 1.0;
			if (next.y > current.y) {
				step += 1.0;
			} else if (next.y < current.y) {
				step += 0.5 * double(current.y - next.y);
			}
			if (t.at(t.liquid, w.get(next.x, next.y, next.z)) == 1) {
				step *= 2.0;
			}
			const double total = cost[current_key] + step;
			auto known = cost.find(next_key);
			if (total < (known == cost.end() ? INFINITY : known->second)) {
				cost[next_key] = total;
				came[next_key] = current;
				heap.push(next, total + guess(next, goal));
			}
		}
	}
	result.set(0, visited);
	if (best == start) {
		return result;
	}
	std::vector<Cell> path;
	Cell cell = best;
	while (cell != start) {
		path.push_back(cell);
		cell = came[key_of(cell)];
	}
	for (auto it = path.rbegin(); it != path.rend(); ++it) {
		result.push_back(it->x);
		result.push_back(it->y);
		result.push_back(it->z);
	}
	return result;
}

PackedInt32Array NativePath::random_ticks(const Array &blocks, int count, const PackedByteArray &ticks, int64_t seed) {
	PackedInt32Array result;
	Pcg rng{ uint64_t(seed) };
	const uint8_t *table = ticks.ptr();
	const int64_t table_size = ticks.size();
	for (int64_t c = 0; c < blocks.size(); c++) {
		const PackedInt32Array chunk = blocks[c];
		if (chunk.size() != 4096) {
			continue;
		}
		const int32_t *data = chunk.ptr();
		for (int i = 0; i < count; i++) {
			const int index = int(rng.next() & 4095u);
			const int id = data[index];
			if (id >= 0 && id < table_size && table[id] != 0) {
				result.push_back(int32_t(c));
				result.push_back(index);
			}
		}
	}
	return result;
}

void NativePath::_bind_methods() {
	ClassDB::bind_static_method("NativePath",
			D_METHOD("find", "chunks", "start", "goal", "tall", "max_nodes", "solid", "floor", "harmful", "liquid"),
			&NativePath::find);
	ClassDB::bind_static_method("NativePath", D_METHOD("random_ticks", "blocks", "count", "ticks", "seed"),
			&NativePath::random_ticks);
}

} // namespace voxel
