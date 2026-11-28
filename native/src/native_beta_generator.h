#pragma once

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <cstdint>
#include <vector>

namespace voxel {

class Pcg;

// BetaGenerator.generate_blocks() in native code, block for block the same:
// the same noises (the generator's own FastNoiseLite objects), the same
// random numbers (Godot's PCG32, seeds from Godot's hash()) drawn in the
// same order. Read-only after setup(): one instance serves all worker
// threads.
class NativeBetaGenerator : public godot::RefCounted {
	GDCLASS(NativeBetaGenerator, godot::RefCounted)

public:
	// Noises in BetaGenerator's order.
	enum Noise { MIN, MAX, MAIN, DEPTH, SCALE, TEMPERATURE, HUMIDITY, DETAIL, SAND, GRAVEL, SOIL, TREE, NOISE_COUNT };

protected:
	static void _bind_methods();

private:
	int64_t world_seed = 0;
	bool tall = true;
	int h = 192; // the classic part's height
	int cells = 24;
	int shift = 64; // where the classic part starts in the column
	bool deep = true; // the deep layer under it (old 256 high worlds)
	godot::Ref<godot::FastNoiseLite> noises[NOISE_COUNT];

	// Block ids.
	int32_t stone = 0, water = 0, lava = 0, bedrock = 0, sand = 0, gravel = 0, sandstone = 0, dirt = 0, clay = 0,
			cactus = 0, reeds = 0, ice = 0, snow_layer = 0, oak_log = 0, oak_leaves = 0, birch_log = 0,
			birch_leaves = 0, spruce_log = 0, spruce_leaves = 0, tall_grass = 0, fern = 0, dandelion = 0, rose = 0,
			dead_bush = 0, brown_mushroom = 0, red_mushroom = 0, water_spring = 0, lava_spring = 0, cobble = 0,
			mossy = 0, dungeon_chest = 0;
	int32_t tree_ground[7] = {};
	int32_t spawners[3] = {}; // zombie, skeleton, spider
	std::vector<int32_t> pumpkins;
	int32_t ores[8] = {}; // dirt, gravel, coal, iron, gold, redstone, diamond, lapis
	int32_t biome_top[11] = {}, biome_filler[11] = {}, biome_trees[11] = {};
	uint8_t biome_cold[11] = {};
	bool new_biomes = false;
	// Per block id.
	std::vector<uint8_t> collides, liquid, opaque, grass_named, leaves;

	godot::Ref<godot::FastNoiseLite> noise(Noise n) const { return noises[n]; }
	double noise2(Noise n, double x, double z) const;
	double noise3(Noise n, double x, double y, double z) const;
	uint64_t column_seed(int64_t cx, int64_t cz, int64_t salt) const;
	double temperature(double x, double z) const;
	double humidity(double x, double z) const;
	void climate(int cx, int cz, float *out) const;

	int shape_terrain(int32_t *blocks, int cx, int cz) const;
	void replace_surface(int32_t *blocks, int cx, int cz, const uint8_t *biomes, int stone_top) const;
	void carve_caves(int32_t *blocks, int size, int cx, int cz, int salt, int start_span, int max_y, int lava_level) const;
	void carve_tunnel(int32_t *blocks, int size, int cx, int cz, uint64_t seed_value, float px, float py, float pz,
			double width, double yaw, double pitch, int step, int length, double height_ratio, int max_y,
			int lava_level) const;
	void carve_ellipsoid(int32_t *blocks, int size, int cx, int cz, float x, float y, float z, double radius,
			double radius_y, int top_y, int lava_level) const;
	void place_ores(int32_t *blocks, int size, Pcg &rng, int top, bool deep, bool upper_only) const;
	void place_vein(int32_t *blocks, int size, Pcg &rng, int32_t id, int vein_size, float sx, float sy, float sz,
			int top) const;
	void place_lake(int32_t *blocks, Pcg &rng, int y, int32_t fill) const;
	void place_dungeon(int32_t *blocks, Pcg &rng, int height) const;
	void place_trees(int32_t *blocks, int cx, int cz, const uint8_t *biomes, Pcg &rng) const;
	void place_plants(int32_t *blocks, const uint8_t *biomes, Pcg &rng) const;
	void plant_patch(int32_t *blocks, Pcg &rng, int32_t plant, int tries) const;
	void place_clay(int32_t *blocks, Pcg &rng) const;
	void place_cacti(int32_t *blocks, const uint8_t *biomes, Pcg &rng) const;
	void place_sugar_cane(int32_t *blocks, Pcg &rng) const;
	void place_mushrooms(int32_t *blocks, Pcg &rng) const;
	void place_springs(int32_t *blocks, Pcg &rng) const;
	void freeze(int32_t *blocks, const uint8_t *biomes) const;
	int surface_y(const int32_t *blocks, int x, int z) const;
	// Trees like Beta 1.7.3's (TreeShapes in GDScript, the same steps).
	int32_t at(const int32_t *blocks, int x, int y, int z) const;
	void put(int32_t *blocks, int x, int y, int z, int32_t id) const;
	bool is_leaves(int32_t id) const;
	bool is_ground(int32_t id) const;
	bool tree_free(int32_t id) const;
	void put_leaf(int32_t *blocks, int x, int y, int z, int32_t leaf) const;
	void put_log(int32_t *blocks, int x, int y, int z, int32_t log) const;
	bool ring_free(const int32_t *blocks, int x, int y, int z, int radius) const;
	bool oak(int32_t *blocks, Pcg &rng, int x, int y, int z, int32_t log, int32_t leaf, int min_height) const;
	bool spruce(int32_t *blocks, Pcg &rng, int x, int y, int z) const;
	bool pine(int32_t *blocks, Pcg &rng, int x, int y, int z) const;
	bool big_oak(int32_t *blocks, Pcg &rng, int x, int y, int z) const;
	int line_cells(const int a[3], const int b[3], int (*cells)[3], int max) const;
	int check_line(const int32_t *blocks, const int a[3], const int b[3]) const;
	bool can_stay(int32_t plant, int32_t ground) const;
	uint8_t table(const std::vector<uint8_t> &t, int32_t id) const {
		return id >= 0 && size_t(id) < t.size() ? t[id] : 0;
	}

public:
	// `config`: "seed", "tall", "noises" (the 12 FastNoiseLite in order),
	// "ids" (block name -> id), "pumpkins" (ids by facing), per-id tables
	// "collides", "liquid", "opaque", "grass_named" (name starts with
	// "grass_"), "leaves" (name ends with "_leaves").
	void setup(const godot::Dictionary &config);
	void set_tall(bool value);
	// The world's layout (WorldSave.layout): the classic part `height` high
	// from y `shift` up, mountains softened above the middle (`tall`), the deep
	// layer under it (`deep`).
	void set_layout(int shift, bool deep, int height, bool tall);
	void set_new_biomes(bool value);
	godot::PackedInt32Array generate_blocks(int cx, int cz) const;

	// For checking: Godot's own generator against ours (seed, then a mix of
	// randi / randf / randi_range): returns ours, the caller compares.
	static godot::PackedFloat64Array check_random(int64_t seed_value, int count);
};

} // namespace voxel
