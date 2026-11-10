class_name BlockLight
extends RefCounted
## Light from glowing blocks (0..15 per block) like the classic game's
## block light: torches 14, lava, fire and glowstone 15, a burning furnace
## 13... (BlockType.light_emission). It spreads in every direction, losing
## at least 1 per block (more through leaves or water) and stopping at
## opaque blocks. Kept apart from sky light: the shaders use the brighter
## of the two (sky light minus the night's darkness, block light).
##
## compute_column() lights one column from the 3x3 columns around it (light
## travels at most 15 blocks), on a worker thread, with the same block area
## as the sky light (SkyLight.area_of()). Changes later are made by
## VoxelWorld (removal and re-spreading, like sky light).

const MAX := 15
const W := SkyLight.W
const H := SkyLight.H
const WW := W * W


## Returns the 8 block light arrays of the center column, bottom to top.
static func compute_column(area: PackedInt32Array) -> Array[PackedByteArray]:
	var opacity_of := Blocks.light_opacity_table
	var emission_of := Blocks.light_emission_table
	var stored := PackedByteArray()
	stored.resize(WW * H)
	var queue := PackedInt32Array()
	# Sources: every glowing block in the area (native search per kind).
	for id in Blocks.glowing_ids:
		var cell := area.find(id)
		while cell >= 0:
			stored[cell] = emission_of[id]
			queue.append(cell)
			cell = area.find(id, cell + 1)
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var level := stored[cell]
		if level <= 1:
			continue
		var column_index := cell % WW
		var x := column_index % W
		var z := column_index / W
		var y := cell / WW
		for d in 6:
			var target := cell
			if d == 0:
				if x == W - 1: continue
				target += 1
			elif d == 1:
				if x == 0: continue
				target -= 1
			elif d == 2:
				if z == W - 1: continue
				target += W
			elif d == 3:
				if z == 0: continue
				target -= W
			elif d == 4:
				if y == H - 1: continue
				target += WW
			else:
				if y == 0: continue
				target -= WW
			var op := opacity_of[area[target]]
			if op >= MAX:
				continue
			var candidate := level - (op if op > 1 else 1)
			if candidate > stored[target]:
				stored[target] = candidate
				queue.append(target)
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
