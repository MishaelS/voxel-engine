class_name FarTerrain
extends Node3D
## Far terrain (LOD): with a render distance over 16 chunks (REAL_LIMIT),
## the real chunks stop at 16 and the rest, out to the render distance, is
## the land drawn simplified, its quality
## falling off with distance, so mountains and coasts far away are seen
## before their chunks load:
## - each far column is read (its save) or generated on a worker thread,
##   once, and kept as a summary of its 16 x 16 block columns: the highest
##   block (sky light's heightmap: water and leaves count), the block under
##   it and the top's biome tint; then its blocks are dropped;
## - drawn with the blocks' own textures (the tile array, repeated per
##   block; leaves as Beta's fast leaves), tinted like the blocks and shaded
##   per face like them (top 1, sides 0.8 and 0.6), in cells of 1 block next
##   to the real chunks, 2 blocks further and 4 blocks far away (DETAIL):
##   a cell's top at its highest block, walls down to the lower neighbor (the
##   top block's side, then the block under it); tops of the same height and
##   texture in a row are one quad;
## - in regions of 8 x 8 columns, one mesh each, built on a worker thread;
##   columns within the render distance are left out (the real chunks are
##   there), so moving rebuilds only the regions at the edges of the bands;
## - in the fog, which moves out to the far edge (Atmosphere).
## Columns changed by the player while far are seen as last saved.

const REGION := 8                ## columns per region side
const MAX_JOBS := 2              ## columns read at once (when nothing nearer waits)
## For measurements: the far terrain's radius whatever the setting (-1: the
## setting's).
static var test_radius := -1
## Real chunks up to this render distance; the far terrain beyond it.
const REAL_LIMIT := 16
## Cell sizes by distance beyond the render distance: [columns, cell blocks].
const DETAIL := [[4, 1], [10, 2], [1000, 4]]
const SHADE_X := 0.6             ## faces toward x, like the classic game's
const SHADE_Z := 0.8
const KEEP_MARGIN := 2           ## columns kept beyond the radius
const NONE := -1000              ## no wall needed (the real chunks are there)

var world: VoxelWorld

var _radius := 0
var _center := Vector2i(2147483647, 0)
var _near := 0
## column -> [heights, top ids, under ids (PackedInt32Array, 256: x + 16 * z),
## top tints (PackedInt32Array of RGBA8, sRGB)]
var _summaries := {}
var _wanted: Array[Vector2i] = []
var _column_jobs := {}           # column -> [task id, result Array]
var _regions := {}               # region -> MeshInstance3D
var _dirty_regions := {}         # region -> true
var _region_jobs := {}           # region -> [task id, result Array, near, center]
var _material: ShaderMaterial
var _tables := {}                # per block id: top / side layers, tints (_block_tables)
var _brightness_wait := 0.0


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/far_terrain.gdshader")
	_material.set_shader_parameter("tiles", BlockMaterials.tiles())
	_tables = _block_tables()
	Settings.changed.connect(func(key: String, _value: Variant) -> void:
		if key == "render_distance":
			_center = Vector2i(2147483647, 0))


func _exit_tree() -> void:
	for entry: Array in _column_jobs.values():
		WorkerThreadPool.wait_for_task_completion(entry[0])
	for entry: Array in _region_jobs.values():
		WorkerThreadPool.wait_for_task_completion(entry[0])


## How far (chunks) the far terrain reaches, 0 = off (a render distance of
## 16 or less: only real chunks).
static func radius_setting() -> int:
	if test_radius >= 0:
		return test_radius
	var distance := int(Settings.get_value("render_distance"))
	return distance if distance > REAL_LIMIT else 0


## Per block id: "top" / "side" (tile array layers; leaves: the fast
## tile), "tint" (sRGB, its own), "biome" (0, grass 1, foliage 2) and
## "side_tint" (1: the sides are tinted too, no overlay on them).
static func _block_tables() -> Dictionary:
	var top := PackedInt32Array()
	var side := PackedInt32Array()
	var tint := PackedColorArray()
	var biome := PackedByteArray()
	var side_tint := PackedByteArray()
	for id in Blocks.count():
		var block := Blocks.get_type(id)
		var fast: int = block.fast_tile if block and block.fast_tile >= 0 else -1
		top.append(fast if fast >= 0 else (block.tiles[0] if block else 0))
		side.append(fast if fast >= 0 else (block.tiles[2] if block else 0))
		tint.append(block.tint if block else Color.WHITE)
		biome.append(block.biome_tint if block else 0)
		side_tint.append(1 if block and block.overlays[2] < 0 else 0)
	return {"top": top, "side": side, "tint": tint, "biome": biome, "side_tint": side_tint}


