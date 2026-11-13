#include "native_mesher.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <memory>
#include <vector>

using namespace godot;

namespace voxel {

namespace {

constexpr int SIZE = 16;
constexpr int P = SIZE + 2;
constexpr int P2 = P * P;
constexpr int PADDED = P * P * P;
constexpr int MAX_LIGHT = 15;
constexpr int AIR = 0;
enum Layer { OPAQUE = 0, CUTOUT = 1, TRANSLUCENT = 2 };
enum Shape { CUBE = 0, CROSS = 1, MODEL = 2 };
enum Rotation { NONE = 0, TURN = 1, MIRROR = 2 };
constexpr int64_t ALL_CONNECTED = (int64_t(1) << 36) - 1;

struct Quad {
	Vector3 corners[4];
	Vector3 normal;
	Vector2 uvs[4];
	int layer = 0;
};

// Blocks' tables, copied once (set_tables), then shared by the workers.
struct Tables {
	std::vector<uint8_t> opaque, layer, cull_self, collides, liquid, biome_tint, rotation, shape;
	std::vector<int32_t> face_tiles, face_overlays, uv_mode, cull_group, liquid_level, model;
	std::vector<float> height;
	std::vector<Color> tints;
	std::vector<std::vector<Quad>> models;
	size_t count = 0; // block ids
};

std::shared_ptr<const Tables> g_tables;
// The same with Fast graphics' leaves (opaque, their fast tile): far chunks.
std::shared_ptr<const Tables> g_fast_tables;

std::shared_ptr<const Tables> tables(bool fast = false) {
	if (fast) {
		std::shared_ptr<const Tables> f = std::atomic_load(&g_fast_tables);
		if (f)
			return f;
	}
	return std::atomic_load(&g_tables);
}

template <typename T, typename Packed>
std::vector<T> copy_of(const Packed &array) {
	std::vector<T> result(array.size());
	for (int64_t i = 0; i < array.size(); i++)
		result[i] = T(array[i]);
	return result;
}

// FACE_CORNERS, FACE_OFFSETS of ChunkMesher (+Y, -Y, +X, -X, +Z, -Z).
const Vector3 FACE_CORNERS[6][4] = {
	{ { 0, 1, 0 }, { 1, 1, 0 }, { 1, 1, 1 }, { 0, 1, 1 } },
	{ { 0, 0, 1 }, { 1, 0, 1 }, { 1, 0, 0 }, { 0, 0, 0 } },
	{ { 1, 1, 1 }, { 1, 1, 0 }, { 1, 0, 0 }, { 1, 0, 1 } },
	{ { 0, 1, 0 }, { 0, 1, 1 }, { 0, 0, 1 }, { 0, 0, 0 } },
	{ { 0, 1, 1 }, { 1, 1, 1 }, { 1, 0, 1 }, { 0, 0, 1 } },
	{ { 1, 1, 0 }, { 0, 1, 0 }, { 0, 0, 0 }, { 1, 0, 0 } },
};
const int FACE_OFFSETS[6][3] = { { 0, 1, 0 }, { 0, -1, 0 }, { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };
const Vector3 NORMALS[6] = { { 0, 1, 0 }, { 0, -1, 0 }, { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };
const Vector2 CORNER_UVS[4] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } };
constexpr float CROSS_LOW = 0.05f;
constexpr float CROSS_HIGH = 0.95f;
const Vector3 CROSS_QUADS[4][4] = {
	{ { CROSS_LOW, 1, CROSS_LOW }, { CROSS_HIGH, 1, CROSS_HIGH }, { CROSS_HIGH, 0, CROSS_HIGH }, { CROSS_LOW, 0, CROSS_LOW } },
	{ { CROSS_HIGH, 1, CROSS_HIGH }, { CROSS_LOW, 1, CROSS_LOW }, { CROSS_LOW, 0, CROSS_LOW }, { CROSS_HIGH, 0, CROSS_HIGH } },
	{ { CROSS_LOW, 1, CROSS_HIGH }, { CROSS_HIGH, 1, CROSS_LOW }, { CROSS_HIGH, 0, CROSS_LOW }, { CROSS_LOW, 0, CROSS_HIGH } },
	{ { CROSS_HIGH, 1, CROSS_LOW }, { CROSS_LOW, 1, CROSS_HIGH }, { CROSS_LOW, 0, CROSS_HIGH }, { CROSS_HIGH, 0, CROSS_LOW } },
};

inline int delta(int x, int y, int z) {
	return x + P * z + P2 * y;
}

struct Offsets {
	int face[6];
	int ao[6 * 12];
	Offsets() {
		for (int f = 0; f < 6; f++) {
			const int *n = FACE_OFFSETS[f];
			face[f] = delta(n[0], n[1], n[2]);
			const int axis = n[0] != 0 ? 0 : (n[1] != 0 ? 1 : 2);
			const int ta = (axis + 1) % 3;
			const int tb = (axis + 2) % 3;
			for (int c = 0; c < 4; c++) {
				const Vector3 &corner = FACE_CORNERS[f][c];
				int a[3] = { 0, 0, 0 };
				int b[3] = { 0, 0, 0 };
				a[ta] = int(corner[ta]) * 2 - 1;
				b[tb] = int(corner[tb]) * 2 - 1;
				ao[f * 12 + c * 3] = delta(a[0], a[1], a[2]);
				ao[f * 12 + c * 3 + 1] = delta(b[0], b[1], b[2]);
				ao[f * 12 + c * 3 + 2] = delta(a[0] + b[0], a[1] + b[1], a[2] + b[2]);
			}
		}
	}
};
const Offsets OFFSETS;

// ChunkMesher.pad_blocks() / pad_light() into `padded` (already filled).
template <typename T, typename Packed>
void pad(T *padded, const Packed &center, const Dictionary &neighbors) {
	if (center.size() >= SIZE * SIZE * SIZE) {
		const auto *src = center.ptr();
		for (int y = 0; y < SIZE; y++)
			for (int z = 0; z < SIZE; z++)
				for (int x = 0; x < SIZE; x++)
					padded[1 + x + P * ((z + 1) + P * (y + 1))] = T(*src++);
	}
	const Array keys = neighbors.keys();
	for (int64_t n = 0; n < keys.size(); n++) {
		const Vector3i offset = keys[n];
		const Packed blocks = neighbors[keys[n]];
		if (blocks.size() < SIZE * SIZE * SIZE)
			continue;
		const auto *src = blocks.ptr();
		const int x0 = offset.x < 0 ? SIZE - 1 : 0, x1 = offset.x > 0 ? 0 : SIZE - 1;
		const int y0 = offset.y < 0 ? SIZE - 1 : 0, y1 = offset.y > 0 ? 0 : SIZE - 1;
		const int z0 = offset.z < 0 ? SIZE - 1 : 0, z1 = offset.z > 0 ? 0 : SIZE - 1;
		const int shift = (1 + offset.x * SIZE) + P * (1 + offset.z * SIZE) + P2 * (1 + offset.y * SIZE);
		for (int y = y0; y <= y1; y++)
			for (int z = z0; z <= z1; z++) {
				const int row = SIZE * (z + SIZE * y);
				const int dst = shift + P * z + P2 * y;
				for (int x = x0; x <= x1; x++)
					padded[dst + x] = T(src[row + x]);
			}
	}
}

// ChunkMesher.connectivity().
int64_t connectivity(const int32_t *padded, const Tables &t) {
	uint8_t open[4096];
	int count = 0;
	int i = 0;
	for (int y = 0; y < SIZE; y++)
		for (int z = 0; z < SIZE; z++) {
			const int row = 1 + P * ((z + 1) + P * (y + 1));
			for (int x = 0; x < SIZE; x++, i++) {
				open[i] = t.opaque[padded[row + x]] == 0;
				count += open[i];
			}
		}
	if (count == 0)
		return 0;
	if (count == 4096)
		return ALL_CONNECTED;
	uint8_t visited[4096] = {};
	int32_t queue[4096];
	int64_t result = 0;
	for (int start = 0; start < 4096; start++) {
		if (!open[start] || visited[start])
			continue;
		visited[start] = 1;
		queue[0] = start;
		int head = 0, tail = 1, faces = 0;
		auto visit = [&](int n) {
			if (open[n] && !visited[n]) {
				visited[n] = 1;
				queue[tail++] = n;
			}
		};
		while (head < tail) {
			const int c = queue[head++];
			const int x = c & 15, z = (c >> 4) & 15, y = c >> 8;
			if (y == 15) faces |= 1; else visit(c + 256);
			if (y == 0) faces |= 2; else visit(c - 256);
			if (x == 15) faces |= 4; else visit(c + 1);
			if (x == 0) faces |= 8; else visit(c - 1);
			if (z == 15) faces |= 16; else visit(c + 16);
			if (z == 0) faces |= 32; else visit(c - 16);
		}
		for (int a = 0; a < 6; a++)
			if (faces & (1 << a))
				for (int b = 0; b < 6; b++)
					if (faces & (1 << b))
						result |= int64_t(1) << (a * 6 + b);
	}
	return result;
}

inline int flow_decay(int level) {
	return level >= 8 ? 0 : level;
}

// One layer's surface arrays (ChunkMesher._build_layer()).
struct Surface {
	std::vector<Vector3> vertices, normals;
	std::vector<Vector2> uvs, layers;
	std::vector<Color> colors;
	std::vector<uint8_t> glow;
	std::vector<int32_t> indices;

