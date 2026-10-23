extends DungeonTest

## Covers MazeQuery's distances between cells: along the grid (manhattan),
## as a king moves (chebyshev), and which of several cells is nearest.
## Pure functions -- no game needed.

func test_manhattan_counts_steps_along_the_grid():
	assert_eq(MazeQuery.manhattan(Vector2i(0, 0), Vector2i(3, 4)), 7)
	assert_eq(MazeQuery.manhattan(Vector2i(3, 4), Vector2i(0, 0)), 7, "either way round")
	assert_eq(MazeQuery.manhattan(Vector2i(2, 2), Vector2i(2, 2)), 0)

func test_chebyshev_counts_a_diagonal_as_one():
	assert_eq(MazeQuery.chebyshev(Vector2i(0, 0), Vector2i(3, 4)), 4)

func test_the_nearest_of_several_cells():
	var cells := [Vector2i(9, 9), Vector2i(1, 2), Vector2i(5, 0)]
	assert_eq(MazeQuery.nearest(Vector2i(0, 0), cells), Vector2i(1, 2))

func test_a_dictionarys_cells_too():
	assert_eq(MazeQuery.nearest(Vector2i(0, 0), {Vector2i(4, 4): true, Vector2i(0, 3): true}), Vector2i(0, 3))

func test_none_of_none():
	assert_eq(MazeQuery.nearest(Vector2i(0, 0), []), MazeQuery.NONE)