func _process(delta: float) -> void:
	if world == null or world.player == null:
		return
	_radius = radius_setting()
	visible = _radius > world.render_distance
	if not visible:
		return
	var center := Vector2i(floori(world.player.global_position.x / 16.0), floori(world.player.global_position.z / 16.0))
	if center != _center or _near != world.render_distance:
		_moved(center)
	_start_column_jobs()
	_finish_column_jobs()
	_start_region_jobs()
	_finish_region_jobs()
	_brightness_wait -= delta
	if _brightness_wait <= 0.0:
		_brightness_wait = 0.5
		# Lit like full sky light now (darker at night).
		var b := world.brightness_at(Vector3(world.player.global_position.x, WorldGenerator.HEIGHT - 1, world.player.global_position.z))
		_material.set_shader_parameter("brightness", b)


## Far columns to read and regions to draw again after moving.
func _moved(center: Vector2i) -> void:
	var old_center := _center
	var old_near := _near
	_center = center
	_near = world.render_distance
	_wanted.clear()
	for ring in range(_radius, _near, -1):
		for dx in range(-ring, ring + 1):
			for dz: int in ([-ring, ring] if absi(dx) != ring else range(-ring, ring + 1)):
				var column := center + Vector2i(dx, dz)
				if not _summaries.has(column) and not _column_jobs.has(column):
					_wanted.append(column) # nearest last (taken first)
	# Forget what is far behind.
	for column: Vector2i in _summaries.keys():
		if _distance(column, center) > _radius + KEEP_MARGIN:
			_summaries.erase(column)
	for region: Vector2i in _regions.keys():
		if _region_distance(region, center) > _radius + KEEP_MARGIN:
			(_regions[region] as Node).queue_free()
			_regions.erase(region)
	# The regions at the edge of the near area (before and after) change.
	# The regions at the edges of the bands (before and after) change: the
	# real chunks' edge and each change of the cell size.
	var dirty := {}
	for pair: Array in [[center, _near], [old_center, old_near]]:
		if (pair[0] as Vector2i).x == 2147483647:
			continue
		var edges := [int(pair[1])]
		for band: Array in DETAIL:
			edges.append(int(pair[1]) + int(band[0]))
		for edge: int in edges:
			for ring in [edge, edge + 1]:
				for region in _regions_on_ring(pair[0], ring):
					dirty[region] = true
	for region: Vector2i in dirty:
		if _regions.has(region) or _region_has_summaries(region):
			_dirty_regions[region] = true


static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _region_distance(region: Vector2i, center: Vector2i) -> int:
	var low := region * REGION
	var nearest := Vector2i(clampi(center.x, low.x, low.x + REGION - 1), clampi(center.y, low.y, low.y + REGION - 1))
	return _distance(nearest, center)


## The regions the columns `ring` away from `center` are in.
func _regions_on_ring(center: Vector2i, ring: int) -> Array[Vector2i]:
	var found := {}
	for i in range(-ring, ring + 1):
		for column: Vector2i in [center + Vector2i(i, -ring), center + Vector2i(i, ring), center + Vector2i(-ring, i), center + Vector2i(ring, i)]:
			found[Vector2i(floori(float(column.x) / REGION), floori(float(column.y) / REGION))] = true
	var result: Array[Vector2i] = []
	result.assign(found.keys())
	return result


func _region_has_summaries(region: Vector2i) -> bool:
	for cx in REGION:
		for cz in REGION:
			if _summaries.has(region * REGION + Vector2i(cx, cz)):
				return true
	return false


# --- Columns: read or generated on worker threads, kept as summaries ---------------------

func _start_column_jobs() -> void:
	# Nearer work first: the real chunks are generated before anything far.
	if not world.is_streaming_idle():
		return
	while _column_jobs.size() < MAX_JOBS and not _wanted.is_empty():
		var column: Vector2i = _wanted.pop_back()
		if _summaries.has(column) or _distance(column, _center) <= _near:
			continue
		var result := []
		var save := world.save if world.save and not world.save.remote else null
		var task := WorkerThreadPool.add_task(_summarize.bind(column, world.world_generator, save, _tables, result),
			false, "Far terrain column")
		_column_jobs[column] = [task, result]


