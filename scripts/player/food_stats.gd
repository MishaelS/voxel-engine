class_name FoodStats
extends RefCounted
## Hunger like the classic game (1.8 rules):
## - food level 0..20 (10 drumsticks) and hidden saturation (starts at 5);
## - actions add exhaustion (sprinting, jumping, swimming, breaking blocks,
##   taking damage); every 4 exhaustion takes 1 saturation, or 1 food when
##   saturation is gone;
## - with food 18+ the player heals 1 half heart every 4 seconds (which
##   costs 3 exhaustion); at food 0 starvation hurts every 4 seconds, down
##   to half a heart;
## - at food 6 or less the player can't sprint.

const MAX_FOOD := 20
const REGEN_FOOD := 18
const SPRINT_FOOD := 6
const TIMER_TICKS := 80
const EXHAUSTION_STEP := 4.0
const REGEN_EXHAUSTION := 3.0

## Exhaustion of actions (per block moved, per jump, per block broken...).
const SPRINT_PER_BLOCK := 0.1
const WALK_PER_BLOCK := 0.01
const SWIM_PER_BLOCK := 0.015
const JUMP := 0.2
const SPRINT_JUMP := 0.8
const BREAK_BLOCK := 0.025
const DAMAGE := 0.1

var food := MAX_FOOD
var saturation := 5.0
var exhaustion := 0.0
var _timer := 0


func add_exhaustion(amount: float) -> void:
	exhaustion = minf(exhaustion + amount, 40.0)


## Restores food and saturation (eating; for food items later).
func eat(food_points: int, saturation_modifier: float) -> void:
	food = mini(food + food_points, MAX_FOOD)
	saturation = minf(saturation + food_points * saturation_modifier * 2.0, food)


func can_sprint() -> bool:
	return food > SPRINT_FOOD


func reset() -> void:
	food = MAX_FOOD
	saturation = 5.0
	exhaustion = 0.0
	_timer = 0


## One game tick: spends exhaustion, heals or starves the player.
func tick(player: Player, natural_regeneration: bool) -> void:
	if exhaustion > EXHAUSTION_STEP:
		exhaustion -= EXHAUSTION_STEP
		if saturation > 0.0:
			saturation = maxf(saturation - 1.0, 0.0)
		else:
			food = maxi(food - 1, 0)
	if natural_regeneration and food >= REGEN_FOOD and player.health < Player.MAX_HEALTH:
		_timer += 1
		if _timer >= TIMER_TICKS:
			player.heal(1)
			add_exhaustion(REGEN_EXHAUSTION)
			_timer = 0
	elif food <= 0:
		_timer += 1
		if _timer >= TIMER_TICKS:
			if player.health > 1:
				player.damage(1)
			_timer = 0
	else:
		_timer = 0


func save_state() -> Dictionary:
	return {"food": food, "saturation": saturation, "exhaustion": exhaustion}


func load_state(saved: Dictionary) -> void:
	food = clampi(saved.get("food", MAX_FOOD), 0, MAX_FOOD)
	saturation = saved.get("saturation", 5.0)
	exhaustion = saved.get("exhaustion", 0.0)
