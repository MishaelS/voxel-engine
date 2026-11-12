#pragma once

#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <vector>

namespace voxel {

// BlockParticles' simulation and drawing in native code: every particle's
// movement (gravity, drag, stopping on blocks axis by axis), its animation
// frames, its light (taken each tick where it is, like the classic game) and
// the MultiMesh buffer written in one go each frame.
//
// A tick is two calls: cells_needed() lists the block cells the particles can
// touch this tick (each once), the world looks up their blocks and light,
// tick() moves the particles with them. So the world is asked a few hundred
// times a tick instead of three times per particle.
class NativeParticles : public godot::RefCounted {
	GDCLASS(NativeParticles, godot::RefCounted)

protected:
	static void _bind_methods();

private:
	struct Particle {
		godot::Vector3 position, previous, velocity;
		godot::Color custom; // layer, u, v, size (particle.gdshader)
		godot::Color color;
		int32_t age = 0, life = 1;
		float gravity = 0.0f;
		int32_t anim = -1;
		float min_light = -1.0f; // < 0: not lit (glows); else the darkest it gets
		float brightness = 1.0f;
		bool fade = false;
	};
	std::vector<Particle> particles;
	int max_particles = 4000;
	// Per block id: collision boxes (position, end) for blocks_point().
	std::vector<std::vector<float>> boxes;
	// Animations: frames (u, v) of each.
	std::vector<std::vector<godot::Vector2>> anims;
	// The cells of the last cells_needed(), in order.
	std::vector<int64_t> cell_keys;
	std::vector<float> buffer;

	static int64_t key(int x, int y, int z) {
		return (int64_t(x + (1 << 20)) << 42) | (int64_t(y + (1 << 20)) << 21) | int64_t(z + (1 << 20));
	}
	bool blocks_point(int32_t id, const godot::Vector3 &local) const;

public:
	// Blocks.collision_table (per id an array of AABB) and BlockParticles.ANIMS
	// (per animation an array of (u, v) frames, 0..1 in the atlas).
	void setup(const godot::Array &collision, const godot::Array &animations, int max_count);
	// A new particle; false when there are too many. `min_light` < 0: drawn
	// at full color (flames, hearts); else lit, never darker than it.
	bool add(const godot::Vector3 &start, const godot::Vector3 &velocity, const godot::Color &custom,
			const godot::Color &color, int life, float gravity, bool fade, int anim, float min_light, float brightness);
	int count() const { return int(particles.size()); }
	void clear() { particles.clear(); }
	// x, y, z of every cell the particles may touch this tick.
	godot::PackedInt32Array cells_needed();
	// One game tick with the blocks and brightness of those cells.
	void tick(const godot::PackedInt32Array &ids, const godot::PackedFloat32Array &brightness);
	// Writes the particles, `alpha` of the way from the last tick to this one,
	// into the MultiMesh (instances grow in steps of 256; the rest are hidden).
	void draw(const godot::Ref<godot::MultiMesh> &multimesh, float alpha);
};

} // namespace voxel
