class_name SkyLight
extends RefCounted
## Sky light (0..15 per block) like the classic game: light comes straight
## down from the sky (full 15 through air, minus the opacity of leaves or
## water), then spreads sideways and down into overhangs and caves, losing
## at least 1 per block.
##
## compute_column() lights one column from a 3x3 area of columns around it
## (light travels at most 15 blocks, so everything that can reach the center
## column is inside), so there are no seams at column borders. It runs on a
## worker thread.
##
## Cheap by design: cells above a column's heightmap are implicitly 15 and
## never stored or visited; only columns' lower parts near terrain steps are
## seeded, and the flood fill only touches cells that end up darker.
##
## Written for worker threads: the hot loops touch only packed arrays and
## inline arithmetic. In GDScript, function calls and generic Array indexing
## serialize across threads, so they stay out of the loops.

const MAX := 15
const W := 48 ## area width in blocks (3 columns)
const H := WorldGenerator.HEIGHT
const WW := W * W


## Block ids of a 3x3 column area, index x + W * (z + W * y), from
## `chunks`: 9 arrays (index (dx + 1) * 3 + (dz + 1)) of the 8 chunk block
## arrays of each column. Built in index order from 16-block rows (native
## copies; a per-block loop here was most of the time). Shared by sky light
## and block light (BlockLight).
static func area_of(chunks: Array) -> PackedInt32Array:
	# Each column as one array (index x + 16 * (z + 16 * y)): 8 appends each.
	var columns: Array[PackedInt32Array] = []
	for c in 9:
		var whole := PackedInt32Array()
		for chunk: PackedInt32Array in chunks[c]:
			whole.append_array(chunk)
		columns.append(whole)
	var area := PackedInt32Array()
	for y in H:
		for cz in 3:
			var west := columns[cz]
			var middle := columns[3 + cz]
			var east := columns[6 + cz]
			for lz in 16:
				var row := 16 * (lz + 16 * y)
				area.append_array(west.slice(row, row + 16))
				area.append_array(middle.slice(row, row + 16))
				area.append_array(east.slice(row, row + 16))
	return area


## `area`: block ids of the 3x3 columns (area_of()); `heights`: the 9
## heightmaps. Returns the 8 light arrays of the center column, bottom to top.
static func compute_column(area: PackedInt32Array, heights: Array) -> Array[PackedByteArray]:
	var opacity_of := Blocks.light_opacity_table
	var stored := PackedByteArray()
	stored.resize(WW * H)
	var area_heights := PackedInt32Array()
	area_heights.resize(WW)
	for c in 9:
		var ox := (c / 3) * 16
		var oz := (c % 3) * 16
		var column_heights: PackedInt32Array = heights[c]
		for z in 16:
			for x in 16:
				area_heights[(ox + x) + W * (oz + z)] = column_heights[x + 16 * z]

	# 1. Straight down from the sky through leaves / water.
	for column_index in WW:
		var y := area_heights[column_index]
		var level := MAX
		var cell := column_index + WW * y
		while y >= 0:
			var op := opacity_of[area[cell]]
			if op >= MAX:
				break
			level -= op
			if level <= 0:
				break
			stored[cell] = level
			y -= 1
			cell -= WW

	# 2. Seeds: lit cells next to a neighbor column's darker cells at the
	# same height (terrain steps, cliffs, cave mouths).
	var queue := PackedInt32Array()
	for z in W:
		for x in W:
			var column_index := x + W * z
			var top := area_heights[column_index]
			for d in 4:
				var nx := x
				var nz := z
				if d == 0:
					nx += 1
				elif d == 1:
					nx -= 1
				elif d == 2:
					nz += 1
				else:
					nz -= 1
				if nx < 0 or nz < 0 or nx >= W or nz >= W:
					continue
				var neighbor_index := nx + W * nz
				var neighbor_top := area_heights[neighbor_index]
				for y in range(mini(neighbor_top, H - 1), -1, -1):
					var cell := column_index + WW * y
					var level := MAX if y > top else stored[cell]
					if level <= 1:
						break
					var target := neighbor_index + WW * y
					if stored[target] < level - 1 and opacity_of[area[target]] < MAX:
						queue.append(cell)

	# 3. Flood fill.
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var column_index := cell % WW
		var x := column_index % W
		var z := column_index / W
		var y := cell / WW
		var level := MAX if y > area_heights[column_index] else stored[cell]
		if level <= 1:
			continue
		for d in 6:
			var target := cell
			var target_column := column_index
			var ny := y
			if d == 0:
				if x == W - 1: continue
				target += 1
				target_column += 1
			elif d == 1:
				if x == 0: continue
				target -= 1
				target_column -= 1
			elif d == 2:
				if z == W - 1: continue
				target += W
				target_column += W
			elif d == 3:
				if z == 0: continue
				target -= W
				target_column -= W
			elif d == 4:
				if y == H - 1: continue
				target += WW
				ny += 1
			else:
				if y == 0: continue
				target -= WW
				ny -= 1
			if ny > area_heights[target_column]:
				continue # open sky: already full
			var op := opacity_of[area[target]]
			if op >= MAX:
				continue
			var candidate := level - (op if op > 1 else 1)
			if candidate > stored[target]:
				stored[target] = candidate
				queue.append(target)

	# 4. Light of the center column: open sky above the heightmap is 15
	# (written now, the passes are done), then 16-block rows are copied.
	for lz in 16:
		for lx in 16:
			var column_index := (16 + lx) + W * (16 + lz)
			var cell := column_index + WW * (area_heights[column_index] + 1)
			while cell < WW * H:
				stored[cell] = MAX
				cell += WW
	var result: Array[PackedByteArray] = []
	for k in WorldGenerator.HEIGHT_CHUNKS:
		var light := PackedByteArray()
		for ly in 16:
			var y := k * 16 + ly
			for lz in 16:
				var base := 16 + W * (16 + lz + W * y)
				light.append_array(stored.slice(base, base + 16))
		result.append(light)
	return result
