class_name Storm
extends RefCounted

## The storm closing in on the maze, battle-royale style. For its first
## START_SECONDS it's gathering just beyond the maze's edge; then its ring
## shrinks steadily towards the centre, closing completely at
## CLOSED_SECONDS. Anyone outside the ring is "in the storm": they lose HP
## (DAMAGE_PER_SECOND) and can't heal (see NpcAgent._weather_the_storm), and
## everyone's AI steers clear of it where it can.
##
## One shared by everyone (GameManager.storm), timed by the game -- so it
## waits while the game's paused. Everything is in cell units, measured from
## the maze's centre (see MazeShape).

const START_SECONDS := 30.0
const CLOSED_SECONDS := 600.0
const DAMAGE_PER_SECOND := 1.0
## How far the ring has to shrink before `covered` is worked out again.
const RECOUNT_STEP := 0.25

var center := Vector2.ZERO
## The ring's radius before it starts closing: just beyond the maze's edge.
var start_radius := 0.0
var elapsed := 0.0
## The ring's radius right now.
var radius := 0.0
## Every maze cell the storm covers right now, for the AI to steer round
## (see NpcRoutes.storm_cells) -- worked out again each time the ring's
## shrunk another RECOUNT_STEP, not every frame.
var covered: Dictionary = {}
var _grid: Array = []
## The radius `covered` was last worked out at, and whether it's been worked
## out since the storm closed.
var _counted_at := INF
var _counted_closed := false

## The storm for a maze of `shape` -- or, without one, a storm that covers
## nothing until told otherwise (a test's hand-made one).
func _init(shape: MazeShape = null, grid: Array = []) -> void:
	if shape == null:
		return
	center = shape.center
	start_radius = shape.radius + 1.0
	radius = start_radius
	_grid = grid

## Moves the storm on by `delta` seconds.
func advance(delta: float) -> void:
	elapsed += delta
	radius = radius_at(elapsed)
	if radius < _counted_at - RECOUNT_STEP or (is_closed() and not _counted_closed):
		_recount()

## The ring's radius `seconds` into the game.
func radius_at(seconds: float) -> float:
	if seconds <= START_SECONDS:
		return start_radius
	var left := clampf((CLOSED_SECONDS - seconds) / (CLOSED_SECONDS - START_SECONDS), 0.0, 1.0)
	return start_radius * left

func has_started() -> bool:
	return elapsed > START_SECONDS

func is_closed() -> bool:
	return elapsed >= CLOSED_SECONDS

## Whether the storm covers `cell` -- outside the ring once it's begun, or
## everywhere once it's closed.
func covers(cell: Vector2i) -> bool:
	if not has_started():
		return false
	if is_closed():
		return true
	return (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(center) > radius

func _recount() -> void:
	_counted_at = radius
	_counted_closed = is_closed()
	covered.clear()
	for y in range(_grid.size()):
		for x in range(_grid[0].size()):
			var cell := Vector2i(x, y)
			if not MazeGenerator.is_outside(_grid, cell) and covers(cell):
				covered[cell] = true
