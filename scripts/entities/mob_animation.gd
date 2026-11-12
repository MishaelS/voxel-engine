class_name MobAnimation
extends RefCounted
## Poses for the creature models (MobModels), in the style of Beta 1.7.3's
## models (ModelBiped, ModelZombie, ModelQuadruped, EntitySlime):
## - idle: arms drift slowly out and back (the game's arm sway), the head
##   bobs a little and now and then looks around;
## - holding something: the arm is raised a little, like the game's;
## - walking: legs swing 1.4 and arms 1.0 by the walking speed (opposite
##   arm and leg together); zombies and skeletons keep their arms ahead;
## - sneaking (the player): the body bends 0.5 forward, arms come forward,
##   legs step back under it, the head drops a pixel;
## - jumping: one leg forward, the other back (quadrupeds: front legs ahead,
##   back legs behind); slimes stretch up when they jump and squash when
##   they land;
## - falling fast: arms spread out and up, legs apart;
## - hurt: red, with a short flinch back;
## - dying: red, falling over sideways (then a puff of smoke);
## - sleeping (the player): lying on the back in the bed, head on the pillow.
## Angles are ours: the game's X angles keep their sign, Y and Z flip (its
## model space is upside down and turned around).

## Ticks between idle look-arounds.
const LOOK_AROUND := Vector2i(40, 160)


## The game's idle arm sway at `t` ticks: [x, z] for the right arm (the left
## one takes the opposite).
static func arm_sway(t: float) -> Vector2:
	return Vector2(sin(t * 0.067) * 0.05, -(cos(t * 0.09) * 0.05 + 0.05))


## A little nod of the head while standing.
static func head_bob(t: float) -> float:
	return sin(t * 0.05) * 0.04


## How far into a jump (0..1, rising) and a fall (0..1, falling fast) a
## creature is, from its vertical speed in blocks per tick.
static func jump_amount(velocity_y: float, on_ground: bool, in_water: bool) -> float:
	if on_ground or in_water:
		return 0.0
	return clampf(velocity_y / 0.42, 0.0, 1.0)


static func fall_amount(velocity_y: float, on_ground: bool, in_water: bool) -> float:
	if on_ground or in_water:
		return 0.0
	return clampf((-velocity_y - 0.25) / 0.6, 0.0, 1.0)


## The flinch when hurt: 0..1 over the hurt ticks (quick, settling back).
static func flinch(hurt_ticks: int, alpha: float, length: int) -> float:
	if hurt_ticks <= 0:
		return 0.0
	var f := clampf((hurt_ticks - alpha) / length, 0.0, 1.0)
	return sin(f * f * f * f * PI)


## Poses a two-legged body (zombie, skeleton, the player): `parts` the
## model's pivots, `t` age in ticks, `swing` / `amount` the walk cycle,
## `holding` an item in the right hand, `arms_ahead` zombie-like arms.
static func pose_biped(parts: Dictionary, t: float, swing: float, amount: float, holding: bool,
		arms_ahead: bool, jump: float, fall: float) -> void:
	var right_arm: Node3D = parts.get("right_arm")
	var left_arm: Node3D = parts.get("left_arm")
	var right_leg: Node3D = parts.get("right_leg")
	var left_leg: Node3D = parts.get("left_leg")
	var walk := swing * 0.6662
	var sway := arm_sway(t)
	if right_leg and left_leg:
		right_leg.rotation = Vector3(cos(walk) * 1.4 * amount, 0, 0)
		left_leg.rotation = Vector3(cos(walk + PI) * 1.4 * amount, 0, 0)
		# Jumping: a leg ahead, the other behind; falling: legs apart.
		right_leg.rotation.x += -0.5 * jump
		left_leg.rotation.x += 0.3 * jump
		right_leg.rotation.z += 0.12 * fall
		left_leg.rotation.z -= 0.12 * fall
	if right_arm == null or left_arm == null:
		return
	if arms_ahead:
		# ModelZombie: both arms straight ahead, a little apart.
		right_arm.rotation = Vector3(-PI / 2.0, 0.1, 0)
		left_arm.rotation = Vector3(-PI / 2.0, -0.1, 0)
	else:
		right_arm.rotation = Vector3(cos(walk + PI) * amount, 0, 0)
		left_arm.rotation = Vector3(cos(walk) * amount, 0, 0)
		if holding:
			right_arm.rotation.x = right_arm.rotation.x * 0.5 - PI / 10.0
	right_arm.rotation.x += sway.x
	right_arm.rotation.z += sway.y
	left_arm.rotation.x -= sway.x
	left_arm.rotation.z -= sway.y
	# Up and out: a little when jumping, wide when falling.
	var lift := jump * 0.25 + fall * 0.9
	if not arms_ahead:
		right_arm.rotation.x -= lift * 0.4
		left_arm.rotation.x -= lift * 0.4
	right_arm.rotation.z -= lift
	left_arm.rotation.z += lift


## Poses a four-legged body's legs (ModelQuadruped) with the jump and fall.
static func pose_quadruped_leg(node: Node3D, front: bool, a_side: bool, swing: float, amount: float,
		jump: float, fall: float) -> void:
	var walk := cos(swing * 0.6662 + (0.0 if a_side else PI)) * 1.4 * amount
	node.rotation.x = walk + (-0.6 if front else 0.6) * jump
	node.rotation.z = (0.15 if a_side == front else -0.15) * fall


## The game's slime squish: `squish` > 0 stretches it up, < 0 squashes
## it; returns the model's scale factors for a slime of `size`.
static func slime_scale(squish: float, size: int) -> Vector3:
	var f := squish / (size * 0.5 + 1.0)
	var across := 1.0 / (f + 1.0)
	return Vector3(across, 1.0 / across, across)
