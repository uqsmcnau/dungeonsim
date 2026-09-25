class_name MazeQuery
extends RefCounted

const NONE := Vector2i(-1, -1)

## Cells reachable in one step from `cell` through an open passage.
static func open_neighbors(grid: Array, cell: Vector2i) -> Array:
	var walls: int = grid[cell.y][cell.x]
	var width: int = grid[0].size()
	var height: int = grid.size()
	var result: Array = []
	if not (walls & MazeGenerator.WALL_N) and cell.y > 0:
		result.append(cell + Vector2i(0, -1))
	if not (walls & MazeGenerator.WALL_E) and cell.x < width - 1:
		result.append(cell + Vector2i(1, 0))
	if not (walls & MazeGenerator.WALL_S) and cell.y < height - 1:
		result.append(cell + Vector2i(0, 1))
	if not (walls & MazeGenerator.WALL_W) and cell.x > 0:
		result.append(cell + Vector2i(-1, 0))
	return result

## True if a straight line between the two cell centers only ever crosses
## open passages. Walls sit on cell edges, so a diagonal hop counts as clear
## as long as at least one of the two orthogonal routes around its corner is
## open — which lets open rooms be seen across diagonally while still being
## blocked by walls.
static func has_line_of_sight(grid: Array, from: Vector2i, to: Vector2i) -> bool:
	var x := from.x
	var y := from.y
	var dx: int = abs(to.x - x)
	var dy: int = abs(to.y - y)
	var sx: int = 1 if to.x > x else -1
	var sy: int = 1 if to.y > y else -1
	var err: int = dx - dy

	while x != to.x or y != to.y:
		var prev := Vector2i(x, y)
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
		if not _hop_open(grid, prev, Vector2i(x, y)):
			return false
	return true

## The closest cell (by Manhattan distance) that's a key in `targets`, is
## within `sight_range` cells, and is in line of sight — or NONE.
static func nearest_visible(grid: Array, from: Vector2i, sight_range: int, targets: Dictionary) -> Vector2i:
	var best := NONE
	var best_dist := 1 << 30
	for c in targets:
		var dx: int = abs(c.x - from.x)
		var dy: int = abs(c.y - from.y)
		if (dx == 0 and dy == 0) or max(dx, dy) > sight_range:
			continue
		var d: int = dx + dy
		if d < best_dist and has_line_of_sight(grid, from, c):
			best = c
			best_dist = d
	return best

## First step of a shortest path from `from` to `to` through open passages,
## searching at most `max_depth` steps out and never entering `blocked`
## cells. Returns `from` itself when there's no such path.
static func step_toward(grid: Array, from: Vector2i, to: Vector2i, max_depth: int, blocked: Dictionary = {}) -> Vector2i:
	if from == to:
		return from
	var came_from: Dictionary = {from: from}
	var frontier: Array = [from]
	var depth := 0
	while not frontier.is_empty() and depth < max_depth:
		var next_frontier: Array = []
		for cur in frontier:
			for n in open_neighbors(grid, cur):
				if came_from.has(n) or blocked.has(n):
					continue
				came_from[n] = cur
				if n == to:
					var step: Vector2i = n
					while came_from[step] != from:
						step = came_from[step]
					return step
				next_frontier.append(n)
		frontier = next_frontier
		depth += 1
	return from

static func _edge_open(grid: Array, a: Vector2i, b: Vector2i) -> bool:
	var walls: int = grid[a.y][a.x]
	if b.x > a.x:
		return not (walls & MazeGenerator.WALL_E)
	if b.x < a.x:
		return not (walls & MazeGenerator.WALL_W)
	if b.y > a.y:
		return not (walls & MazeGenerator.WALL_S)
	return not (walls & MazeGenerator.WALL_N)

static func _hop_open(grid: Array, a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x or a.y == b.y:
		return _edge_open(grid, a, b)
	var via_x := Vector2i(b.x, a.y)
	var via_y := Vector2i(a.x, b.y)
	return (_edge_open(grid, a, via_x) and _edge_open(grid, via_x, b)) \
		or (_edge_open(grid, a, via_y) and _edge_open(grid, via_y, b))
