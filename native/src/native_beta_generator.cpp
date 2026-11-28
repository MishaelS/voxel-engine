#include "native_beta_generator.h"

#include "pcg.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>

using namespace godot;

// Mirrors scripts/worldgen/beta_generator.gd and DungeonBehavior.place(): the
// comments there explain the why. Here everything must stay number for
// number the same: GDScript floats are doubles, Vector3 components are
// floats (so positions are rounded to float where the script keeps a
// Vector3), and every random number is drawn in the script's order
// (C++ leaves the order of function arguments open, so draws are always
// sequenced into locals first).

namespace voxel {

namespace {

constexpr double PI_D = 3.14159265358979323846;
constexpr double TAU_D = 6.28318530717958647692;
constexpr int AIR = 0;
constexpr int GRID_X = 4;
constexpr int GRID_Y = 8;
constexpr int CELLS_X = 16 / GRID_X;
constexpr double LIMIT_AMPLITUDE = 128.0;
constexpr double MAIN_AMPLITUDE = 25.5;
constexpr double DEPTH_AMPLITUDE = 8.2;
constexpr double SCALE_AMPLITUDE = 1023.0;
constexpr int CLIMATE_STEP = 4;
constexpr int CAVE_RANGE = 8;
constexpr int LAVA_LEVEL = 10;
constexpr int SEA = 64;
constexpr int LEGACY_CELLS = 16;
constexpr int LEGACY_SHIFT = 64;
constexpr int HEIGHT = 256;
constexpr int COLUMN_VOLUME = 16 * 16 * HEIGHT;
constexpr int DUNGEON_TRIES = 32;

// [veins per column, vein size, max height] (ids in NativeBetaGenerator::ores).
const int ORES[8][3] = { { 20, 32, 128 }, { 10, 32, 128 }, { 20, 16, 128 }, { 20, 8, 64 }, { 2, 8, 32 }, { 8, 7, 16 },
	{ 1, 7, 16 }, { 1, 6, 32 } };
const int DEEP_ORES[8][3] = { { 10, 32, 64 }, { 5, 32, 64 }, { 10, 16, 64 }, { 20, 8, 64 }, { 2, 8, 32 }, { 8, 7, 16 },
	{ 1, 7, 16 }, { 1, 6, 32 } };
// Tall grass patches by biome number (BIOME_NAMES order).
const int GRASS_PATCHES[11] = { 0, 1, 1, 2, 2, 10, 1, 1, 10, 0, 0 };
// New worlds' (BetaGenerator.NEW_GRASS_PATCHES, NEW_TREES).
const int NEW_GRASS_PATCHES[11] = { 0, 3, 6, 2, 2, 10, 1, 1, 10, 0, 0 };
enum Biome { TUNDRA, TAIGA, SWAMPLAND, FOREST, SEASONAL_FOREST, RAINFOREST, SAVANNA, SHRUBLAND, PLAINS, DESERT, GLACIER };
constexpr int BIOME_COUNT = 11;
// New worlds' glacier and swamp (BetaGenerator: the same numbers).
constexpr double GLACIER_TEMP = 0.3;
constexpr double SWAMP_HUMID = 0.42;
constexpr double SWAMP_TEMP = 0.78;
constexpr double BLEND = 0.05;
constexpr double SWAMP_LEVEL = 7.9;
constexpr double SWAMP_FLAT = 9.0;
constexpr double POOL_STRETCH = 0.3;
constexpr double POOL_OVER = 0.04;
constexpr double GLACIER_LEVEL = 8.45;
constexpr double GLACIER_FLAT = 3.0;
const int SIDES[4][2] = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } };

inline int idx(int x, int y, int z) {
	return x + 16 * (z + 16 * y);
}

int biome_index(double temp, double humid) {
	if (temp < 0.1)
		return TUNDRA;
	humid *= temp;
	if (humid < 0.2) {
		if (temp < 0.5)
			return TUNDRA;
		return temp < 0.95 ? SAVANNA : DESERT;
	}
	if (humid > 0.5 && temp < 0.7)
		return SWAMPLAND;
	if (temp < 0.5)
		return TAIGA;
	if (temp < 0.97)
		return humid < 0.35 ? SHRUBLAND : FOREST;
	if (humid < 0.45)
		return PLAINS;
	return humid < 0.9 ? SEASONAL_FOREST : RAINFOREST;
}

// BetaGenerator.biome_index_new.
int biome_index_new(double temp, double humid) {
	if (temp < GLACIER_TEMP)
		return GLACIER;
	humid *= temp;
	if (humid < 0.2) {
		if (temp < 0.5)
			return TUNDRA;
		return temp < 0.95 ? SAVANNA : DESERT;
	}
	if (humid > SWAMP_HUMID && temp < SWAMP_TEMP)
		return SWAMPLAND;
	if (temp < 0.5)
		return TAIGA;
	if (temp < 0.97)
		return humid < 0.35 ? SHRUBLAND : FOREST;
	if (humid < 0.45)
		return PLAINS;
	return humid < 0.9 ? SEASONAL_FOREST : RAINFOREST;
}

inline double clamp01(double v) {
	return v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);
}

inline int floori(double v) {
	return int(std::floor(v));
}

std::vector<uint8_t> bytes(const Variant &v) {
	const PackedByteArray array = v;
	std::vector<uint8_t> result(array.size());
	if (array.size() > 0)
		memcpy(result.data(), array.ptr(), array.size());
	return result;
}

} // namespace

// --- Setup ----------------------------------------------------------------------------

void NativeBetaGenerator::setup(const Dictionary &config) {
	world_seed = config["seed"];
	const Array list = config["noises"];
	ERR_FAIL_COND_MSG(list.size() != NOISE_COUNT, "NativeBetaGenerator: 12 noises expected.");
	for (int n = 0; n < NOISE_COUNT; n++)
		noises[n] = list[n];
	const Dictionary ids = config["ids"];
	auto id = [&](const char *name) -> int32_t { return int32_t(int64_t(ids.get(name, 0))); };
	stone = id("stone");
	water = id("water");
	lava = id("lava");
	bedrock = id("bedrock");
	sand = id("sand");
	gravel = id("gravel");
	sandstone = id("sandstone");
	dirt = id("dirt");
	clay = id("clay");
	cactus = id("cactus");
	reeds = id("sugar_cane_block");
	ice = id("ice");
	snow_layer = id("snow_layer");
	oak_log = id("oak_log");
	oak_leaves = id("oak_leaves");
	birch_log = id("birch_log");
	birch_leaves = id("birch_leaves");
	spruce_log = id("spruce_log");
	spruce_leaves = id("spruce_leaves");
	tall_grass = id("tall_grass");
	fern = id("fern");
	dandelion = id("dandelion");
	rose = id("rose");
	dead_bush = id("dead_bush");
	brown_mushroom = id("brown_mushroom");
	red_mushroom = id("red_mushroom");
	water_spring = id("water_spring");
	lava_spring = id("lava_spring");
	cobble = id("cobblestone");
	mossy = id("mossy_cobblestone");
	dungeon_chest = id("dungeon_chest");
	spawners[0] = id("mob_spawner_zombie");
	spawners[1] = id("mob_spawner_skeleton");
	spawners[2] = id("mob_spawner_spider");
	const char *ground[7] = { "grass_plains", "grass_forest", "grass_taiga", "grass_swamp", "grass_savanna",
		"snowy_grass", "dirt" };
	for (int k = 0; k < 7; k++)
		tree_ground[k] = id(ground[k]);
	const char *ore_names[8] = { "dirt", "gravel", "coal_ore", "iron_ore", "gold_ore", "redstone_ore",
		"diamond_ore", "lapis_ore" };
	for (int k = 0; k < 8; k++)
		ores[k] = id(ore_names[k]);
	const char *tops[BIOME_COUNT] = { "snowy_grass", "snowy_grass", "grass_swamp", "grass_forest", "grass_forest",
		"grass_forest", "grass_savanna", "grass_savanna", "grass_plains", "sand", "snow" };
	const int32_t snow = id("snow");
	for (int b = 0; b < BIOME_COUNT; b++) {
		biome_top[b] = id(tops[b]);
		biome_filler[b] = b == DESERT ? sand : (b == GLACIER ? snow : dirt);
		biome_cold[b] = (b <= TAIGA || b == GLACIER) ? 1 : 0;
	}
	set_new_biomes(false);
	pumpkins.clear();
	const PackedInt32Array pumpkin_ids = config["pumpkins"];
	for (int64_t k = 0; k < pumpkin_ids.size(); k++)
		pumpkins.push_back(pumpkin_ids[k]);
	collides = bytes(config["collides"]);
	liquid = bytes(config["liquid"]);
	opaque = bytes(config["opaque"]);
	grass_named = bytes(config["grass_named"]);
	leaves = bytes(config["leaves"]);
	set_tall(config.get("tall", true));
}

