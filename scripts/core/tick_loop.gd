extends Node
## Autoload "TickLoop": the fixed-rate game loop, like the server loop in
## Minecraft. All game logic (world time, block updates, later entities)
## runs in ticks at a fixed rate (20 per second by default), independent of
## the frame rate. Rendering runs every frame and can interpolate between
## ticks using `alpha`.
##
## Tick listeners are registered per phase; every tick runs the phases in
## order, so e.g. the world clock always advances before entities move.
##
## Debug controls (like /tick in Minecraft): P - freeze/unfreeze,
## period - run one tick while frozen.

enum Phase {
	WORLD,    ## World time, scheduled and random block ticks.
	ENTITIES, ## Mobs, items, players (later).
	LATE,     ## Anything that must see the results of the tick.
}

const DEFAULT_TICK_RATE := 20.0
## If the game falls behind, at most this many ticks run in one frame;
## the rest is dropped (the game slows down instead of freezing: running
## up to 10 slow ticks in a frame made each frame slower still).
const MAX_TICKS_PER_FRAME := 3

## Ticks per second (like /tick rate).
var tick_rate: float = DEFAULT_TICK_RATE:
	set(value):
		tick_rate = clampf(value, 1.0, 1000.0)
## While frozen no ticks run except requested steps (like /tick freeze).
var frozen := false
## Ticks run since start.
var tick_count := 0
## Progress toward the next tick (0..1), for interpolating visuals.
var alpha := 0.0
## Measured ticks per second over the last second.
var measured_tps := 0.0
## Average milliseconds spent per tick (smoothed).
var mspt := 0.0
## Ticks dropped because the game could not keep up.
var skipped_ticks := 0

var _listeners: Array = [] # per phase: Array[Callable]
var _accumulator := 0.0
var _pending_steps := 0
var _tps_window_ticks := 0
var _tps_window_time := 0.0


func _ready() -> void:
	for phase in Phase.size():
		_listeners.append([])


## Quitting (autoloads leave the tree last): the saved world is let go while
## the engine still runs. Its generator holds native objects
## (NativeBetaGenerator and its noises); freed with GDScript's static
## variables at the very end, they could outlive the native library.
func _exit_tree() -> void:
	WorldSave.current = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("tick_freeze"):
		frozen = not frozen
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("tick_step") and frozen:
		step(1)
		get_viewport().set_input_as_handled()


## Calls `listener(tick: int)` every tick in the given phase.
func add_listener(listener: Callable, phase: Phase = Phase.WORLD) -> void:
	if not _listeners[phase].has(listener):
		_listeners[phase].append(listener)


func remove_listener(listener: Callable) -> void:
	for phase_listeners: Array in _listeners:
		phase_listeners.erase(listener)


## Runs `count` ticks while frozen (like /tick step).
func step(count: int = 1) -> void:
	_pending_steps += count


func tick_duration() -> float:
	return 1.0 / tick_rate


func _process(delta: float) -> void:
	var ticks_to_run := 0
	if frozen:
		ticks_to_run = _pending_steps
		_pending_steps = 0
	else:
		_accumulator += delta * tick_rate
		ticks_to_run = int(_accumulator)
		_accumulator -= ticks_to_run
		if ticks_to_run > MAX_TICKS_PER_FRAME:
			skipped_ticks += ticks_to_run - MAX_TICKS_PER_FRAME
			ticks_to_run = MAX_TICKS_PER_FRAME
		alpha = _accumulator

	for i in ticks_to_run:
		_run_tick()

	_tps_window_time += delta
	if _tps_window_time >= 1.0:
		measured_tps = _tps_window_ticks / _tps_window_time
		_tps_window_ticks = 0
		_tps_window_time = 0.0


## Time of each listener in the last tick (microseconds, by node name and
## method), for profiling.
var listener_times := {}


func _run_tick() -> void:
	var start_us := Time.get_ticks_usec()
	for phase_listeners: Array in _listeners:
		for listener: Callable in phase_listeners:
			var before := Time.get_ticks_usec()
			listener.call(tick_count)
			var owner := listener.get_object()
			var key := "%s.%s" % [owner.name if owner is Node else owner.get_class(), listener.get_method()]
			listener_times[key] = Time.get_ticks_usec() - before
	tick_count += 1
	_tps_window_ticks += 1
	var tick_ms := (Time.get_ticks_usec() - start_us) / 1000.0
	mspt = lerpf(mspt, tick_ms, 0.1)