	void add(const Vector3 &vertex, const Vector3 &normal, const Vector2 &layer, const Color &color, int g) {
		vertices.push_back(vertex);
		normals.push_back(normal);
		layers.push_back(layer);
		colors.push_back(color);
		glow.push_back(uint8_t(g));
		glow.push_back(0);
		glow.push_back(0);
		glow.push_back(0);
	}

	void quad_indices(int start) {
		const int order[6] = { 0, 1, 2, 0, 2, 3 };
		for (int k : order)
			indices.push_back(start + k);
	}

	Array to_arrays() const {
		Array arrays;
		arrays.resize(Mesh::ARRAY_MAX);
		PackedVector3Array v, n;
		PackedVector2Array uv, uv2;
		PackedColorArray c;
		PackedByteArray g;
		PackedInt32Array idx;
		v.resize(vertices.size());
		memcpy(v.ptrw(), vertices.data(), vertices.size() * sizeof(Vector3));
		n.resize(normals.size());
		memcpy(n.ptrw(), normals.data(), normals.size() * sizeof(Vector3));
		uv.resize(uvs.size());
		memcpy(uv.ptrw(), uvs.data(), uvs.size() * sizeof(Vector2));
		uv2.resize(layers.size());
		memcpy(uv2.ptrw(), layers.data(), layers.size() * sizeof(Vector2));
		c.resize(colors.size());
		memcpy(c.ptrw(), colors.data(), colors.size() * sizeof(Color));
		g.resize(glow.size());
		memcpy(g.ptrw(), glow.data(), glow.size());
		idx.resize(indices.size());
		memcpy(idx.ptrw(), indices.data(), indices.size() * sizeof(int32_t));
		arrays[Mesh::ARRAY_VERTEX] = v;
		arrays[Mesh::ARRAY_NORMAL] = n;
		arrays[Mesh::ARRAY_TEX_UV] = uv;
		arrays[Mesh::ARRAY_TEX_UV2] = uv2;
		arrays[Mesh::ARRAY_COLOR] = c;
		arrays[Mesh::ARRAY_CUSTOM0] = g;
		arrays[Mesh::ARRAY_INDEX] = idx;
		return arrays;
	}
};

struct Input {
	const int32_t *padded;
	const uint8_t *light;
	const uint8_t *block_light;
	const Color *grass;
	const Color *foliage; // null: the blocks' own tints
	bool rotate;
	Vector3i at;
};

void build_layer(const Tables &t, const Input &in, const std::vector<int> &cells, bool smooth, bool use_ao, Surface &s) {
	const int32_t *padded = in.padded;
	const uint8_t *light = in.light;
	const uint8_t *block_light = in.block_light;
	for (const int i : cells) {
		const int id = padded[i];
		Color tint = t.tints[id];
		const Vector3 origin(float(i % P - 1), float(i / P2 - 1), float((i / P) % P - 1));
		if (in.foliage && t.biome_tint[id] != 0) {
			const int column = (i % P - 1) + 16 * ((i / P) % P - 1);
			tint = t.biome_tint[id] == 1 ? in.grass[column] : in.foliage[column];
		}
		if (t.shape[id] == MODEL) {
			const Color model_color(tint.r, tint.g, tint.b, float(double(light[i]) / MAX_LIGHT));
			const int model_glow = block_light[i] * 17;
			const int model = t.model[id];
			if (model < 0 || model >= int(t.models.size()))
				continue;
			for (const Quad &q : t.models[model]) {
				const int start = int(s.vertices.size());
				const Vector2 layer(float(double(q.layer) + 0.75), -1.0f);
				for (int c = 0; c < 4; c++) {
					s.add(origin + q.corners[c], q.normal, layer, model_color, model_glow);
					s.uvs.push_back(q.uvs[c]);
				}
				s.quad_indices(start);
			}
			continue;
		}
		if (t.shape[id] == CROSS) {
			const Vector2 layer(float(double(t.face_tiles[id * 6 + 2]) + 0.75), t.face_overlays[id * 6 + 2] == -2 ? -2.0f : -1.0f);
			const Color cross_color(tint.r, tint.g, tint.b, float(double(light[i]) / MAX_LIGHT));
			const int cross_glow = block_light[i] * 17;
			for (const auto &q : CROSS_QUADS) {
				const int start = int(s.vertices.size());
				for (int c = 0; c < 4; c++) {
					s.add(origin + q[c], NORMALS[0], layer, cross_color, cross_glow);
					s.uvs.push_back(CORNER_UVS[c]);
				}
				s.quad_indices(start);
			}
			continue;
		}
		const bool self_culls = t.cull_self[id] == 1;
		const int group = t.cull_group[id];
		const double top = t.height[id];
		const bool is_liquid = t.liquid[id] == 1;
		const bool sloped = is_liquid && t.liquid[padded[i + P2]] == 0;
		float corner_heights[4] = { 1, 1, 1, 1 };
		Vector2 flow;
		if (sloped) {
			for (int k = 0; k < 4; k++) {
				const int cx = k & 1, cz = k >> 1;
				double total = 0.0, weight = 0.0;
				bool full = false;
				for (int dz = 0; dz < 2; dz++)
					for (int dx = 0; dx < 2; dx++) {
						const int j = i + (cx - 1 + dx) + (cz - 1 + dz) * P;
						const int other = padded[j];
						if (t.liquid[padded[j + P2]] == 1)
							full = true;
						if (t.liquid[other] == 1) {
							const int level = t.liquid_level[other];
							const double part = ((level >= 8 ? 0 : level) + 1) / 9.0;
							if (level == 0 || level >= 8) {
								total += part * 10.0;
								weight += 10.0;
							}
							total += part;
							weight += 1.0;
						} else if (t.collides[other] == 0) {
							total += 1.0;
							weight += 1.0;
						}
					}
				corner_heights[k] = full ? 1.0f : float(1.0 - total / std::max(weight, 1.0));
			}
			// The flow vector: toward lower neighbors.
			const int own = flow_decay(t.liquid_level[id]);
			const int steps[4] = { 1, -1, P, -P };
			const float fx[4] = { 1, -1, 0, 0 };
			const float fz[4] = { 0, 0, 1, -1 };
			for (int side = 0; side < 4; side++) {
				const int neighbor_id = padded[i + steps[side]];
				int diff;
				if (t.liquid[neighbor_id] == 1) {
					diff = flow_decay(t.liquid_level[neighbor_id]) - own;
				} else if (t.collides[neighbor_id] == 0 && t.liquid[padded[i + steps[side] - P2]] == 1) {
					diff = flow_decay(t.liquid_level[padded[i + steps[side] - P2]]) - (own - 8);
				} else {
					continue;
				}
				flow += Vector2(fx[side], fz[side]) * float(diff);
			}
			flow = flow.length_squared() > 1e-6 ? flow.normalized() : Vector2();
		}
		// Random texture variant, fixed per block position.
		int turn = -1;
		const int variants = t.rotation[id];
		if (in.rotate && variants != NONE) {
			const int64_t wx = in.at.x + i % P - 1;
			const int64_t wy = in.at.y + i / P2 - 1;
			const int64_t wz = in.at.z + (i / P) % P - 1;
			uint64_t h = uint64_t(wx * 3129871) ^ uint64_t(wz * 116129781) ^ uint64_t(wy);
			h = h * h * 42317861ull + h * 11ull;
			turn = int((int64_t(h) >> 16) & 7);
			turn &= variants == TURN ? 3 : 6;
		}

		for (int face = 0; face < 6; face++) {
			const int front = i + OFFSETS.face[face];
			const int neighbor = padded[front];
			if (t.opaque[neighbor] == 1 && (face != 0 || (top >= 1.0 && !sloped)))
				continue;
			if (self_culls && t.cull_group[neighbor] == group)
				continue;
			// Water under ice: only the ice face (not lava, which would leave a hole).
			if (is_liquid && t.layer[id] == TRANSLUCENT && neighbor != AIR && t.layer[neighbor] == TRANSLUCENT)
				continue;
			const int index = id * 6 + face;
			const bool flowing_top = face == 0 && flow != Vector2();
			const double tile = flowing_top ? t.face_tiles[id * 6 + 2] : t.face_tiles[index];
			const float overlay = float(t.face_overlays[index]);
			const int start = int(s.vertices.size());
			const int front_light = light[front];
			const int front_glow = block_light[front];
			int ao_sum_02 = 0, ao_sum_13 = 0;
			for (int c = 0; c < 4; c++) {
				int ao = 3;
				double level = front_light;
				double glow_level = front_glow;
				if (smooth) {
					const int base = face * 12 + c * 3;
					const int a = front + OFFSETS.ao[base];
					const int b = front + OFFSETS.ao[base + 1];
					const bool side_a = t.opaque[padded[a]] == 1;
					const bool side_b = t.opaque[padded[b]] == 1;
					int total = front_light, total_glow = front_glow, count = 1;
					if (!side_a) {
						total += light[a];
						total_glow += block_light[a];
						count++;
					}
					if (!side_b) {
						total += light[b];
						total_glow += block_light[b];
						count++;
					}
					if (side_a && side_b) {
						ao = 0;
					} else {
						const int d = front + OFFSETS.ao[base + 2];
						const bool diagonal = t.opaque[padded[d]] == 1;
						if (!diagonal) {
							total += light[d];
							total_glow += block_light[d];
							count++;
						}
						ao = 3 - int(side_a) - int(side_b) - int(diagonal);
					}
					level = double(total) / count;
					glow_level = double(total_glow) / count;
					if (!use_ao)
						ao = 3;
				}
				if (c == 0 || c == 2)
					ao_sum_02 += ao;
				else
					ao_sum_13 += ao;
				Vector3 corner = FACE_CORNERS[face][c];
				if (corner.y > 0.5f) {
					if (sloped)
						corner.y = corner_heights[int(corner.x) + 2 * int(corner.z)];
					else if (top < 1.0)
						corner.y = float(top);
				}
				s.add(origin + corner, NORMALS[face], Vector2(float(tile + ao * 0.25), overlay),
						Color(tint.r, tint.g, tint.b, float(level / MAX_LIGHT)), int(std::llround(glow_level * 17.0)));
			}
			int mode = t.uv_mode[index];
			if (turn >= 0)
				mode = face < 2 ? turn : (turn & 4);
			for (int c = 0; c < 4; c++) {
				Vector2 uv = CORNER_UVS[(c + mode) & 3];
				if (flowing_top) {
					const Vector3 &corner = FACE_CORNERS[0][c];
					const Vector2 d(corner.x - 0.5f, corner.z - 0.5f);
					const float across = d.dot(Vector2(-flow.y, flow.x));
					const float along = d.dot(flow);
					s.uvs.push_back(Vector2(float(0.5 + double(across) * 0.5), float(0.5 + double(along) * 0.5)));
					continue;
				}
				if (mode & 4)
					uv.x = 1.0f - uv.x;
				if (face >= 2) {
					if (c < 2 && sloped)
						uv.y = float(1.0 - double(s.vertices[start + c].y - origin.y));
					else if (c < 2 && top < 1.0)
						uv.y = float(1.0 - top);
				}
				s.uvs.push_back(uv);
			}
			// Split along the diagonal through the darker corners.
			s.indices.push_back(start);
			s.indices.push_back(start + 1);
			if (ao_sum_02 > ao_sum_13) {
				const int rest[4] = { start + 3, start + 1, start + 2, start + 3 };
				s.indices.insert(s.indices.end(), rest, rest + 4);
			} else {
				const int rest[4] = { start + 2, start, start + 2, start + 3 };
				s.indices.insert(s.indices.end(), rest, rest + 4);
			}
			// Water surface: also a copy facing down.
			if (face == 0 && is_liquid) {
				const int below = int(s.vertices.size());
				for (int c = 0; c < 4; c++) {
					const int k = start + c;
					s.vertices.push_back(s.vertices[k]);
					s.normals.push_back(NORMALS[1]);
					s.layers.push_back(s.layers[k]);
					s.colors.push_back(s.colors[k]);
					for (int b = 0; b < 4; b++)
						s.glow.push_back(s.glow[k * 4 + b]);
					s.uvs.push_back(s.uvs[k]);
				}
				const int order[6] = { 0, 2, 1, 0, 3, 2 };
				for (int k : order)
					s.indices.push_back(below + k);
			}
		}
	}
}

} // namespace

void NativeMesher::set_tables(const Dictionary &d) {
	auto t = std::make_shared<Tables>();
	t->opaque = copy_of<uint8_t>(PackedByteArray(d["is_opaque"]));
	t->layer = copy_of<uint8_t>(PackedByteArray(d["layer"]));
	t->cull_self = copy_of<uint8_t>(PackedByteArray(d["cull_self"]));
	t->collides = copy_of<uint8_t>(PackedByteArray(d["collides"]));
	t->liquid = copy_of<uint8_t>(PackedByteArray(d["liquid"]));
	t->biome_tint = copy_of<uint8_t>(PackedByteArray(d["biome_tint"]));
	t->rotation = copy_of<uint8_t>(PackedByteArray(d["random_rotation"]));
	t->shape = copy_of<uint8_t>(PackedByteArray(d["shape"]));
	t->face_tiles = copy_of<int32_t>(PackedInt32Array(d["face_tiles"]));
	t->face_overlays = copy_of<int32_t>(PackedInt32Array(d["face_overlays"]));
	t->uv_mode = copy_of<int32_t>(PackedInt32Array(d["uv_mode"]));
	t->cull_group = copy_of<int32_t>(PackedInt32Array(d["cull_group"]));
	t->liquid_level = copy_of<int32_t>(PackedInt32Array(d["liquid_level"]));
	t->model = copy_of<int32_t>(PackedInt32Array(d["model"]));
	t->height = copy_of<float>(PackedFloat32Array(d["height"]));
	t->tints = copy_of<Color>(PackedColorArray(d["tints"]));
	t->count = t->opaque.size();
	const Array models = d["models"];
	for (int64_t m = 0; m < models.size(); m++) {
		std::vector<Quad> quads;
		const Array list = models[m];
		for (int64_t q = 0; q < list.size(); q++) {
			const Array spec = list[q];
			Quad quad;
			const PackedVector3Array corners = spec[0];
			const PackedVector2Array uvs = spec[2];
			for (int c = 0; c < 4; c++) {
				quad.corners[c] = corners[c];
				quad.uvs[c] = uvs[c];
			}
			quad.normal = spec[1];
			quad.layer = int(spec[3]);
			quads.push_back(quad);
		}
		t->models.push_back(std::move(quads));
	}
	const size_t n = t->count;
	bool ok = t->layer.size() >= n && t->cull_self.size() >= n && t->collides.size() >= n && t->liquid.size() >= n &&
			t->biome_tint.size() >= n && t->rotation.size() >= n && t->shape.size() >= n &&
			t->face_tiles.size() >= n * 6 && t->face_overlays.size() >= n * 6 && t->uv_mode.size() >= n * 6 &&
			t->cull_group.size() >= n && t->liquid_level.size() >= n && t->model.size() >= n &&
			t->height.size() >= n && t->tints.size() >= n;
	ERR_FAIL_COND_MSG(!ok, "NativeMesher: block tables of different sizes.");
	std::shared_ptr<const Tables> shared = t;
	std::atomic_store(&g_tables, shared);
	// "fast": the tables that differ with Fast graphics' leaves.
	std::shared_ptr<const Tables> fast_shared;
	if (d.has("fast")) {
		const Dictionary f = d["fast"];
		auto ft = std::make_shared<Tables>(*t);
		ft->opaque = copy_of<uint8_t>(PackedByteArray(f["is_opaque"]));
		ft->layer = copy_of<uint8_t>(PackedByteArray(f["layer"]));
		ft->face_tiles = copy_of<int32_t>(PackedInt32Array(f["face_tiles"]));
		if (ft->opaque.size() >= n && ft->layer.size() >= n && ft->face_tiles.size() >= n * 6)
			fast_shared = ft;
	}
	std::atomic_store(&g_fast_tables, fast_shared);
}

bool NativeMesher::has_tables() {
	return tables() != nullptr;
}

Array NativeMesher::build_chunk(const Vector3i &coord, const PackedInt32Array &center, const Dictionary &neighbors,
		const PackedByteArray &center_light, const Dictionary &neighbor_light,
		const PackedByteArray &center_block_light, const Dictionary &neighbor_block_light,
		const PackedColorArray &grass, const PackedColorArray &foliage, int smooth, bool rotate, bool fast) {
	Array result;
	const std::shared_ptr<const Tables> t = tables(fast);
	ERR_FAIL_COND_V_MSG(!t, result, "NativeMesher: set_tables() first.");
	std::vector<int32_t> padded(PADDED, 0);
	std::vector<uint8_t> light(PADDED, MAX_LIGHT);
	std::vector<uint8_t> glow(PADDED, 0);
	pad(padded.data(), center, neighbors);
	pad(light.data(), center_light, neighbor_light);
	pad(glow.data(), center_block_light, neighbor_block_light);
	// Unknown ids (newer saves) count as air.
	for (int32_t &id : padded)
		if (id < 0 || size_t(id) >= t->count)
			id = AIR;

	Dictionary surfaces;
	bool see_through = false;
	for (const int32_t id : padded)
		if (t->opaque[id] == 0) {
			see_through = true;
			break;
		}
	if (see_through) {
		std::vector<int> cells[3];
		for (int y = 0; y < SIZE; y++)
			for (int z = 0; z < SIZE; z++) {
				const int row = 1 + P * ((z + 1) + P * (y + 1));
				for (int x = 0; x < SIZE; x++) {
					const int i = row + x;
					const int id = padded[i];
					if (id == AIR)
						continue;
					const int layer = t->layer[id];
					cells[layer == OPAQUE ? 0 : (layer == CUTOUT ? 1 : 2)].push_back(i);
				}
			}
		const bool colors = grass.size() == 256 && foliage.size() == 256;
		const Input in = { padded.data(), light.data(), glow.data(), colors ? grass.ptr() : nullptr,
			colors ? foliage.ptr() : nullptr, rotate, coord * SIZE };
		for (int layer = 0; layer < 3; layer++) {
			if (cells[layer].empty())
				continue;
			Surface s;
			const bool translucent = layer == TRANSLUCENT;
			build_layer(*t, in, cells[layer], !translucent && smooth > 0, !translucent && smooth >= 2, s);
			if (!s.vertices.empty())
				surfaces[layer] = s.to_arrays();
		}
	}
	result.append(surfaces);
	result.append(connectivity(padded.data(), *t));
	return result;
}

void NativeMesher::_bind_methods() {
	ClassDB::bind_static_method("NativeMesher", D_METHOD("set_tables", "tables"), &NativeMesher::set_tables);
	ClassDB::bind_static_method("NativeMesher", D_METHOD("has_tables"), &NativeMesher::has_tables);
	ClassDB::bind_static_method("NativeMesher",
			D_METHOD("build_chunk", "coord", "center", "neighbors", "center_light", "neighbor_light",
					"center_block_light", "neighbor_block_light", "grass", "foliage", "smooth", "rotate", "fast"),
			&NativeMesher::build_chunk, DEFVAL(false));
}

} // namespace voxel