void NativeBetaGenerator::set_tall(bool value) {
	set_layout(LEGACY_SHIFT, true, value ? 192 : 128, value);
}

// New worlds' biomes (BetaGenerator.new_biomes): the glacier, the flat
// marshy swamp, more trees in the taiga.
void NativeBetaGenerator::set_new_biomes(bool value) {
	new_biomes = value;
	const int trees[BIOME_COUNT] = { -20, 5, 0, 5, 2, 5, 0, 0, -20, -20, -20 };
	for (int b = 0; b < BIOME_COUNT; b++)
		biome_trees[b] = trees[b];
	if (new_biomes) {
		biome_trees[TAIGA] = 8;
		biome_trees[SWAMPLAND] = 5;
	}
}

void NativeBetaGenerator::set_layout(int new_shift, bool new_deep, int height, bool new_tall) {
	shift = std::clamp(new_shift, 0, LEGACY_SHIFT);
	deep = new_deep;
	h = std::clamp(height - height % GRID_Y, 128, HEIGHT - shift);
	tall = new_tall;
	cells = h / GRID_Y;
}

// --- Noise, random numbers, climate --------------------------------------------------

double NativeBetaGenerator::noise2(Noise n, double x, double z) const {
	return noises[n]->get_noise_2d(real_t(x), real_t(z));
}

double NativeBetaGenerator::noise3(Noise n, double x, double y, double z) const {
	return noises[n]->get_noise_3d(real_t(x), real_t(y), real_t(z));
}

// WorldGenerator.column_rng(): the seed hash([world_seed, cx, cz, salt]).
uint64_t NativeBetaGenerator::column_seed(int64_t cx, int64_t cz, int64_t salt) const {
	Array key;
	key.append(world_seed);
	key.append(cx);
	key.append(cz);
	key.append(salt);
	return uint64_t(int64_t(UtilityFunctions::hash(key)));
}

double NativeBetaGenerator::temperature(double x, double z) const {
	return clamp01(0.62 + noise2(TEMPERATURE, x, z) * 0.9 + noise2(DETAIL, x, z) * 0.03);
}

double NativeBetaGenerator::humidity(double x, double z) const {
	return clamp01(0.5 + noise2(HUMIDITY, x, z) * 0.9 + noise2(DETAIL, z, x) * 0.03);
}

void NativeBetaGenerator::climate(int cx, int cz, float *out) const {
	constexpr int CELLS = 16 / CLIMATE_STEP + 1;
	float temps[CELLS * CELLS];
	float humids[CELLS * CELLS];
	for (int gz = 0; gz < CELLS; gz++)
		for (int gx = 0; gx < CELLS; gx++) {
			const int wx = cx * 16 + gx * CLIMATE_STEP;
			const int wz = cz * 16 + gz * CLIMATE_STEP;
			temps[gx + gz * CELLS] = float(temperature(wx, wz));
			humids[gx + gz * CELLS] = float(humidity(wx, wz));
		}
	for (int z = 0; z < 16; z++) {
		const int gz = z / CLIMATE_STEP;
		const double fz = double(z % CLIMATE_STEP) / CLIMATE_STEP;
		for (int x = 0; x < 16; x++) {
			const int gx = x / CLIMATE_STEP;
			const double fx = double(x % CLIMATE_STEP) / CLIMATE_STEP;
			const int i00 = gx + gz * CELLS;
			const double t0 = double(temps[i00]) + (double(temps[i00 + 1]) - double(temps[i00])) * fx;
			const double t1 = double(temps[i00 + CELLS]) + (double(temps[i00 + CELLS + 1]) - double(temps[i00 + CELLS])) * fx;
			const double h0 = double(humids[i00]) + (double(humids[i00 + 1]) - double(humids[i00])) * fx;
			const double h1 = double(humids[i00 + CELLS]) + (double(humids[i00 + CELLS + 1]) - double(humids[i00 + CELLS])) * fx;
			out[x + 16 * z] = float(t0 + (t1 - t0) * fz);
			out[256 + x + 16 * z] = float(h0 + (h1 - h0) * fz);
		}
	}
}

// --- Generation -----------------------------------------------------------------------

PackedInt32Array NativeBetaGenerator::generate_blocks(int cx, int cz) const {
	PackedInt32Array result;
	result.resize(COLUMN_VOLUME);
	int32_t *column = result.ptrw();
	std::fill(column, column + shift * 256, stone);
	std::fill(column + shift * 256, column + COLUMN_VOLUME, AIR);
	int32_t *upper = column + shift * 256;
	const int upper_size = 256 * h;

	// The classic part (BetaGenerator._generate_upper), in place: its array
	// is the column from y 64 up.
	float climate_values[512];
	climate(cx, cz, climate_values);
	uint8_t biomes[256];
	for (int i = 0; i < 256; i++)
		biomes[i] = uint8_t(new_biomes ? biome_index_new(climate_values[i], climate_values[256 + i])
										: biome_index(climate_values[i], climate_values[256 + i]));
	const int top = shape_terrain(upper, cx, cz);
	replace_surface(upper, cx, cz, biomes, top);
	carve_caves(upper, upper_size, cx, cz, 2, 119, h - 8, -1);
	Pcg rng(column_seed(cx, cz, 100));
	{
		Pcg lakes(column_seed(cx, cz, 250));
		if (lakes.randi_range(0, 3) == 0) {
			const int y = int(lakes.randi_range(8, h - 8));
			place_lake(upper, lakes, y, water);
		}
	}
	{
		Pcg lakes(column_seed(cx, cz, 200));
		if (lakes.randi_range(0, 7) == 0) {
			const int inner = int(lakes.randi_range(0, 119));
			const int y = int(lakes.randi_range(0, inner + 7));
			if (!(y >= SEA && lakes.randi_range(0, 9) != 0))
				place_lake(upper, lakes, y, lava);
		}
	}
	{
		Pcg dungeon(column_seed(cx, cz, 600));
		place_dungeon(upper, dungeon, h);
	}
	place_ores(upper, upper_size, rng, top, false, tall);
	place_trees(upper, cx, cz, biomes, rng);
	{
		Pcg plants(column_seed(cx, cz, 300));
		place_plants(upper, biomes, plants);
	}
	{
		Pcg clays(column_seed(cx, cz, 400));
		place_clay(upper, clays);
	}
	{
		Pcg nature(column_seed(cx, cz, 500));
		place_cacti(upper, biomes, nature);
		place_sugar_cane(upper, nature);
		place_mushrooms(upper, nature);
		place_springs(upper, nature);
	}
	freeze(upper, biomes);

	// The bedrock floor, uneven like the game's (BetaGenerator._place_floor).
	Pcg floor(column_seed(cx, cz, 700));
	for (int i = 0; i < 256; i++) {
		column[i] = bedrock;
		for (int y = 1; y < 5; y++)
			if (floor.randi_range(0, 4) >= y)
				column[i + 256 * y] = bedrock;
	}
	if (!deep)
		return result;
	// The deep layer (BetaGenerator._generate_deep).
	carve_caves(column, COLUMN_VOLUME, cx, cz, 702, LEGACY_SHIFT - 8, tall ? LEGACY_SHIFT + 12 : LEGACY_SHIFT - 2, LAVA_LEVEL);
	{
		Pcg lakes(column_seed(cx, cz, 703));
		if (lakes.randi_range(0, 3) == 0) {
			const int y = int(lakes.randi_range(10, LEGACY_SHIFT - 8));
			place_lake(column, lakes, y, lava);
		}
	}
	{
		Pcg dungeon(column_seed(cx, cz, 704));
		place_dungeon(column, dungeon, LEGACY_SHIFT + 16);
	}
	{
		Pcg deep_ores(column_seed(cx, cz, 705));
		place_ores(column, COLUMN_VOLUME, deep_ores, LEGACY_SHIFT + 8, true, false);
	}
	return result;
}

