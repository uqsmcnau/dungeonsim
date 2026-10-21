extends DungeonTest

## Covers the maze's outline -- a circle (MazeShape) with solid rock
## beyond it (MazeGenerator.OUTSIDE) -- and everything that has to keep to
## it: the maze itself, the zones, who and what's placed, sight, route
## planning, Guidance, and the border drawn round it.

func before_each():
	load_main()

func _maze_cells() -> Array:
	var cells: Array = []
	for y in range(main.MAZE_HEIGHT):
		for x in range(main.MAZE_WIDTH):
			if not MazeGenerator.is_outside(main.grid, Vector2i(x, y)):
				cells.append(Vector2i(x, y))
	return cells

func _assert_zone_inside(center: Vector2i, what: String) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			assert_false(MazeGenerator.is_outside(main.grid, center + Vector2i(dx, dy)), "%s at %s" % [what, center])

# ================================ The shape ===============================

func test_the_outline_is_an_even_circle():
	var size: int = main.MAZE_WIDTH
	var shape := MazeShape.circle(size, size)
	assert_eq(shape.radius, size / 2.0 - 1.0, "as big as fits, a cell's margin to the grid's edge")
	assert_true(shape.contains(Vector2i(size / 2, size / 2)), "the middle")
	for corner in [Vector2i(0, 0), Vector2i(size - 1, 0), Vector2i(0, size - 1), Vector2i(size - 1, size - 1)]:
		assert_false(shape.contains(corner), "the corner %s" % corner)
	for point in shape.outline(36):
		assert_almost_eq(point.distance_to(shape.center), shape.radius, 0.001, "round, not wobbly")

func test_the_circle_is_symmetrical():
	# Mirrored about the middle cell's centre, every way round.
	var size: int = main.MAZE_WIDTH
	var shape := MazeShape.circle(size, size)
	var middle := size / 2
	for y in range(size):
		for x in range(size):
			var mirrored := Vector2i(2 * middle - x, 2 * middle - y)
			if mirrored.x < size and mirrored.y < size:
				assert_eq(shape.contains(Vector2i(x, y)), shape.contains(mirrored))

func test_only_cells_inside_the_outline_are_maze():
	# ...all of them, bar any the edge pinches off from the rest (see
	# MazeGenerator._cut_off_stragglers): those are rock, with no maze next
	# to them side-on.
	for y in range(main.MAZE_HEIGHT):
		for x in range(main.MAZE_WIDTH):
			var cell := Vector2i(x, y)
			if not MazeGenerator.is_outside(main.grid, cell):
				assert_true(main.maze_shape.contains(cell), "%s is maze outside the outline" % cell)
			elif main.maze_shape.contains(cell):
				for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					assert_true(MazeGenerator.is_outside(main.grid, cell + dir), "%s was cut off, yet touches maze" % cell)

func test_a_cell_the_edge_pinches_off_turns_to_rock():
	# A 5x5 "outline" (everything but a ring of rock) with one cell left
	# touching the rest only at a corner.
	var g: Array = []
	for y in range(5):
		var row: Array = []
		for x in range(5):
			row.append(MazeGenerator.ALL_WALLS)
		g.append(row)
	for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		g[c.y][c.x] |= MazeGenerator.OUTSIDE
	g[0][0] &= ~MazeGenerator.OUTSIDE  # (0,0): inside, but only (1,1) diagonally
	MazeGenerator.new()._cut_off_stragglers(g, Vector2i(2, 2))
	assert_true(MazeGenerator.is_outside(g, Vector2i(0, 0)))
	assert_false(MazeGenerator.is_outside(g, Vector2i(1, 1)), "the rest stays maze")

func test_the_rock_is_solid():
	for y in range(main.MAZE_HEIGHT):
		for x in range(main.MAZE_WIDTH):
			if MazeGenerator.is_outside(main.grid, Vector2i(x, y)):
				assert_eq(main.grid[y][x], MazeGenerator.ALL_WALLS | MazeGenerator.OUTSIDE)

# ================================ The maze ================================

func test_every_cell_of_the_maze_can_be_reached():
	var seen: Dictionary = {main.exit_cell: true}
	var frontier: Array = [main.exit_cell]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for n in MazeQuery.open_neighbors(main.grid, cell):
			if not seen.has(n):
				seen[n] = true
				frontier.append(n)
	assert_eq(seen.size(), _maze_cells().size())

func test_no_passage_leads_into_the_rock():
	for cell in _maze_cells():
		for n in MazeQuery.open_neighbors(main.grid, cell):
			assert_false(MazeGenerator.is_outside(main.grid, n), "%s opens onto rock at %s" % [cell, n])