## On a worker thread: a column's summary (its block columns' tops).
static func _summarize(column: Vector2i, generator: WorldGenerator, save: WorldSave, tables: Dictionary, result: Array) -> void:
	if generator == null:
		return
	var blocks := PackedInt32Array()
	if save and save.has_column(column):
		blocks = save.load_column(column)
		if blocks.size() == WorldGenerator.LEGACY_VOLUME:
			blocks = generator.convert_legacy(column.x, column.y, blocks)
	if blocks.size() != WorldGenerator.COLUMN_VOLUME:
		blocks = generator.generate_blocks(column.x, column.y)
	var heights := WorldGenerator.heightmap(blocks)
	var climate := generator.column_colors(column.x, column.y)
	var tops := PackedInt32Array()
	var unders := PackedInt32Array()
	var tints := PackedInt32Array()
	tops.resize(256)
	unders.resize(256)
	tints.resize(256)
	var own: PackedColorArray = tables.tint
	var biome: PackedByteArray = tables.biome
	for i in 256:
		var h := heights[i]
		if h < 0:
			continue
		var id := blocks[i + 256 * h]
		tops[i] = id
		unders[i] = blocks[i + 256 * (h - 1)] if h > 0 else id
		var color := own[id]
		var kind := biome[id]
		if kind > 0 and (climate[kind - 1] as PackedColorArray).size() == 256:
			color = (climate[kind - 1] as PackedColorArray)[i].linear_to_srgb()
		tints[i] = color.to_rgba32()
	result.append_array([heights, tops, unders, tints])


func _finish_column_jobs() -> void:
	for column: Vector2i in _column_jobs.keys():
		var entry: Array = _column_jobs[column]
		if not WorkerThreadPool.is_task_completed(entry[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(entry[0])
		_column_jobs.erase(column)
		var result: Array = entry[1]
		if result.size() == 4:
			_summaries[column] = result
			_dirty_regions[Vector2i(floori(float(column.x) / REGION), floori(float(column.y) / REGION))] = true


# --- Regions: meshes built on worker threads ------------------------------------------

func _start_region_jobs() -> void:
	for region: Vector2i in _dirty_regions.keys():
		if _region_jobs.size() >= 2:
			return
		if _region_jobs.has(region):
			continue
		_dirty_regions.erase(region)
		# The summaries it needs (and the ones around, for the walls).
		var columns := {}
		for cx in range(-1, REGION + 1):
			for cz in range(-1, REGION + 1):
				var column := region * REGION + Vector2i(cx, cz)
				if _summaries.has(column):
					columns[column] = _summaries[column]
		var result := []
		var task := WorkerThreadPool.add_task(_build_region.bind(region, columns, _center, _near, _tables, result), false, "Far terrain mesh")
		_region_jobs[region] = [task, result]


## The cell size (blocks) of a column `d` columns from the player (`near`:
## the render distance).
static func cell_size(d: int, near: int) -> int:
	for band: Array in DETAIL:
		if d <= near + int(band[0]):
			return band[1]
	return 4


## On a worker thread: the region's arrays, its columns near the player
## left out.
static func _build_region(region: Vector2i, columns: Dictionary, center: Vector2i, near: int, tables: Dictionary, result: Array) -> void:
	var mesh := Arrays.new()
	var top_layer: PackedInt32Array = tables.top
	var side_layer: PackedInt32Array = tables.side
	var side_tint: PackedByteArray = tables.side_tint
	var shade_x := pow(SHADE_X, 2.2)
	var shade_z := pow(SHADE_Z, 2.2)
	for cx in REGION:
		for cz in REGION:
			var column := region * REGION + Vector2i(cx, cz)
			var d := maxi(absi(column.x - center.x), absi(column.y - center.y))
			if d <= near:
				continue # the real chunks are drawn there
			var summary: Variant = columns.get(column)
			if summary == null:
				continue
			var size := cell_size(d, near)
			var cells := 16 / size
			var base := Vector2i(column.x * 16, column.y * 16)
			for z in cells:
				var run_start := 0
				var run_key := []
				for x in cells + 1:
					var cell: Array = _cell(columns, center, near, base + Vector2i(x * size, z * size), size) if x < cells else []
					var key := [cell[0], top_layer[cell[1]], cell[3]] if cell.size() > 0 and cell[0] >= 0 else []
					if key != run_key:
						if run_key.size() > 0:
							# A row of equal tops: one quad.
							var y := float(run_key[0] + 1)
							var x0 := float(base.x + run_start * size)
							var x1 := float(base.x + x * size)
							var z0 := float(base.y + z * size)
							var tint := Color.hex(run_key[2]).srgb_to_linear()
							_quad(mesh, [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z0 + size), Vector3(x0, y, z0 + size)],
								[Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z0 + size), Vector2(x0, z0 + size)], run_key[1], tint)
						run_key = key
						run_start = x
					if cell.size() == 0 or cell[0] < 0:
						continue
					# Walls down to the lower neighbors.
					var h: int = cell[0]
					var top := float(h + 1)
					var x0 := float(base.x + x * size)
					var z0 := float(base.y + z * size)
					var tint := Color.hex(cell[3]).srgb_to_linear()
					for side in 4:
						var offset: Vector2i = [Vector2i(size, 0), Vector2i(-size, 0), Vector2i(0, size), Vector2i(0, -size)][side]
						var other: Array = _cell(columns, center, near, base + Vector2i(x * size, z * size) + offset, size)
						var other_h: int = other[0] if other.size() > 0 else -5 + h
						if other_h == NONE or other_h >= h:
							continue
						var bottom := float(other_h + 1)
						var shade := shade_x if side < 2 else shade_z
						var corners: Array
						match side:
							0: corners = [Vector3(x0 + size, 0, z0 + size), Vector3(x0 + size, 0, z0)]
							1: corners = [Vector3(x0, 0, z0), Vector3(x0, 0, z0 + size)]
							2: corners = [Vector3(x0, 0, z0 + size), Vector3(x0 + size, 0, z0 + size)]
							_: corners = [Vector3(x0 + size, 0, z0), Vector3(x0, 0, z0)]
						var a: Vector3 = corners[0]
						var b: Vector3 = corners[1]
						var along_a := a.z if side < 2 else a.x
						var along_b := b.z if side < 2 else b.x
						# The top block's side, then the block under it down to the neighbor.
						for band in 2:
							var y_top := top if band == 0 else top - 1.0
							var y_bottom := maxf(top - 1.0, bottom) if band == 0 else bottom
							if y_bottom >= y_top:
								continue
							var id: int = cell[1] if band == 0 else cell[2]
							var color := (tint if side_tint[id] == 1 else Color.WHITE) * shade
							_quad(mesh, [Vector3(a.x, y_top, a.z), Vector3(b.x, y_top, b.z), Vector3(b.x, y_bottom, b.z), Vector3(a.x, y_bottom, a.z)],
								[Vector2(along_a, -y_top), Vector2(along_b, -y_top), Vector2(along_b, -y_bottom), Vector2(along_a, -y_bottom)],
								side_layer[id], color)
	result.append(mesh)