int NativeBetaGenerator::shape_terrain(int32_t *blocks, int cx, int cz) const {
	int top = -1;
	const int stride_y = cells + 1;
	const int stride_z = (CELLS_X + 1) * stride_y;
	std::vector<float> density((CELLS_X + 1) * (CELLS_X + 1) * stride_y);
	for (int gx = 0; gx < CELLS_X + 1; gx++) {
		for (int gz = 0; gz < CELLS_X + 1; gz++) {
			const double wx = double(cx * 16 + gx * GRID_X);
			const double wz = double(cz * 16 + gz * GRID_X);
			const double temp = temperature(wx, wz);
			const double humid = humidity(wx, wz) * temp;
			double dryness = 1.0 - humid;
			dryness *= dryness;
			dryness *= dryness;
			const double vegetation = 1.0 - dryness;
			double scale = (noise2(SCALE, wx, wz) * SCALE_AMPLITUDE + 256.0) / 512.0 * vegetation;
			if (scale > 1.0)
				scale = 1.0;
			double depth = noise2(DEPTH, wx, wz) * DEPTH_AMPLITUDE;
			if (depth < 0.0)
				depth = -depth * 0.3;
			depth = depth * 3.0 - 2.0;
			if (depth < 0.0) {
				depth /= 2.0;
				if (depth < -1.0)
					depth = -1.0;
				depth /= 1.4;
				depth /= 2.0;
				scale = 0.0;
			} else {
				if (depth > 1.0)
					depth = 1.0;
				depth /= 8.0;
			}
			if (scale < 0.0)
				scale = 0.0;
			scale += 0.5;
			depth = depth * LEGACY_CELLS / 16.0;
			double center = LEGACY_CELLS / 2.0 + 0.5 + depth * 4.0;
			double flatten = 1.0;
			if (new_biomes) {
				const double glacier = std::clamp((GLACIER_TEMP - temp) / BLEND, 0.0, 1.0);
				const double swamp = std::clamp(std::min((humid - SWAMP_HUMID) / BLEND, (SWAMP_TEMP - temp) / BLEND), 0.0, 1.0);
				flatten = 1.0 + glacier * GLACIER_FLAT + swamp * SWAMP_FLAT;
				center += (GLACIER_LEVEL - center) * glacier * 0.5;
				center += (SWAMP_LEVEL - center) * swamp;
			}
			for (int gy = 0; gy < stride_y; gy++) {
				const double wy = double(gy * GRID_Y);
				double rise = gy - center;
				if (tall && rise > 1.0)
					rise = 1.0 + (rise - 1.0) * 0.3;
				double offset = rise * 12.0 / scale * flatten;
				if (offset < 0.0)
					offset *= 4.0;
				const double low = noise3(MIN, wx, wy * 0.5, wz) * LIMIT_AMPLITUDE;
				const double high = noise3(MAX, wx, wy * 0.5, wz) * LIMIT_AMPLITUDE;
				const double mix = (noise3(MAIN, wx, wy * 0.25, wz) * MAIN_AMPLITUDE + 1.0) * 0.5;
				double value = mix < 0.0 ? low : (mix > 1.0 ? high : low + (high - low) * mix);
				value -= offset;
				if (gy > cells - 3) {
					const double fade = (gy - (cells - 3)) / 3.0;
					value = value * (1.0 - fade) - 10.0 * fade;
				}
				density[gx * stride_z + gz * stride_y + gy] = float(value);
			}
		}
	}
	for (int gx = 0; gx < CELLS_X; gx++)
		for (int gz = 0; gz < CELLS_X; gz++)
			for (int gy = 0; gy < cells; gy++) {
				const int base = gx * stride_z + gz * stride_y + gy;
				const double d000 = density[base];
				const double d001 = density[base + stride_y];
				const double d100 = density[base + stride_z];
				const double d101 = density[base + stride_z + stride_y];
				const double d010 = density[base + 1];
				const double d011 = density[base + stride_y + 1];
				const double d110 = density[base + stride_z + 1];
				const double d111 = density[base + stride_z + stride_y + 1];
				for (int sy = 0; sy < GRID_Y; sy++) {
					const double ty = sy / double(GRID_Y);
					const int y = gy * GRID_Y + sy;
					const double a00 = d000 + (d010 - d000) * ty;
					const double a01 = d001 + (d011 - d001) * ty;
					const double a10 = d100 + (d110 - d100) * ty;
					const double a11 = d101 + (d111 - d101) * ty;
					for (int sx = 0; sx < GRID_X; sx++) {
						const double tx = sx / double(GRID_X);
						const double b0 = a00 + (a10 - a00) * tx;
						const double b1 = a01 + (a11 - a01) * tx;
						const int row = gx * GRID_X + sx + 16 * (gz * GRID_X + 16 * y);
						for (int sz = 0; sz < GRID_X; sz++) {
							const double value = b0 + (b1 - b0) * (sz / double(GRID_X));
							if (value > 0.0) {
								blocks[row + 16 * sz] = stone;
								if (y > top)
									top = y;
							} else if (y < SEA) {
								blocks[row + 16 * sz] = water;
							}
						}
					}
				}
			}
	return top;
}

void NativeBetaGenerator::replace_surface(int32_t *blocks, int cx, int cz, const uint8_t *biomes, int stone_top) const {
	const int start_y = std::min(std::max(stone_top, SEA - 1), h - 1);
	Pcg rng(column_seed(cx, cz, 1));
	for (int z = 0; z < 16; z++)
		for (int x = 0; x < 16; x++) {
			const double wx = double(cx * 16 + x);
			const double wz = double(cz * 16 + z);
			const int biome = biomes[z * 16 + x];
			const int32_t own_top = biome_top[biome];
			const int32_t own_filler = biome_filler[biome];
			const bool sand_beach = noise2(SAND, wx, wz) + rng.randf() * 0.2 > 0.0;
			const bool gravel_beach = noise2(GRAVEL, wz, wx) * 15.0 + rng.randf() * 0.2 > 3.0;
			const int soil_depth = int(noise2(SOIL, wx, wz) * 5.0 + 3.0 + rng.randf() * 0.25);
			int32_t top = own_top;
			int32_t filler = own_filler;
			int depth_left = -1;
			int bedrock_mask = 1;
			for (int y = 1; y < 5; y++)
				if (rng.randi_range(0, 4) >= y)
					bedrock_mask |= 1 << y;
			for (int y = start_y; y >= 0; y--) {
				const int i = x + 16 * (z + 16 * y);
				if (y <= 4 && ((bedrock_mask >> y) & 1) == 1)
					continue;
				const int32_t id = blocks[i];
				if (id == AIR) {
					depth_left = -1;
					continue;
				}
				if (id != stone)
					continue;
				if (depth_left == -1) {
					if (soil_depth <= 0) {
						top = AIR;
						filler = stone;
					} else if (y >= SEA - 4 && y <= SEA + 1) {
						top = own_top;
						filler = own_filler;
						const bool plain_shore = new_biomes && (biome == GLACIER || biome == SWAMPLAND);
						if (gravel_beach && !plain_shore) {
							top = AIR;
							filler = gravel;
						}
						if (sand_beach && !plain_shore) {
							top = sand;
							filler = sand;
						}
					}
					if (new_biomes && biome == GLACIER && y < SEA - 1) {
						top = gravel;
						filler = gravel;
					}
					if (y < SEA && top == AIR)
						top = water;
					depth_left = soil_depth;
					blocks[i] = y >= SEA - 1 ? top : filler;
					if (new_biomes && biome == SWAMPLAND && y == SEA - 1 && blocks[i + 256] == AIR &&
							noise2(DETAIL, wx * POOL_STRETCH, wz * POOL_STRETCH) > POOL_OVER)
						blocks[i] = water;
				} else if (depth_left > 0) {
					depth_left--;
					blocks[i] = filler;
					if (depth_left == 0 && filler == sand) {
						depth_left = int(rng.randi_range(0, 3));
						filler = sandstone;
					}
				}
			}
		}
}

// --- Caves ----------------------------------------------------------------------------

