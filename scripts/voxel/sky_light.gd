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

const MAX := 15
const W := 48 ## area width in blocks (3 columns)
const H := WorldGenerator.HEIGHT


## `chunks`: 9 arrays (index (dx + 1) * 3 + (dz + 1)) of the 8 chunk block
## arrays of each column; `heights`: the 9 heightmaps. Returns the 8 light
## arrays of the center column, bottom to top.
static func compute_column(chunks: Array, heights: Array) -> Array[PackedByteArray]:
	var opacity := Blocks.light_opacity_table
	var stored := PackedByteArray()
	stored.resize(W * W * H)
	var area_heights := PackedInt32Array()
	area_heights.resize(W * W)
	for c in 9:
		var ox := (c / 3) * 16
		var oz := (c % 3) * 16
		var column_heights: PackedInt32Array = heights[c]
		for z in 16:
			for x in 16:
				area_heights[(ox + x) + W * (oz + z)] = column_heights[x + 16 * z]

	# 1. Straight down from the sky through leaves / water.
	for z in W:
		for x in W:
			var y := area_heights[x + W * z]
			var level := MAX
			while y >= 0:
				var op := opacity[_block(chunks, x, y, z)]
				if op >= MAX:
					break
				level -= op
				if level <= 0:
					break
				stored[_index(x, y, z)] = level
				y -= 1

	# 2. Seeds: lit cells next to a neighbor column's darker cells at the
	# same height (terrain steps, cliffs, cave mouths).
	var queue := PackedInt32Array()
	for z in W:
		for x in W:
			var top := area_heights[x + W * z]
			for d in 4:
				var nx := x + (1 if d == 0 else (-1 if d == 1 else 0))
				var nz := z + (1 if d == 2 else (-1 if d == 3 else 0))
				if nx < 0 or nz < 0 or nx >= W or nz >= W:
					continue
				var neighbor_top := area_heights[nx + W * nz]
				for y in range(mini(neighbor_top, H - 1), -1, -1):
					var level := MAX if y > top else stored[_index(x, y, z)]
					if level <= 1:
						break
					var target := _index(nx, y, nz)
					if stored[target] < level - 1 and opacity[_block(chunks, nx, y, nz)] < MAX:
						queue.append(_index(x, y, z))

	# 3. Flood fill.
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var x := cell % W
		var z := (cell / W) % W
		var y := cell / (W * W)
		var level := MAX if y > area_heights[x + W * z] else stored[cell]
		if level <= 1:
			continue
		for d in 6:
			var nx := x
			var ny := y
			var nz := z
			match d:
				0: nx += 1
				1: nx -= 1
				2: nz += 1
				3: nz -= 1
				4: ny += 1
				5: ny -= 1
			if nx < 0 or nz < 0 or ny < 0 or nx >= W or nz >= W or ny >= H:
				continue
			if ny > area_heights[nx + W * nz]:
				continue # open sky: already full
			var op := opacity[_block(chunks, nx, ny, nz)]
			if op >= MAX:
				continue
			var candidate := level - maxi(op, 1)
			var target := _index(nx, ny, nz)
			if candidate > stored[target]:
				stored[target] = candidate
				queue.append(target)

	# 4. Light of the center column.
	var result: Array[PackedByteArray] = []
	for k in WorldGenerator.HEIGHT_CHUNKS:
		var light := PackedByteArray()
		light.resize(ChunkData.VOLUME)
		for ly in 16:
			var y := k * 16 + ly
			for lz in 16:
				for lx in 16:
					var i := lx + 16 * (lz + 16 * ly)
					if y > area_heights[(16 + lx) + W * (16 + lz)]:
						light[i] = MAX
					else:
						light[i] = stored[_index(16 + lx, y, 16 + lz)]
		result.append(light)
	return result


static func _index(x: int, y: int, z: int) -> int:
	return x + W * (z + W * y)


static func _block(chunks: Array, x: int, y: int, z: int) -> int:
	var column: Array = chunks[(x >> 4) * 3 + (z >> 4)]
	var blocks: PackedByteArray = column[y >> 4]
	return blocks[(x & 15) + 16 * ((z & 15) + 16 * (y & 15))]
