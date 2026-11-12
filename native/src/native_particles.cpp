#include "native_particles.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/aabb.hpp>

#include <algorithm>
#include <cstring>
#include <cmath>
#include <unordered_map>
#include <unordered_set>

using namespace godot;

namespace voxel {

namespace {
constexpr float GRAVITY = 0.04f;
constexpr int STRIDE = 20; // transform 12, color 4, custom 4
constexpr int STEP = 256;

inline int floor_int(float v) {
	return int(std::floor(v));
}
} // namespace

void NativeParticles::setup(const Array &collision, const Array &animations, int max_count) {
	max_particles = max_count;
	boxes.clear();
	for (int64_t id = 0; id < collision.size(); id++) {
		std::vector<float> list;
		const Array shapes = collision[id];
		for (int64_t b = 0; b < shapes.size(); b++) {
			const AABB box = shapes[b];
			const Vector3 end = box.position + box.size;
			list.insert(list.end(), { box.position.x, box.position.y, box.position.z, end.x, end.y, end.z });
		}
		boxes.push_back(std::move(list));
	}
	anims.clear();
	for (int64_t a = 0; a < animations.size(); a++) {
		std::vector<Vector2> frames;
		const Array list = animations[a];
		for (int64_t f = 0; f < list.size(); f++)
			frames.push_back(list[f]);
		anims.push_back(std::move(frames));
	}
}

// Blocks.blocks_point(): inside one of the block's boxes (AABB.has_point,
// edges included).
bool NativeParticles::blocks_point(int32_t id, const Vector3 &p) const {
	if (id < 0 || size_t(id) >= boxes.size())
		return false;
	const std::vector<float> &list = boxes[id];
	for (size_t b = 0; b + 5 < list.size(); b += 6)
		if (p.x >= list[b] && p.x <= list[b + 3] && p.y >= list[b + 1] && p.y <= list[b + 4] && p.z >= list[b + 2] &&
				p.z <= list[b + 5])
			return true;
	return false;
}

bool NativeParticles::add(const Vector3 &start, const Vector3 &velocity, const Color &custom, const Color &color,
		int life, float gravity, bool fade, int anim, float min_light, float brightness) {
	if (int(particles.size()) >= max_particles)
		return false;
	Particle p;
	p.position = p.previous = start;
	p.velocity = velocity;
	p.custom = custom;
	p.color = color;
	p.life = std::max(life, 1);
	p.gravity = gravity;
	p.fade = fade;
	p.anim = anim >= 0 && size_t(anim) < anims.size() ? anim : -1;
	p.min_light = min_light;
	p.brightness = brightness;
	particles.push_back(p);
	return true;
}

PackedInt32Array NativeParticles::cells_needed() {
	cell_keys.clear();
	std::unordered_set<int64_t> seen;
	PackedInt32Array cells;
	for (const Particle &p : particles) {
		const bool moves_on_blocks = p.gravity > 0.0f;
		if (!moves_on_blocks && p.min_light < 0.0f)
			continue;
		Vector3 velocity = p.velocity;
		velocity.y -= GRAVITY * p.gravity;
		const Vector3 next = p.position + velocity;
		const int x0 = floor_int(std::min(p.position.x, next.x)), x1 = floor_int(std::max(p.position.x, next.x));
		const int y0 = floor_int(std::min(p.position.y, next.y)), y1 = floor_int(std::max(p.position.y, next.y));
		const int z0 = floor_int(std::min(p.position.z, next.z)), z1 = floor_int(std::max(p.position.z, next.z));
		for (int x = x0; x <= x1; x++)
			for (int y = y0; y <= y1; y++)
				for (int z = z0; z <= z1; z++) {
					const int64_t k = key(x, y, z);
					if (!seen.insert(k).second)
						continue;
					cell_keys.push_back(k);
					cells.append(x);
					cells.append(y);
					cells.append(z);
				}
	}
	return cells;
}

void NativeParticles::tick(const PackedInt32Array &ids, const PackedFloat32Array &brightness) {
	struct Info {
		int32_t id;
		float brightness;
	};
	std::unordered_map<int64_t, Info> cells;
	cells.reserve(cell_keys.size());
	for (size_t n = 0; n < cell_keys.size(); n++)
		cells[cell_keys[n]] = { n < size_t(ids.size()) ? ids[n] : 0, n < size_t(brightness.size()) ? brightness[n] : 1.0f };
	auto info = [&](const Vector3 &point) -> const Info * {
		const auto found = cells.find(key(floor_int(point.x), floor_int(point.y), floor_int(point.z)));
		return found == cells.end() ? nullptr : &found->second;
	};
	auto solid = [&](const Vector3 &point) -> bool {
		const Info *cell = info(point);
		if (cell == nullptr)
			return false;
		return blocks_point(cell->id, point - Vector3(std::floor(point.x), std::floor(point.y), std::floor(point.z)));
	};
	size_t i = 0;
	while (i < particles.size()) {
		Particle &p = particles[i];
		p.age++;
		if (p.age >= p.life) {
			p = particles.back(); // the last one takes its place
			particles.pop_back();
			continue;
		}
		if (p.anim >= 0) {
			const std::vector<Vector2> &frames = anims[p.anim];
			const int n = int(frames.size());
			if (n > 0) {
				const Vector2 &frame = frames[std::min(p.age * n / p.life, n - 1)];
				p.custom.g = frame.x;
				p.custom.b = frame.y;
			}
		}
		Vector3 position = p.position;
		p.previous = position;
		Vector3 velocity = p.velocity;
		velocity.y -= GRAVITY * p.gravity;
		bool on_ground = false;
		if (p.gravity > 0.0f) {
			// Stop on blocks, axis by axis (y, x, z).
			const int order[3] = { 1, 0, 2 };
			for (const int axis : order) {
				Vector3 next = position;
				next[axis] += velocity[axis];
				if (solid(next)) {
					if (axis == 1 && velocity.y < 0.0f)
						on_ground = true;
					velocity[axis] = 0.0f;
				} else {
					position = next;
				}
			}
		} else {
			position += velocity;
		}
		velocity *= 0.98f;
		if (on_ground) {
			velocity.x *= 0.7f;
			velocity.z *= 0.7f;
		}
		p.position = position;
		p.velocity = velocity;
		if (p.min_light >= 0.0f) {
			const Info *cell = info(position);
			if (cell)
				p.brightness = cell->brightness;
		}
		i++;
	}
}

void NativeParticles::draw(const Ref<MultiMesh> &multimesh, float alpha) {
	if (multimesh.is_null())
		return;
	const int total = int(particles.size());
	const int capacity = std::max((total + STEP - 1) / STEP, 1) * STEP;
	if (multimesh->get_instance_count() != capacity)
		multimesh->set_instance_count(capacity);
	buffer.assign(size_t(capacity) * STRIDE, 0.0f);
	for (int i = 0; i < total; i++) {
		const Particle &p = particles[i];
		const Vector3 at = p.previous.lerp(p.position, alpha);
		float *b = buffer.data() + size_t(i) * STRIDE;
		// Basis identity, origin `at` (rows of a 3 x 4 matrix).
		b[0] = 1.0f;
		b[3] = at.x;
		b[5] = 1.0f;
		b[7] = at.y;
		b[10] = 1.0f;
		b[11] = at.z;
		const float light = p.min_light < 0.0f ? 1.0f : std::max(p.brightness, p.min_light);
		b[12] = p.color.r * light;
		b[13] = p.color.g * light;
		b[14] = p.color.b * light;
		b[15] = p.fade ? p.color.a * (1.0f - float(p.age) / p.life) : p.color.a;
		b[16] = p.custom.r;
		b[17] = p.custom.g;
		b[18] = p.custom.b;
		b[19] = p.custom.a;
	}
	PackedFloat32Array data;
	data.resize(int64_t(buffer.size()));
	memcpy(data.ptrw(), buffer.data(), buffer.size() * sizeof(float));
	multimesh->set_buffer(data);
	multimesh->set_visible_instance_count(total);
}

void NativeParticles::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "collision", "animations", "max_count"), &NativeParticles::setup);
	ClassDB::bind_method(D_METHOD("add", "start", "velocity", "custom", "color", "life", "gravity", "fade", "anim",
								 "min_light", "brightness"),
			&NativeParticles::add);
	ClassDB::bind_method(D_METHOD("count"), &NativeParticles::count);
	ClassDB::bind_method(D_METHOD("clear"), &NativeParticles::clear);
	ClassDB::bind_method(D_METHOD("cells_needed"), &NativeParticles::cells_needed);
	ClassDB::bind_method(D_METHOD("tick", "ids", "brightness"), &NativeParticles::tick);
	ClassDB::bind_method(D_METHOD("draw", "multimesh", "alpha"), &NativeParticles::draw);
}

} // namespace voxel