void NativeBetaGenerator::carve_caves(int32_t *blocks, int size, int cx, int cz, int salt, int start_span, int max_y,
		int lava_level) const {
	for (int ox = -CAVE_RANGE; ox <= CAVE_RANGE; ox++)
		for (int oz = -CAVE_RANGE; oz <= CAVE_RANGE; oz++) {
			// GDScript's 64-bit integers wrap; their >> keeps the sign.
			int64_t hv = int64_t(uint64_t(world_seed) * 6364136223846793005ULL + uint64_t(int64_t(cx + ox)) * 1442695040888963407ULL +
					uint64_t(int64_t(cz + oz)) * 3935559000370003845ULL);
			hv ^= hv >> 29;
			hv = int64_t(uint64_t(hv) * uint64_t(int64_t(-4658895280553007687LL)));
			hv ^= hv >> 32;
			if ((hv & 0xFFFFFF) % 15 != 0)
				continue;
			Pcg rng(column_seed(cx + ox, cz + oz, salt));
			const int64_t c1 = rng.randi_range(0, 39);
			const int64_t c2 = rng.randi_range(0, c1 + 1);
			const int64_t count = rng.randi_range(0, c2);
			for (int64_t i = 0; i < count; i++) {
				const int64_t rx = rng.randi_range(0, 15);
				const int64_t span = rng.randi_range(0, start_span);
				const int64_t ry = rng.randi_range(0, span + 8);
				const int64_t rz = rng.randi_range(0, 15);
				const float sx = float((cx + ox) * 16 + rx);
				const float sy = float(ry);
				const float sz = float((cz + oz) * 16 + rz);
				int64_t tunnels = 1;
				if (rng.randi_range(0, 3) == 0) {
					const uint64_t seed_value = uint64_t(rng.randi());
					const double width = 1.0 + rng.randf() * 6.0;
					carve_tunnel(blocks, size, cx, cz, seed_value, sx, sy, sz, width, 0.0, 0.0, -1, -1, 0.5, max_y, lava_level);
					tunnels += rng.randi_range(0, 3);
				}
				for (int64_t t = 0; t < tunnels; t++) {
					const double yaw = rng.randf() * TAU_D;
					const double pitch = (rng.randf() - 0.5) * 2.0 / 8.0;
					const double w1 = rng.randf() * 2.0;
					double width = w1 + rng.randf();
					if (rng.randi_range(0, 9) == 0) {
						const double f1 = rng.randf();
						const double f2 = f1 * rng.randf();
						width *= f2 * 3.0 + 1.0;
					}
					const uint64_t seed_value = uint64_t(rng.randi());
					carve_tunnel(blocks, size, cx, cz, seed_value, sx, sy, sz, width, yaw, pitch, 0, 0, 1.0, max_y, lava_level);
				}
			}
		}
}

void NativeBetaGenerator::carve_tunnel(int32_t *blocks, int size, int cx, int cz, uint64_t seed_value, float px,
		float py, float pz, double width, double yaw, double pitch, int step, int length, double height_ratio,
		int max_y, int lava_level) const {
	Pcg rng(seed_value);
	const double center_x = cx * 16 + 8.0;
	const double center_z = cz * 16 + 8.0;
	double yaw_change = 0.0;
	double pitch_change = 0.0;
	if (length <= 0) {
		length = CAVE_RANGE * 16 - 16;
		length -= int(rng.randi_range(0, length / 4));
	}
	const bool is_room = step == -1;
	if (is_room)
		step = length / 2;
	const double start_dx = double(px) - center_x;
	const double start_dz = double(pz) - center_z;
	if (std::sqrt(start_dx * start_dx + start_dz * start_dz) - (length - step) > 8.0 + 2.0 * (1.5 + width) + 2.0)
		return;
	const int split_at = int(rng.randi_range(length / 4, length / 2 + length / 4));
	const bool steep = rng.randi_range(0, 5) == 0;
	while (step < length) {
		const double radius = 1.5 + std::sin(step * PI_D / length) * width;
		const double radius_y = radius * height_ratio;
		px += float(std::cos(yaw) * std::cos(pitch));
		py += float(std::sin(pitch));
		pz += float(std::sin(yaw) * std::cos(pitch));
		pitch *= steep ? 0.92 : 0.7;
		pitch += pitch_change * 0.1;
		yaw += yaw_change * 0.1;
		pitch_change *= 0.9;
		yaw_change *= 0.75;
		{
			const double a = rng.randf();
			const double b = rng.randf();
			const double c = rng.randf();
			pitch_change += (a - b) * c * 2.0;
		}
		{
			const double a = rng.randf();
			const double b = rng.randf();
			const double c = rng.randf();
			yaw_change += (a - b) * c * 4.0;
		}
		if (!is_room && step == split_at && width > 1.0) {
			const uint64_t s1 = uint64_t(rng.randi());
			const double w1 = rng.randf() * 0.5 + 0.5;
			carve_tunnel(blocks, size, cx, cz, s1, px, py, pz, w1, yaw - PI_D / 2.0, pitch / 3.0, step, length, 1.0,
					max_y, lava_level);
			const uint64_t s2 = uint64_t(rng.randi());
			const double w2 = rng.randf() * 0.5 + 0.5;
			carve_tunnel(blocks, size, cx, cz, s2, px, py, pz, w2, yaw + PI_D / 2.0, pitch / 3.0, step, length, 1.0,
					max_y, lava_level);
			return;
		}
		step++;
		if (!is_room && rng.randi_range(0, 3) == 0)
			continue;
		const double dx = double(px) - center_x;
		const double dz = double(pz) - center_z;
		const double remaining = double(length - step);
		const double reach = width + 2.0 + 16.0;
		if (dx * dx + dz * dz - remaining * remaining > reach * reach)
			return;
		if (std::abs(dx) > 8.0 + radius * 2.0 || std::abs(dz) > 8.0 + radius * 2.0)
			continue;
		carve_ellipsoid(blocks, size, cx, cz, px, py, pz, radius, radius_y, max_y, lava_level);
		if (is_room)
			return;
	}
}

void NativeBetaGenerator::carve_ellipsoid(int32_t *blocks, int size, int cx, int cz, float x0, float y0, float z0,
		double radius, double radius_y, int top_y, int lava_level) const {
	const double cxf = x0, cyf = y0, czf = z0;
	const int min_x = std::max(floori(cxf - radius) - cx * 16 - 1, 0);
	const int max_x = std::min(floori(cxf + radius) - cx * 16 + 1, 15);
	const int min_z = std::max(floori(czf - radius) - cz * 16 - 1, 0);
	const int max_z = std::min(floori(czf + radius) - cz * 16 + 1, 15);
	const int min_y = std::max(floori(cyf - radius_y) - 1, 1);
	const int max_y = std::min(floori(cyf + radius_y) + 1, top_y);
	if (min_x > max_x || min_z > max_z || min_y > max_y)
		return;
	for (int x = min_x; x <= max_x; x++)
		for (int z = min_z; z <= max_z; z++)
			for (int y = min_y; y <= max_y + 1; y++) {
				const int j = idx(x, y, z);
				if (j < size && blocks[j] == water)
					return;
			}
	for (int x = min_x; x <= max_x; x++) {
		const double fx = (x + cx * 16 + 0.5 - cxf) / radius;
		for (int z = min_z; z <= max_z; z++) {
			const double fz = (z + cz * 16 + 0.5 - czf) / radius;
			if (fx * fx + fz * fz >= 1.0)
				continue;
			for (int y = max_y; y >= min_y; y--) {
				const double fy = (y + 0.5 - cyf) / radius_y;
				if (fy > -0.7 && fx * fx + fy * fy + fz * fz < 1.0) {
					const int i = idx(x, y, z);
					if (blocks[i] != bedrock)
						blocks[i] = y < lava_level ? lava : AIR;
				}
			}
		}
	}
}

// --- Ores and lakes -------------------------------------------------------------------

void NativeBetaGenerator::place_ores(int32_t *blocks, int size, Pcg &rng, int top, bool deep, bool upper_only) const {
	const int(*table)[3] = deep ? DEEP_ORES : ORES;
	for (int k = 0; k < 8; k++) {
		const int32_t id = (!upper_only || k < 4) ? ores[k] : stone;
		for (int vein = 0; vein < table[k][0]; vein++) {
			const double a = rng.randf() * 16.0;
			const int64_t b = rng.randi_range(0, table[k][2] - 1);
			const double c = rng.randf() * 16.0;
			place_vein(blocks, size, rng, id, table[k][1], float(a), float(b), float(c), top);
		}
	}
}

