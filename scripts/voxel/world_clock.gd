class_name WorldClock
extends RefCounted
## Time of one world, counted in ticks (like Minecraft's game time and
## day time).
## - game_time: ticks since the world was created; only ever increases.
##   Scheduled block ticks are keyed by it.
## - day_time: time of day in ticks; can be changed (like /time set or
##   /time add). day_time 0 = 06:00, 6000 = noon, 18000 = midnight.
##   day = floor(day_time / TICKS_PER_DAY).

const TICKS_PER_DAY := 24000

var game_time: int = 0
## Float so that time can also be moved smoothly by fractions of a tick.
var day_time: float = 0.0
## When false, day_time stops (like the doDaylightCycle game rule).
var daylight_cycle := true


func _init(start_day_time: float = 0.0) -> void:
	day_time = start_day_time


func tick() -> void:
	game_time += 1
	if daylight_cycle:
		day_time += 1.0


## Moves the time of day (can be negative).
func add_day_time(ticks: float) -> void:
	day_time = maxf(day_time + ticks, 0.0)


func day() -> int:
	return floori(day_time / TICKS_PER_DAY)


## Ticks since the start of the current day (0 .. 24000).
func time_of_day() -> float:
	return fposmod(day_time, TICKS_PER_DAY)