func test_the_start_zones_ring_the_edge():
	var shape: MazeShape = main.maze_shape
	var angles: Array = []
	for start in main.start_cells:
		_assert_zone_inside(start, "a start zone")
		var offset: Vector2 = Vector2(start) + Vector2(0.5, 0.5) - shape.center
		assert_gt(offset.length(), shape.radius * 0.75, "near the edge, far from the boss")
		angles.append(fposmod(offset.angle(), TAU))
	angles.sort()
	var even_gap: float = TAU / angles.size()
	for i in range(angles.size()):
		var gap: float = fposmod(angles[(i + 1) % angles.size()] - angles[i], TAU)
		assert_almost_eq(gap, even_gap, even_gap * 0.5, "spread evenly round")

func test_twenty_six_players_eight_shops_and_six_mini_bosses():
	assert_eq(main.npcs.size(), 26)
	assert_eq(main.shop_cells.size(), 8)
	assert_eq(main.mini_boss_cells.size(), 6)
	var minis := 0
	for enemy in main.enemy_container.get_children():
		if enemy.is_mini_boss:
			minis += 1
	assert_eq(minis, 6)

func test_every_player_has_their_own_name_and_color():
	var names := {}
	var colors := {}
	for npc in main.npcs:
		names[npc.npc_name] = true
		colors[npc.visual.color] = true
	assert_eq(names.size(), 26)
	assert_eq(colors.size(), 26)

func test_the_shops_ring_the_boss_room():
	var shape: MazeShape = main.maze_shape
	var quarters := {}
	for shop in main.shop_cells:
		var offset: Vector2 = Vector2(shop) + Vector2(0.5, 0.5) - shape.center
		assert_gt(offset.length(), 6.0, "clear of the boss room")
		quarters[int(fposmod(offset.angle(), TAU) / (TAU / 4.0))] = true
	assert_eq(quarters.size(), 4, "some in every quarter of the maze")

func test_shops_and_mini_boss_rooms_are_inside():
	for shop in main.shop_cells:
		_assert_zone_inside(shop, "a shop")
	for room in main.mini_boss_cells:
		_assert_zone_inside(room, "a mini boss room")

func test_nothing_stands_in_the_rock():
	for npc in main.npcs:
		assert_false(MazeGenerator.is_outside(main.grid, npc.cell_pos), npc.npc_name)
	for cell in main.enemy_map:
		assert_false(MazeGenerator.is_outside(main.grid, cell), "a monster at %s" % cell)
	for cell in main.chest_map:
		assert_false(MazeGenerator.is_outside(main.grid, cell), "a chest at %s" % cell)

func test_nobody_sees_into_the_rock():
	for npc in main.npcs:
		for cell in npc.look_around():
			assert_false(MazeGenerator.is_outside(main.grid, cell), "%s sees rock at %s" % [npc.npc_name, cell])

# ============================== Getting about =============================

func test_route_planning_never_goes_through_rock():
	# Unexplored, the straight way from (0,0) to (2,0) looks open -- but
	# (1,0) is rock, so the only way round is down and along the bottom.
	var g := walled_grid(3, 2)
	g[0][1] |= MazeGenerator.OUTSIDE
	open_between(g, Vector2i(0, 0), Vector2i(0, 1))
	open_between(g, Vector2i(0, 1), Vector2i(1, 1))
	open_between(g, Vector2i(1, 1), Vector2i(2, 1))
	open_between(g, Vector2i(2, 1), Vector2i(2, 0))
	assert_eq(MazeQuery.explore_step(g, Vector2i(0, 0), Vector2i(2, 0), {}), Vector2i(0, 1))

func test_guidance_cant_send_a_party_into_the_rock():
	var npc: NpcAgent = main.npcs[0]
	main.hud.inspect(npc)
	main._on_world_right_clicked(main.maze_view.to_global(Vector2(5, 5)))  # cell (0,0), a corner
	assert_eq(npc.guidance_target, MazeQuery.NONE)

# ================================ Drawing =================================

func test_the_border_runs_round_outside_the_maze():
	var view: MazeView = main.maze_view
	var shape: MazeShape = main.maze_shape
	assert_false(view._border.is_empty())
	for point in view._border:
		var offset: Vector2 = point / view.cell_size - shape.center
		assert_gt(offset.length(), shape.radius, "beyond the maze's edge")

func test_the_floor_covers_exactly_the_maze():
	var cells := 0.0
	for run in main.maze_view._floor:
		cells += run.size.x / main.maze_view.cell_size
	assert_almost_eq(cells, float(_maze_cells().size()), 0.01)