void NativeBetaGenerator::place_vein(int32_t *blocks, int size, Pcg &rng, int32_t id, int vein_size, float sx,
		float sy, float sz, int top) const {
	const double angle = rng.randf() * PI_D;
	// Vector3(sin, 0, cos) * size / 8.0, in floats.
	const float hx = float(std::sin(angle)) * float(vein_size) / 8.0f;
	const float hy = 0.0f * float(vein_size) / 8.0f;
	const float hz = float(std::cos(angle)) * float(vein_size) / 8.0f;
	const int64_t r1 = rng.randi_range(0, 2);
	const float ax = sx + hx + 0.0f, ay = sy + hy + float(r1 - 1), az = sz + hz + 0.0f;
	const int64_t r2 = rng.randi_range(0, 2);
	const float bx = sx - hx + 0.0f, by = sy - hy + float(r2 - 1), bz = sz - hz + 0.0f;
	const int height = size / 256;
	for (int i = 0; i <= vein_size; i++) {
		const float w = float(double(i) / vein_size);
		const float cxf = ax + (bx - ax) * w;
		const float cyf = ay + (by - ay) * w;
		const float czf = az + (bz - az) * w;
		const double radius = ((std::sin(i * PI_D / vein_size) + 1.0) * rng.randf() * vein_size / 16.0 + 1.0) / 2.0;
		const double radius_squared = radius * radius;
		const int x0 = std::max(floori(cxf - radius), 0);
		const int x1 = std::min(floori(cxf + radius), 15);
		const int y0 = std::max(floori(cyf - radius), 1);
		const int y1 = std::min(floori(cyf + radius), height - 1);
		const int z0 = std::max(floori(czf - radius), 0);
		const int z1 = std::min(floori(czf + radius), 15);
		if (y0 > top)
			continue;
		for (int y = y0; y <= std::min(y1, top); y++) {
			const double dy = y + 0.5 - cyf;
			for (int z = z0; z <= z1; z++) {
				const double dz = z + 0.5 - czf;
				if (dy * dy + dz * dz >= radius_squared)
					continue;
				const int row = 16 * (z + 16 * y);
				for (int x = x0; x <= x1; x++) {
					const double dx = x + 0.5 - cxf;
					if (dx * dx + dy * dy + dz * dz < radius_squared && blocks[row + x] == stone)
						blocks[row + x] = id;
				}
			}
		}
	}
}

void NativeBetaGenerator::place_lake(int32_t *blocks, Pcg &rng, int y, int32_t fill) const {
	const int floor_y = y - 4;
	if (floor_y < 2 || floor_y + 8 >= h)
		return;
	uint8_t shape[16 * 16 * 8] = {};
	const int64_t blobs = rng.randi_range(4, 7);
	for (int64_t blob = 0; blob < blobs; blob++) {
		const float sx = float(rng.randf() * 6.0 + 3.0);
		const float sy = float(rng.randf() * 4.0 + 2.0);
		const float sz = float(rng.randf() * 6.0 + 3.0);
		const double r1 = rng.randf();
		const float cxf = float(r1 * (16.0 - sx - 2.0) + 1.0 + sx / 2.0);
		const double r2 = rng.randf();
		const float cyf = float(r2 * (8.0 - sy - 4.0) + 2.0 + sy / 2.0);
		const double r3 = rng.randf();
		const float czf = float(r3 * (16.0 - sz - 2.0) + 1.0 + sz / 2.0);
		const float hx = sx / 2.0f, hy = sy / 2.0f, hz = sz / 2.0f;
		for (int lx = 1; lx < 15; lx++)
			for (int lz = 1; lz < 15; lz++)
				for (int ly = 1; ly < 7; ly++) {
					const float dx = ((float(lx) + 0.5f) - cxf) / hx;
					const float dy = ((float(ly) + 0.5f) - cyf) / hy;
					const float dz = ((float(lz) + 0.5f) - czf) / hz;
					if (dx * dx + dy * dy + dz * dz < 1.0f)
						shape[lx + 16 * (lz + 16 * ly)] = 1;
				}
	}
	for (int i = 0; i < 16 * 16 * 8; i++) {
		if (shape[i] == 0)
			continue;
		const int ly = i / 256;
		const int32_t block = blocks[idx(i % 16, floor_y + ly, (i / 16) % 16)];
		if (block == water || block == lava || (ly < 4 && block == AIR))
			return;
	}
	for (int i = 0; i < 16 * 16 * 8; i++) {
		if (shape[i] != 1)
			continue;
		const int ly = i / 256;
		const int j = idx(i % 16, floor_y + ly, (i / 16) % 16);
		if (blocks[j] != bedrock)
			blocks[j] = ly < 4 ? fill : AIR;
	}
}

// DungeonBehavior.place().
void NativeBetaGenerator::place_dungeon(int32_t *blocks, Pcg &rng, int height) const {
	for (int attempt = 0; attempt < DUNGEON_TRIES; attempt++) {
		const int cx = int(rng.randi_range(4, 11));
		const int cy = int(rng.randi_range(4, height - 20));
		const int cz = int(rng.randi_range(4, 11));
		const int rx = int(rng.randi_range(2, 3));
		const int rz = int(rng.randi_range(2, 3));
		if (cx - rx - 1 < 0 || cx + rx + 1 > 15 || cz - rz - 1 < 0 || cz + rz + 1 > 15)
			continue;
		int openings = 0;
		for (int x = cx - rx - 1; x < cx + rx + 2; x++) {
			const bool x_edge = x == cx - rx - 1 || x == cx + rx + 1;
			for (int z = cz - rz - 1; z < cz + rz + 2; z++)
				if ((x_edge || z == cz - rz - 1 || z == cz + rz + 1) && blocks[idx(x, cy, z)] == AIR &&
						blocks[idx(x, cy + 1, z)] == AIR)
					openings++;
		}
		if (openings < 1 || openings > 5)
			continue;
		bool fits = true;
		for (int x = cx - rx - 1; x < cx + rx + 2 && fits; x++)
			for (int z = cz - rz - 1; z < cz + rz + 2 && fits; z++)
				for (int y = cy - 1; y < cy + 5; y++) {
					const int32_t id = blocks[idx(x, y, z)];
					const bool solid = id != AIR && table(collides, id) == 1;
					if (((y == cy - 1 || y == cy + 4) && !solid) || table(liquid, id) == 1) {
						fits = false;
						break;
					}
				}
		if (!fits)
			continue;
		for (int x = cx - rx - 1; x < cx + rx + 2; x++)
			for (int z = cz - rz - 1; z < cz + rz + 2; z++)
				for (int y = cy + 3; y > cy - 2; y--) {
					const int i = idx(x, y, z);
					const bool edge = x == cx - rx - 1 || x == cx + rx + 1 || z == cz - rz - 1 || z == cz + rz + 1;
					if (y >= cy && y <= cy + 3 && !edge)
						blocks[i] = AIR;
					else if (y == cy - 1 && rng.randi_range(0, 3) != 0)
						blocks[i] = mossy;
					else if (blocks[i] != AIR && table(collides, blocks[i]) == 1)
						blocks[i] = cobble;
				}
		for (int chest = 0; chest < 2; chest++)
			for (int tries = 0; tries < 3; tries++) {
				const int x = cx + int(rng.randi_range(-rx, rx));
				const int z = cz + int(rng.randi_range(-rz, rz));
				int walls = 0;
				for (const auto &side : SIDES)
					if (table(collides, blocks[idx(x + side[0], cy, z + side[1])]) == 1)
						walls++;
				if (walls == 1 && blocks[idx(x, cy, z)] == AIR) {
					blocks[idx(x, cy, z)] = dungeon_chest;
					break;
				}
			}
		const int kinds[4] = { 0, 0, 1, 2 };
		blocks[idx(cx, cy, cz)] = spawners[kinds[rng.randi_range(0, 3)]];
		return;
	}
}

// --- Trees ----------------------------------------------------------------------------

int NativeBetaGenerator::surface_y(const int32_t *blocks, int x, int z) const {
	for (int y = h - 1; y > 0; y--)
		if (blocks[idx(x, y, z)] != AIR)
			return y;
	return -1;
}

int32_t NativeBetaGenerator::at(const int32_t *blocks, int x, int y, int z) const {
	if (x < 0 || x > 15 || z < 0 || z > 15 || y < 0 || y >= h)
		return AIR;
	return blocks[idx(x, y, z)];
}

