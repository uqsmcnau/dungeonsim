extends GutTest

## Covers MazeGenerator's structural guarantees in isolation -- no scene
## instantiation needed, just the grid data it produces.

var generator: MazeGenerator

func before_each():
	generator = MazeGenerator.new()

## Flood-fills from (0,0) through open passages and returns how many
## distinct cells it reached.
func _reachable_count(grid: Array) -> int:
	var seen: Dictionary = {Vector2i(0, 0): true}
	var frontier: Array = [Vector2i(0, 0)]
	while not frontier.is_empty():
		var next_frontier: Array = []
		for cur in frontier:
			for n in MazeQuery.open_neighbors(grid, cur):
				if not seen.has(n):
					seen[n] = true
					next_frontier.append(n)
		frontier = next_frontier
	return seen.size()

func test_generated_maze_is_fully_connected():
	var width := 20
	var height := 20
	var grid: Array = generator.generate(width, height)
	assert_eq(_reachable_count(grid), width * height)

func test_generated_maze_stays_fully_connected_with_braiding():
	var width := 20
	var height := 20
	var grid: Array = generator.generate(width, height, 0.3)
	assert_eq(_reachable_count(grid), width * height, "adding loops should never disconnect anything")

func test_perfect_maze_has_exactly_cells_minus_one_open_edges():
	# A perfect (unbraided) maze is a spanning tree over the grid: exactly
	# (width*height - 1) edges, no more, no less, regardless of the random
	# path the generator happened to take.
	var width := 10
	var height := 10
	var grid: Array = generator.generate(width, height)
	var open_edges := 0
	for y in range(height):
		for x in range(width):
			var walls: int = grid[y][x]
			if x < width - 1 and not (walls & MazeGenerator.WALL_E):
				open_edges += 1
			if y < height - 1 and not (walls & MazeGenerator.WALL_S):
				open_edges += 1
	assert_eq(open_edges, width * height - 1)

func test_braiding_only_ever_adds_edges_never_removes_them():
	var width := 15
	var height := 15
	seed(12345)
	var unbraided: Array = MazeGenerator.new().generate(width, height, 0.0)
	seed(12345)
	var braided: Array = MazeGenerator.new().generate(width, height, 1.0)

	var unbraided_open := 0
	var braided_open := 0
	for y in range(height):
		for x in range(width):
			if not (unbraided[y][x] & MazeGenerator.WALL_E):
				unbraided_open += 1
			if not (unbraided[y][x] & MazeGenerator.WALL_S):
				unbraided_open += 1
			if not (braided[y][x] & MazeGenerator.WALL_E):
				braided_open += 1
			if not (braided[y][x] & MazeGenerator.WALL_S):
				braided_open += 1
	assert_gte(braided_open, unbraided_open)

func test_carve_boss_room_opens_the_full_3x3_interior():
	var width := 20
	var height := 20
	var grid: Array = generator.generate(width, height)
	var center := Vector2i(10, 10)
	generator.carve_boss_room(grid, center, width, height)

	# Every one of the 12 internal edges between adjacent room cells should
	# be open -- no internal walls left standing anywhere in the 3x3.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := center + Vector2i(dx, dy)
			if dx < 1:
				assert_has(MazeQuery.open_neighbors(grid, cell), cell + Vector2i(1, 0))
			if dy < 1:
				assert_has(MazeQuery.open_neighbors(grid, cell), cell + Vector2i(0, 1))

func test_carve_boss_room_has_exactly_four_entrances():
	var width := 20
	var height := 20
	var grid: Array = generator.generate(width, height)
	var center := Vector2i(10, 10)
	generator.carve_boss_room(grid, center, width, height)

	var min_x := center.x - 1
	var max_x := center.x + 1
	var min_y := center.y - 1
	var max_y := center.y + 1

	# Count open connections from any room cell to any cell outside the
	# room's 3x3 bounds -- carve_boss_room should leave exactly one per side.
	var entrances := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := center + Vector2i(dx, dy)
			for n in MazeQuery.open_neighbors(grid, cell):
				var in_room: bool = n.x >= min_x and n.x <= max_x and n.y >= min_y and n.y <= max_y
				if not in_room:
					entrances += 1
	assert_eq(entrances, 4, "the boss room should have exactly one entrance per side")

func test_open_room_clears_internal_walls_without_erroring_at_grid_edges():
	var width := 10
	var height := 10
	var grid: Array = generator.generate(width, height)
	# A corner, so the clip-to-bounds logic actually gets exercised.
	generator.open_room(grid, Vector2i(0, 0), width, height)
	assert_has(MazeQuery.open_neighbors(grid, Vector2i(0, 0)), Vector2i(1, 0))
	assert_has(MazeQuery.open_neighbors(grid, Vector2i(0, 0)), Vector2i(0, 1))
