class_name MazeGenerator
extends RefCounted

const WALL_N = 1
const WALL_E = 2
const WALL_S = 4
const WALL_W = 8
const ALL_WALLS = WALL_N | WALL_E | WALL_S | WALL_W

## Returns a height x width array of ints, each a bitmask of which of its
## four walls are still closed (see WALL_* constants above). A perfect maze
## has exactly one path between any two cells; extra_connection_chance
## knocks down that many additional interior walls afterward, adding loops
## so there are multiple routes through (e.g. toward the center goal).
func generate(width: int, height: int, extra_connection_chance: float = 0.0) -> Array:
	var grid: Array = []
	for y in range(height):
		var row: Array = []
		for x in range(width):
			row.append(ALL_WALLS)
		grid.append(row)

	var visited: Array = []
	for y in range(height):
		var row: Array = []
		for x in range(width):
			row.append(false)
		visited.append(row)

	var stack: Array = []
	var start := Vector2i(0, 0)
	visited[start.y][start.x] = true
	stack.append(start)

	while stack.size() > 0:
		var current: Vector2i = stack[stack.size() - 1]
		var neighbors := _unvisited_neighbors(current, width, height, visited)
		if neighbors.is_empty():
			stack.pop_back()
			continue
		var next_cell: Vector2i = neighbors[randi() % neighbors.size()]
		_remove_wall(grid, current, next_cell)
		visited[next_cell.y][next_cell.x] = true
		stack.append(next_cell)

	if extra_connection_chance > 0.0:
		_braid(grid, width, height, extra_connection_chance)

	return grid

## Knocks down extra walls between adjacent cells at random, turning the
## perfect (single-path) maze into one with loops and multiple routes.
func _braid(grid: Array, width: int, height: int, chance: float) -> void:
	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			if x < width - 1 and (grid[y][x] & WALL_E) and randf() < chance:
				_remove_wall(grid, cell, cell + Vector2i(1, 0))
			if y < height - 1 and (grid[y][x] & WALL_S) and randf() < chance:
				_remove_wall(grid, cell, cell + Vector2i(0, 1))

## Carves a 3x3 open room (no internal walls) centered on `center`, sealed
## on every outer edge except for a single one-cell entrance at the middle
## of each side (north, south, east, west). Call this after generate() (and
## after any braiding) so nothing else can punch extra holes into it.
func carve_boss_room(grid: Array, center: Vector2i, width: int, height: int) -> void:
	if center.x < 2 or center.x > width - 3 or center.y < 2 or center.y > height - 3:
		return

	var min_x := center.x - 1
	var max_x := center.x + 1
	var min_y := center.y - 1
	var max_y := center.y + 1

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			if x < max_x:
				_remove_wall(grid, cell, cell + Vector2i(1, 0))
			if y < max_y:
				_remove_wall(grid, cell, cell + Vector2i(0, 1))

	for x in range(min_x, max_x + 1):
		_seal_wall(grid, Vector2i(x, min_y), Vector2i(x, min_y - 1))
		_seal_wall(grid, Vector2i(x, max_y), Vector2i(x, max_y + 1))
	for y in range(min_y, max_y + 1):
		_seal_wall(grid, Vector2i(min_x, y), Vector2i(min_x - 1, y))
		_seal_wall(grid, Vector2i(max_x, y), Vector2i(max_x + 1, y))

	_remove_wall(grid, Vector2i(center.x, min_y), Vector2i(center.x, min_y - 1))
	_remove_wall(grid, Vector2i(center.x, max_y), Vector2i(center.x, max_y + 1))
	_remove_wall(grid, Vector2i(min_x, center.y), Vector2i(min_x - 1, center.y))
	_remove_wall(grid, Vector2i(max_x, center.y), Vector2i(max_x + 1, center.y))

## Clears internal walls in a (2*radius+1)-wide square centered on `center`,
## clipped to the maze bounds. Unlike carve_boss_room, the outer boundary is
## left exactly as generation produced it — this is for simple open pockets
## (like a starting area sitting on the border) rather than a controlled
## set-piece room with a fixed number of entrances.
func open_room(grid: Array, center: Vector2i, width: int, height: int, radius: int = 1) -> void:
	var min_x: int = max(0, center.x - radius)
	var max_x: int = min(width - 1, center.x + radius)
	var min_y: int = max(0, center.y - radius)
	var max_y: int = min(height - 1, center.y + radius)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			if x < max_x:
				_remove_wall(grid, cell, cell + Vector2i(1, 0))
			if y < max_y:
				_remove_wall(grid, cell, cell + Vector2i(0, 1))

func _unvisited_neighbors(cell: Vector2i, width: int, height: int, visited: Array) -> Array:
	var result: Array = []
	var dirs = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for d in dirs:
		var n: Vector2i = cell + d
		if n.x >= 0 and n.x < width and n.y >= 0 and n.y < height and not visited[n.y][n.x]:
			result.append(n)
	return result

func _remove_wall(grid: Array, a: Vector2i, b: Vector2i) -> void:
	var dx := b.x - a.x
	var dy := b.y - a.y
	if dx == 1:
		grid[a.y][a.x] &= ~WALL_E
		grid[b.y][b.x] &= ~WALL_W
	elif dx == -1:
		grid[a.y][a.x] &= ~WALL_W
		grid[b.y][b.x] &= ~WALL_E
	elif dy == 1:
		grid[a.y][a.x] &= ~WALL_S
		grid[b.y][b.x] &= ~WALL_N
	elif dy == -1:
		grid[a.y][a.x] &= ~WALL_N
		grid[b.y][b.x] &= ~WALL_S

func _seal_wall(grid: Array, a: Vector2i, b: Vector2i) -> void:
	var height: int = grid.size()
	var width: int = grid[0].size()
	if b.x < 0 or b.x >= width or b.y < 0 or b.y >= height:
		return
	var dx := b.x - a.x
	var dy := b.y - a.y
	if dx == 1:
		grid[a.y][a.x] |= WALL_E
		grid[b.y][b.x] |= WALL_W
	elif dx == -1:
		grid[a.y][a.x] |= WALL_W
		grid[b.y][b.x] |= WALL_E
	elif dy == 1:
		grid[a.y][a.x] |= WALL_S
		grid[b.y][b.x] |= WALL_N
	elif dy == -1:
		grid[a.y][a.x] |= WALL_N
		grid[b.y][b.x] |= WALL_S