void NativeBetaGenerator::put(int32_t *blocks, int x, int y, int z, int32_t id) const {
	if (x < 0 || x > 15 || z < 0 || z > 15 || y < 0 || y >= h)
		return;
	blocks[idx(x, y, z)] = id;
}

bool NativeBetaGenerator::is_leaves(int32_t id) const {
	return id == oak_leaves || id == birch_leaves || id == spruce_leaves;
}

bool NativeBetaGenerator::tree_free(int32_t id) const {
	return id == AIR || is_leaves(id);
}

bool NativeBetaGenerator::is_ground(int32_t id) const {
	return table(grass_named, id) == 1 || id == dirt || id == tree_ground[5]; // snowy_grass
}

void NativeBetaGenerator::put_leaf(int32_t *blocks, int x, int y, int z, int32_t leaf) const {
	const int32_t there = at(blocks, x, y, z);
	if (there != leaf && (is_leaves(there) || (table(collides, there) == 0 && table(liquid, there) == 0)))
		put(blocks, x, y, z, leaf);
}

void NativeBetaGenerator::put_log(int32_t *blocks, int x, int y, int z, int32_t log) const {
	if (tree_free(at(blocks, x, y, z)))
		put(blocks, x, y, z, log);
}

bool NativeBetaGenerator::ring_free(const int32_t *blocks, int x, int y, int z, int radius) const {
	for (int dx = -radius; dx <= radius; dx++)
		for (int dz = -radius; dz <= radius; dz++)
			if (!tree_free(at(blocks, x + dx, y, z + dz)))
				return false;
	return true;
}

// Step 6: trees (BetaGenerator._place_trees).
void NativeBetaGenerator::place_trees(int32_t *blocks, int cx, int cz, const uint8_t *biomes, Pcg &rng) const {
	const int biome_here = biomes[8 * 16 + 8];
	const double n = noise2(TREE, cx * 16 + 8, cz * 16 + 8);
	const int noise_count = int((n * 4.0 + rng.randf() * 4.0 + 4.0) / 3.0);
	int count = 0;
	if (rng.randi_range(0, 9) == 0)
		count++;
	const int extra = biome_trees[biome_here];
	count += extra + (extra > 0 ? noise_count : 0);
	enum { OAK, BIRCH, SPRUCE, PINE, BIG };
	static const int MARGINS[5] = { 2, 2, 3, 4, 5 };
	for (int t = 0; t < count; t++) {
		int x = int(rng.randi_range(2, 13));
		int z = int(rng.randi_range(2, 13));
		int kind = OAK;
		switch (biome_here) {
			case TAIGA:
				kind = rng.randi_range(0, 2) == 0 ? PINE : SPRUCE;
				break;
			case FOREST:
				if (rng.randi_range(0, 4) == 0)
					kind = BIRCH;
				else
					kind = rng.randi_range(0, 2) == 0 ? BIG : OAK;
				break;
			case RAINFOREST:
				kind = rng.randi_range(0, 2) == 0 ? BIG : OAK;
				break;
			default:
				kind = rng.randi_range(0, 9) == 0 ? BIG : OAK;
		}
		x = std::clamp(x, MARGINS[kind], 15 - MARGINS[kind]);
		z = std::clamp(z, MARGINS[kind], 15 - MARGINS[kind]);
		const int y = surface_y(blocks, x, z);
		if (y < 0 || !is_ground(blocks[idx(x, y, z)]))
			continue;
		switch (kind) {
			case OAK: oak(blocks, rng, x, y + 1, z, oak_log, oak_leaves, 4); break;
			case BIRCH: oak(blocks, rng, x, y + 1, z, birch_log, birch_leaves, 5); break;
			case SPRUCE: spruce(blocks, rng, x, y + 1, z); break;
			case PINE: pine(blocks, rng, x, y + 1, z); break;
			default: big_oak(blocks, rng, x, y + 1, z);
		}
	}
}

bool NativeBetaGenerator::oak(int32_t *blocks, Pcg &rng, int x, int y, int z, int32_t log, int32_t leaf,
		int min_height) const {
	const int height = int(rng.randi_range(min_height, min_height + 2));
	if (y < 1 || y + height + 1 > h)
		return false;
	for (int ly = y; ly <= y + height + 1; ly++) {
		const int radius = ly == y ? 0 : (ly >= y + height + 1 - 2 ? 2 : 1);
		if (!ring_free(blocks, x, ly, z, radius))
			return false;
	}
	if (!is_ground(at(blocks, x, y - 1, z)))
		return false;
	put(blocks, x, y - 1, z, dirt);
	for (int ly = y - 3 + height; ly <= y + height; ly++) {
		const int above_top = ly - (y + height);
		const int radius = 1 - above_top / 2;
		for (int lx = x - radius; lx <= x + radius; lx++)
			for (int lz = z - radius; lz <= z + radius; lz++)
				if (std::abs(lx - x) != radius || std::abs(lz - z) != radius || (rng.randi_range(0, 1) != 0 && above_top != 0))
					put_leaf(blocks, lx, ly, lz, leaf);
	}
	for (int dy = 0; dy < height; dy++)
		put_log(blocks, x, y + dy, z, log);
	return true;
}

bool NativeBetaGenerator::spruce(int32_t *blocks, Pcg &rng, int x, int y, int z) const {
	const int height = int(rng.randi_range(6, 9));
	const int bare = int(rng.randi_range(1, 2));
	const int leafy = height - bare;
	const int widest = int(rng.randi_range(2, 3));
	if (y < 1 || y + height + 1 > h)
		return false;
	for (int ly = y; ly <= y + height + 1; ly++)
		if (!ring_free(blocks, x, ly, z, ly - y < bare ? 0 : widest))
			return false;
	if (!is_ground(at(blocks, x, y - 1, z)))
		return false;
	put(blocks, x, y - 1, z, dirt);
	int radius = int(rng.randi_range(0, 1));
	int limit = 1;
	int restart = 0;
	for (int i = 0; i <= leafy; i++) {
		const int ly = y + height - i;
		for (int lx = x - radius; lx <= x + radius; lx++)
			for (int lz = z - radius; lz <= z + radius; lz++)
				if (std::abs(lx - x) != radius || std::abs(lz - z) != radius || radius <= 0)
					put_leaf(blocks, lx, ly, lz, spruce_leaves);
		if (radius >= limit) {
			radius = restart;
			restart = 1;
			limit = std::min(limit + 1, widest);
		} else {
			radius++;
		}
	}
	const int shorter = int(rng.randi_range(0, 2));
	for (int dy = 0; dy < height - shorter; dy++)
		put_log(blocks, x, y + dy, z, spruce_log);
	return true;
}

bool NativeBetaGenerator::pine(int32_t *blocks, Pcg &rng, int x, int y, int z) const {
	const int height = int(rng.randi_range(7, 11));
	const int bare = height - int(rng.randi_range(0, 1)) - 3;
	const int leafy = height - bare;
	const int widest = 1 + int(rng.randi_range(0, leafy));
	if (y < 1 || y + height + 1 > h)
		return false;
	for (int ly = y; ly <= y + height + 1; ly++)
		if (!ring_free(blocks, x, ly, z, ly - y < bare ? 0 : widest))
			return false;
	if (!is_ground(at(blocks, x, y - 1, z)))
		return false;
	put(blocks, x, y - 1, z, dirt);
	int radius = 0;
	for (int ly = y + height; ly >= y + bare; ly--) {
		for (int lx = x - radius; lx <= x + radius; lx++)
			for (int lz = z - radius; lz <= z + radius; lz++)
				if (std::abs(lx - x) != radius || std::abs(lz - z) != radius || radius <= 0)
					put_leaf(blocks, lx, ly, lz, spruce_leaves);
		if (radius >= 1 && ly == y + bare + 1)
			radius--;
		else if (radius < widest)
			radius++;
	}
	for (int dy = 0; dy < height - 1; dy++)
		put_log(blocks, x, y + dy, z, spruce_log);
	return true;
}