## A cell of `size` blocks at world block `at` (its corner): [height, top
## id, under id, tint] of its highest block; [NONE] where the real chunks
## are, [] where the column is not known.
static func _cell(columns: Dictionary, center: Vector2i, near: int, at: Vector2i, size: int) -> Array:
	var column := Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
	if maxi(absi(column.x - center.x), absi(column.y - center.y)) <= near:
		return [NONE]
	var summary: Variant = columns.get(column)
	if summary == null:
		return []
	var heights: PackedInt32Array = summary[0]
	var local := at - column * 16
	var best := -1
	var best_i := 0
	for z in size:
		for x in size:
			var i := (local.x + x) + 16 * (local.y + z)
			if heights[i] > best:
				best = heights[i]
				best_i = i
	return [best, (summary[1] as PackedInt32Array)[best_i], (summary[2] as PackedInt32Array)[best_i], (summary[3] as PackedInt32Array)[best_i]]


## A region's mesh arrays (packed arrays in a dictionary would be copied
## on every append).
class Arrays:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var color := PackedColorArray()
	var index := PackedInt32Array()


## A quad (4 corners, their UVs in blocks) with a tile layer and a color.
static func _quad(mesh: Arrays, corners: Array, uvs: Array, layer: int, color: Color) -> void:
	var start := mesh.v.size()
	for k in 4:
		mesh.v.append(corners[k])
		mesh.uv.append(uvs[k])
		mesh.uv2.append(Vector2(layer, 0))
		mesh.color.append(color)
	mesh.index.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))


func _finish_region_jobs() -> void:
	for region: Vector2i in _region_jobs.keys():
		var entry: Array = _region_jobs[region]
		if not WorkerThreadPool.is_task_completed(entry[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(entry[0])
		_region_jobs.erase(region)
		var result: Array = entry[1]
		var instance: MeshInstance3D = _regions.get(region)
		var built: Arrays = result[0] if result.size() == 1 else null
		if built == null or built.v.is_empty():
			if instance:
				instance.queue_free()
				_regions.erase(region)
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = built.v
		arrays[Mesh.ARRAY_TEX_UV] = built.uv
		arrays[Mesh.ARRAY_TEX_UV2] = built.uv2
		arrays[Mesh.ARRAY_COLOR] = built.color
		arrays[Mesh.ARRAY_INDEX] = built.index
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _material)
		if instance == null:
			instance = MeshInstance3D.new()
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)
			_regions[region] = instance
		instance.mesh = mesh


## For the debug screen: far columns known, waiting, regions drawn.
func stats() -> Dictionary:
	return {"columns": _summaries.size(), "waiting": _wanted.size() + _column_jobs.size(), "regions": _regions.size()}
