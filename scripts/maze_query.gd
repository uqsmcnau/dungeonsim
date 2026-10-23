class_name MazeQuery
extends RefCounted

const NONE := Vector2i(-1, -1)

## How many cells apart `a` and `b` are as a king moves, diagonals counting
## as one (Chebyshev distance) -- the shape sight reaches (see visible_cells).
static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

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

## Every cell someone standing on `center` can see: within `sight_range`
## (Chebyshev distance), inside the maze, and in line of sight.
static func visible_cells(grid: Array, center: Vector2i, sight_range: int) -> Dictionary:
	var cells: Dictionary = {}
	for dy in range(-sight_range, sight_range + 1):
		for dx in range(-sight_range, sight_range + 1):
			var c := Vector2i(center.x + dx, center.y + dy)
			if MazeGenerator.is_outside(grid, c):
				continue
			if has_line_of_sight(grid, center, c):
				cells[c] = true
	return cells

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

## First step of a shortest path from `from` out of `region` (cells as
## keys) -- to the nearest cell that isn't in it -- never entering `blocked`
## cells on the way. Returns `from` itself if it's already out, or there's
## no way out.
static func step_out_of(grid: Array, from: Vector2i, region: Dictionary, blocked: Dictionary = {}) -> Vector2i:
	if not region.has(from):
		return from
	var came_from: Dictionary = {from: from}
	var frontier: Array = [from]
	while not frontier.is_empty():
		var next_frontier: Array = []
		for cur in frontier:
			for n in open_neighbors(grid, cur):
				if came_from.has(n) or blocked.has(n):
					continue
				came_from[n] = cur
				if not region.has(n):
					var step: Vector2i = n
					while came_from[step] != from:
						step = came_from[step]
					return step
				next_frontier.append(n)
		frontier = next_frontier
	return from

## First step of an A* search from `from` to `to` across a maze that's only
## partly known: a passage touching a `known` cell is as the grid says (seeing
## a cell means seeing its walls), but between two unknown cells it's assumed
## open until seen otherwise. That guess is optimistic, so the route is only
## a best guess -- call this again after every step, as new walls come into
## view, and the plan corrects itself. Never enters an `avoid` cell (other
## than `to` itself). Returns `from` if there's no route at all.
static func explore_step(grid: Array, from: Vector2i, to: Vector2i, known: Dictionary, avoid: Dictionary = {}) -> Vector2i:
	if from == to:
		return from
	var came_from: Dictionary = {from: from}
	var cost: Dictionary = {from: 0}
	var heap := _Heap.new()
	heap.push(_manhattan(from, to), from)
	while not heap.is_empty():
		var cur: Vector2i = heap.pop()
		if cur == to:
			var step: Vector2i = cur
			while came_from[step] != from:
				step = came_from[step]
			return step
		for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = cur + dir
			if MazeGenerator.is_outside(grid, n):  # off the grid, or rock: never a way through
				continue
			if avoid.has(n) and n != to:
				continue
			if (known.has(cur) or known.has(n)) and not _edge_open(grid, cur, n):
				continue
			var g: int = cost[cur] + 1
			if cost.has(n) and cost[n] <= g:
				continue
			cost[n] = g
			came_from[n] = cur
			# Ties on f go to the deeper node (smaller h), so A* runs straight
			# at the goal across open ground instead of fanning out sideways.
			heap.push((g + _manhattan(n, to)) * 4096 - g, n)
	return from

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

## Minimal binary min-heap of cells by integer priority, for explore_step.
class _Heap:
	var keys: Array[int] = []
	var cells: Array[Vector2i] = []

	func is_empty() -> bool:
		return keys.is_empty()

	func push(key: int, cell: Vector2i) -> void:
		keys.append(key)
		cells.append(cell)
		var i := keys.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if keys[parent] <= keys[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> Vector2i:
		var top: Vector2i = cells[0]
		var last := keys.size() - 1
		_swap(0, last)
		keys.resize(last)
		cells.resize(last)
		var i := 0
		while true:
			var smallest := i
			for child in [2 * i + 1, 2 * i + 2]:
				if child < last and keys[child] < keys[smallest]:
					smallest = child
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var k := keys[a]
		keys[a] = keys[b]
		keys[b] = k
		var c := cells[a]
		cells[a] = cells[b]
		cells[b] = c

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