// The cells of the line a..b, b included (TreeShapes._line); their number.
int NativeBetaGenerator::line_cells(const int a[3], const int b[3], int (*cells)[3], int max) const {
	static const int OTHER[6] = { 2, 0, 0, 1, 2, 1 };
	int delta[3] = { b[0] - a[0], b[1] - a[1], b[2] - a[2] };
	int main = 0;
	for (int axis = 0; axis < 3; axis++)
		if (std::abs(delta[axis]) > std::abs(delta[main]))
			main = axis;
	if (delta[main] == 0)
		return 0;
	const int first = OTHER[main], second = OTHER[main + 3];
	const int step = delta[main] > 0 ? 1 : -1;
	const double d1 = double(delta[first]) / delta[main];
	const double d2 = double(delta[second]) / delta[main];
	int count = 0;
	for (int k = 0; k != delta[main] + step && count < max; k += step) {
		cells[count][main] = int(std::floor(a[main] + k + 0.5));
		cells[count][first] = int(std::floor(a[first] + k * d1 + 0.5));
		cells[count][second] = int(std::floor(a[second] + k * d2 + 0.5));
		count++;
	}
	return count;
}

int NativeBetaGenerator::check_line(const int32_t *blocks, const int a[3], const int b[3]) const {
	int cells[64][3];
	const int count = line_cells(a, b, cells, 64);
	for (int i = 0; i < count; i++)
		if (!tree_free(at(blocks, cells[i][0], cells[i][1], cells[i][2])))
			return i;
	return -1;
}

bool NativeBetaGenerator::big_oak(int32_t *blocks, Pcg &rng, int x, int y, int z) const {
	int height_limit = 5 + int(rng.randi_range(0, 11));
	if (!is_ground(at(blocks, x, y - 1, z)))
		return false;
	{
		const int a[3] = { x, y, z }, b[3] = { x, y + height_limit - 1, z };
		const int blocked = check_line(blocks, a, b);
		if (blocked != -1) {
			if (blocked < 6)
				return false;
			height_limit = blocked;
		}
	}
	if (y + height_limit > h)
		return false;
	int trunk_height = int(height_limit * 0.618);
	if (trunk_height >= height_limit)
		trunk_height = height_limit - 1;
	// Leaf nodes (TreeShapes._leaf_nodes).
	const int per_layer = std::max(int(1.382 + std::pow(height_limit / 13.0, 2.0)), 1);
	const int top = y + height_limit - 4;
	const int trunk_top = y + trunk_height;
	std::vector<std::array<int, 4>> nodes = { { x, top, z, trunk_top } };
	int ny = top - 1;
	for (int layer = top - y; layer >= 0; layer--, ny--) {
		double size;
		if (layer < height_limit * 0.3) {
			size = -1.618;
		} else {
			const double half = height_limit / 2.0;
			const double off = height_limit / 2.0 - layer;
			if (off == 0.0)
				size = half;
			else if (std::abs(off) >= half)
				size = 0.0;
			else
				size = std::sqrt(half * half - off * off);
			size *= 0.5;
		}
		if (size < 0.0)
			continue;
		for (int attempt = 0; attempt < per_layer; attempt++) {
			const double distance = size * (rng.randf() + 0.328);
			const double angle = rng.randf() * 2.0 * 3.14159;
			const int nx = int(std::floor(distance * std::sin(angle) + x + 0.5));
			const int nz = int(std::floor(distance * std::cos(angle) + z + 0.5));
			if (nx < 2 || nx > 13 || nz < 2 || nz > 13)
				continue;
			const int node[3] = { nx, ny, nz }, node_top[3] = { nx, ny + 4, nz };
			if (check_line(blocks, node, node_top) != -1)
				continue;
			const double reach = std::sqrt(std::pow(std::abs(x - nx), 2.0) + std::pow(std::abs(z - nz), 2.0)) * 0.381;
			const int from_y = ny - reach > trunk_top ? trunk_top : int(ny - reach);
			const int from[3] = { x, from_y, z };
			if (check_line(blocks, from, node) == -1)
				nodes.push_back({ nx, ny, nz, from_y });
		}
	}
	for (const auto &node : nodes)
		for (int ly = node[1]; ly < node[1] + 4; ly++) {
			const int layer = ly - node[1];
			const double size = (layer == 0 || layer == 3) ? 2.0 : 3.0;
			const int reach = int(size + 0.618);
			for (int dx = -reach; dx <= reach; dx++)
				for (int dz = -reach; dz <= reach; dz++) {
					if (std::sqrt(std::pow(std::abs(dx) + 0.5, 2.0) + std::pow(std::abs(dz) + 0.5, 2.0)) > size)
						continue;
					const int32_t there = at(blocks, node[0] + dx, ly, node[2] + dz);
					if (there == AIR || is_leaves(there))
						put(blocks, node[0] + dx, ly, node[2] + dz, oak_leaves);
				}
		}
	int cells[64][3];
	{
		const int a[3] = { x, y, z }, b[3] = { x, y + trunk_height, z };
		const int count = line_cells(a, b, cells, 64);
		for (int i = 0; i < count; i++)
			put(blocks, cells[i][0], cells[i][1], cells[i][2], oak_log);
	}
	for (const auto &node : nodes)
		if (node[3] - y >= height_limit * 0.2) {
			const int a[3] = { x, node[3], z }, b[3] = { node[0], node[1], node[2] };
			const int count = line_cells(a, b, cells, 64);
			for (int i = 0; i < count; i++)
				put(blocks, cells[i][0], cells[i][1], cells[i][2], oak_log);
		}
	return true;
}

// --- Plants and the rest ----------------------------------------------------------------

bool NativeBetaGenerator::can_stay(int32_t plant, int32_t ground) const {
	if (plant == dead_bush)
		return ground == sand;
	return table(grass_named, ground) == 1 || ground == dirt || ground == tree_ground[5]; // snowy_grass
}

void NativeBetaGenerator::place_plants(int32_t *blocks, const uint8_t *biomes, Pcg &rng) const {
	const int biome = biomes[8 * 16 + 8];
	const int patches = new_biomes ? NEW_GRASS_PATCHES[biome] : GRASS_PATCHES[biome];
	const bool ferny = biome == RAINFOREST || (new_biomes && biome == SWAMPLAND);
	for (int patch = 0; patch < patches; patch++) {
		const int32_t plant = (ferny && rng.randi_range(0, 2) != 0) ? fern : tall_grass;
		plant_patch(blocks, rng, plant, 128);
	}
	for (int patch = 0; patch < 2; patch++)
		plant_patch(blocks, rng, dandelion, 64);
	if (rng.randi_range(0, 1) == 0)
		plant_patch(blocks, rng, rose, 64);
	if (biome == DESERT)
		for (int patch = 0; patch < 2; patch++)
			plant_patch(blocks, rng, dead_bush, 4);
	if (rng.randi_range(0, 31) == 0) {
		const int x0 = int(rng.randi_range(0, 15));
		const int z0 = int(rng.randi_range(0, 15));
		const int y0 = surface_y(blocks, x0, z0) + 1;
		for (int t = 0; t < 64; t++) {
			const int x = x0 + int(rng.randi_range(0, 7));
			const int x2 = x - int(rng.randi_range(0, 7));
			const int y = y0 + int(rng.randi_range(0, 3));
			const int y2 = y - int(rng.randi_range(0, 3));
			const int z = z0 + int(rng.randi_range(0, 7));
			const int z2 = z - int(rng.randi_range(0, 7));
			if (x2 < 0 || x2 > 15 || z2 < 0 || z2 > 15 || y2 < 1 || y2 >= h)
				continue;
			if (blocks[idx(x2, y2, z2)] == AIR && table(grass_named, blocks[idx(x2, y2 - 1, z2)]) == 1) {
				const int64_t facing = rng.randi_range(0, 3);
				if (!pumpkins.empty())
					blocks[idx(x2, y2, z2)] = pumpkins[std::clamp<int64_t>(facing, 0, int64_t(pumpkins.size()) - 1)];
			}
		}
	}
}

void NativeBetaGenerator::plant_patch(int32_t *blocks, Pcg &rng, int32_t plant, int tries) const {
	const int x0 = int(rng.randi_range(0, 15));
	const int z0 = int(rng.randi_range(0, 15));
	const int y0 = surface_y(blocks, x0, z0) + 1;
	if (y0 <= 0)
		return;
	for (int t = 0; t < tries; t++) {
		const int xa = int(rng.randi_range(0, 7));
		const int x = x0 + xa - int(rng.randi_range(0, 7));
		const int ya = int(rng.randi_range(0, 3));
		const int y = y0 + ya - int(rng.randi_range(0, 3));
		const int za = int(rng.randi_range(0, 7));
		const int z = z0 + za - int(rng.randi_range(0, 7));
		if (x < 0 || x > 15 || z < 0 || z > 15 || y < 1 || y >= h)
			continue;
		if (blocks[idx(x, y, z)] == AIR && can_stay(plant, blocks[idx(x, y - 1, z)]))
			blocks[idx(x, y, z)] = plant;
	}
}

