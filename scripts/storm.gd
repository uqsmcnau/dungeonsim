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
## Every maze cell the storm covers right now -- worked out again each time
## the ring's shrunk another RECOUNT_STEP, not every frame.
var covered: Dictionary = {}
## Every maze cell that isn't safe ground, for the AI to keep out of (see
## NpcRoutes.storm_cells): those the storm covers, plus any dry pocket it's
## cut off from the middle of the maze. A pocket's only way on is through
## the storm, and the storm will have it soon -- so safe ground is the dry
## ground still joined to the middle, and getting out of the storm means
## getting there, not just to the nearest dry cell (which might be the
## pocket it's just left). Once the middle itself is covered, any dry cell
## will do. Worked out along with `covered` -- but looking ahead to where
## the ring will be by the next time it's worked out, so it never lags
## behind the storm and lets the AI walk onto a cell the ring's just
## crept over.
var unsafe: Dictionary = {}
var _grid: Array = []
## The radius `covered` was last worked out at, and whether it's been worked
## out since the storm closed.
var _counted_at := INF
var _counted_closed := false

## The storm for maze `grid`, of `shape` -- or, without a shape, one whose
## ring a test sets up itself (`center`, `start_radius`).
func _init(shape: MazeShape = null, grid: Array = []) -> void:
	_grid = grid
	if shape == null:
		return
	center = shape.center
	start_radius = shape.radius + 1.0
	radius = start_radius

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

## Whether `cell` is safe ground (see `unsafe`) -- anywhere, before the
## storm's begun.
func is_safe(cell: Vector2i) -> bool:
	return not unsafe.has(cell)

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
	unsafe.clear()
	var dry: Array = []
	var ahead := radius - RECOUNT_STEP  # where the ring will be by the next recount
	for y in range(_grid.size()):
		for x in range(_grid[0].size()):
			var cell := Vector2i(x, y)
			if MazeGenerator.is_outside(_grid, cell):
				continue
			if covers(cell):
				covered[cell] = true
			if not has_started():
				continue
			if is_closed() or (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(center) > ahead:
				unsafe[cell] = true
			else:
				dry.append(cell)
	var middle := Vector2i(floori(center.x), floori(center.y))
	if unsafe.has(middle) or dry.is_empty():
		return
	var joined := _dry_ground_joined_to(middle)
	for cell in dry:
		if not joined.has(cell):
			unsafe[cell] = true

## The dry cells reachable from `start` through open passages without
## setting foot in the storm (or where it's about to be).
func _dry_ground_joined_to(start: Vector2i) -> Dictionary:
	var reached: Dictionary = {start: true}
	var frontier: Array = [start]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_back()
		for n in MazeQuery.open_neighbors(_grid, cur):
			if not reached.has(n) and not unsafe.has(n):
				reached[n] = true
				frontier.append(n)
	return reached