void NativeBetaGenerator::place_clay(int32_t *blocks, Pcg &rng) const {
	for (int patch = 0; patch < 2; patch++) {
		if (rng.randi_range(0, 1) == 0)
			continue;
		const int x0 = int(rng.randi_range(2, 13));
		const int z0 = int(rng.randi_range(2, 13));
		int y = surface_y(blocks, x0, z0);
		while (y > 0 && blocks[idx(x0, y, z0)] == water)
			y--;
		if (y >= SEA - 1 || blocks[idx(x0, y + 1, z0)] != water)
			continue;
		const int radius = int(rng.randi_range(1, 2));
		for (int x = x0 - radius; x <= x0 + radius; x++)
			for (int z = z0 - radius; z <= z0 + radius; z++) {
				if ((x - x0) * (x - x0) + (z - z0) * (z - z0) > radius * radius + 1)
					continue;
				for (int dy = -1; dy < 1; dy++) {
					const int i = idx(x, y + dy, z);
					const int32_t here = blocks[i];
					if (here == sand || here == dirt || here == gravel)
						blocks[i] = clay;
				}
			}
	}
}

void NativeBetaGenerator::place_cacti(int32_t *blocks, const uint8_t *biomes, Pcg &rng) const {
	if (biomes[8 * 16 + 8] != DESERT)
		return;
	for (int attempt = 0; attempt < 10; attempt++) {
		const int x = int(rng.randi_range(1, 14));
		const int z = int(rng.randi_range(1, 14));
		const int y = surface_y(blocks, x, z) + 1;
		const int64_t inner = rng.randi_range(0, 2);
		const int height = 1 + int(rng.randi_range(0, inner + 1));
		if (y <= 0 || blocks[idx(x, y - 1, z)] != sand)
			continue;
		for (int hh = 0; hh < std::min(height, 3); hh++) {
			bool free = blocks[idx(x, y + hh, z)] == AIR;
			for (const auto &side : SIDES)
				if (blocks[idx(x + side[0], y + hh, z + side[1])] != AIR)
					free = false;
			if (!free)
				break;
			blocks[idx(x, y + hh, z)] = cactus;
		}
	}
}

void NativeBetaGenerator::place_sugar_cane(int32_t *blocks, Pcg &rng) const {
	for (int attempt = 0; attempt < 20; attempt++) {
		const int x = int(rng.randi_range(1, 14));
		const int z = int(rng.randi_range(1, 14));
		const int y = surface_y(blocks, x, z) + 1;
		if (y <= 0 || blocks[idx(x, y, z)] != AIR)
			continue;
		const int32_t ground = blocks[idx(x, y - 1, z)];
		if (!(table(grass_named, ground) == 1 || ground == dirt || ground == sand))
			continue;
		bool by_water = false;
		for (const auto &side : SIDES)
			if (blocks[idx(x + side[0], y - 1, z + side[1])] == water)
				by_water = true;
		if (!by_water)
			continue;
		const int64_t inner = rng.randi_range(0, 2);
		const int height = std::min(2 + int(rng.randi_range(0, inner + 1)), 3);
		for (int hh = 0; hh < height; hh++)
			if (blocks[idx(x, y + hh, z)] == AIR)
				blocks[idx(x, y + hh, z)] = reeds;
	}
}

void NativeBetaGenerator::place_mushrooms(int32_t *blocks, Pcg &rng) const {
	const int32_t kinds[2] = { brown_mushroom, red_mushroom };
	const int chances[2] = { 4, 8 };
	for (int k = 0; k < 2; k++) {
		if (rng.randi_range(0, chances[k] - 1) != 0)
			continue;
		const int x0 = int(rng.randi_range(0, 15));
		const int z0 = int(rng.randi_range(0, 15));
		const int y0 = int(rng.randi_range(1, std::max(surface_y(blocks, x0, z0), 2)));
		for (int attempt = 0; attempt < 64; attempt++) {
			const int xa = int(rng.randi_range(0, 7));
			const int x = x0 + xa - int(rng.randi_range(0, 7));
			const int ya = int(rng.randi_range(0, 3));
			const int y = y0 + ya - int(rng.randi_range(0, 3));
			const int za = int(rng.randi_range(0, 7));
			const int z = z0 + za - int(rng.randi_range(0, 7));
			if (x < 0 || x > 15 || z < 0 || z > 15 || y < 1 || y >= h - 1)
				continue;
			if (blocks[idx(x, y, z)] == AIR && table(opaque, blocks[idx(x, y - 1, z)]) == 1 && y < surface_y(blocks, x, z))
				blocks[idx(x, y, z)] = kinds[k];
		}
	}
}

void NativeBetaGenerator::place_springs(int32_t *blocks, Pcg &rng) const {
	for (int kind = 0; kind < 2; kind++) {
		const int tries = kind == 0 ? 50 : 20;
		for (int attempt = 0; attempt < tries; attempt++) {
			const int x = int(rng.randi_range(1, 14));
			const int z = int(rng.randi_range(1, 14));
			int y;
			if (kind == 0) {
				const int64_t a = rng.randi_range(0, 119);
				y = int(rng.randi_range(0, a + 7));
			} else {
				const int64_t a = rng.randi_range(0, 111);
				const int64_t b = rng.randi_range(0, a + 7);
				y = int(rng.randi_range(0, b + 7));
			}
			if (y < 1 || y >= h - 1 || blocks[idx(x, y, z)] != stone)
				continue;
			if (blocks[idx(x, y + 1, z)] != stone || blocks[idx(x, y - 1, z)] != stone)
				continue;
			int walls = 0, air = 0;
			for (const auto &side : SIDES) {
				const int32_t s = blocks[idx(x + side[0], y, z + side[1])];
				if (s == stone)
					walls++;
				else if (s == AIR)
					air++;
			}
			if (walls == 3 && air == 1)
				blocks[idx(x, y, z)] = kind == 0 ? water_spring : lava_spring;
		}
	}
}

void NativeBetaGenerator::freeze(int32_t *blocks, const uint8_t *biomes) const {
	const int y = SEA - 1;
	for (int z = 0; z < 16; z++)
		for (int x = 0; x < 16; x++) {
			if (biome_cold[biomes[z * 16 + x]] != 1)
				continue;
			const int i = idx(x, y, z);
			if (blocks[i] == water && blocks[idx(x, y + 1, z)] == AIR)
				blocks[i] = ice;
			const int top = surface_y(blocks, x, z);
			if (top > 0 && top < h - 1) {
				const int32_t under = blocks[idx(x, top, z)];
				if (table(opaque, under) == 1 || table(leaves, under) == 1)
					blocks[idx(x, top + 1, z)] = snow_layer;
			}
		}
}

// --- Checking and binding ---------------------------------------------------------------

PackedFloat64Array NativeBetaGenerator::check_random(int64_t seed_value, int count) {
	PackedFloat64Array result;
	Pcg rng{ uint64_t(seed_value) };
	for (int i = 0; i < count; i++) {
		switch (i % 6) {
			case 0: result.append(double(rng.randi())); break;
			case 1: result.append(rng.randf()); break;
			case 2: result.append(double(rng.randi_range(0, 15))); break;
			case 3: result.append(double(rng.randi_range(-7, 3))); break;
			case 4: result.append(double(rng.randi_range(2, 2))); break;
			default: result.append(double(rng.randi_range(0, i * 37 + 1))); break;
		}
	}
	return result;
}

void NativeBetaGenerator::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "config"), &NativeBetaGenerator::setup);
	ClassDB::bind_method(D_METHOD("set_tall", "value"), &NativeBetaGenerator::set_tall);
	ClassDB::bind_method(D_METHOD("set_layout", "shift", "deep", "height", "tall"), &NativeBetaGenerator::set_layout);
	ClassDB::bind_method(D_METHOD("set_new_biomes", "value"), &NativeBetaGenerator::set_new_biomes);
	ClassDB::bind_method(D_METHOD("generate_blocks", "cx", "cz"), &NativeBetaGenerator::generate_blocks);
	ClassDB::bind_static_method("NativeBetaGenerator", D_METHOD("check_random", "seed", "count"),
			&NativeBetaGenerator::check_random);
}

} // namespace voxel
