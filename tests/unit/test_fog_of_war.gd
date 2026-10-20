extends DungeonTest

## Covers fog-of-war visibility syncing in game_manager._process, including
## a regression for a real bug: enemy_map only ever holds a pack's leader,
## so a loop that only walked enemy_map left pack followers permanently
## visible regardless of fog state (they default to Node2D's visible=true
## and nothing ever touched it).

func before_each():
	load_main()
	# Every NPC starts out somewhere within sight range of its own start
	# cell's safe zone, which varies run to run with the random maze layout
	# and whatever RNG state earlier tests left behind. Pin every one of
	# them to its exact start cell so "nobody can see this far-off cell" is
	# actually guaranteed rather than incidental.
	for i in range(main.npcs.size()):
		main.npcs[i].cell_pos = main.start_cells[i]

## A cell that is unrestricted, has no enemy/chest already on it, and is
## further than sight range from every NPC's (pinned) start cell -- so it's
## guaranteed hidden until a test explicitly moves an observer onto it.
## Distance has to be Chebyshev (max of the two axes), matching the box
## check MazeQuery.visible_cells actually uses -- Manhattan distance would
## let a cell like dx=4,dy=4 (Manhattan 8, outside a sight range of 6) slip
## through as "far enough" even though its Chebyshev distance (4) is well
## within range.
func _isolated_cell() -> Vector2i:
	for c in main.world.unrestricted_cells():
		if main.enemy_map.has(c) or main.chest_map.has(c):
			continue
		var too_close := false
		for s in main.start_cells:
			if max(abs(c.x - s.x), abs(c.y - s.y)) <= NpcAgent.SIGHT_RANGE:
				too_close = true
				break
		if not too_close:
			return c
	return Vector2i(-1, -1)

func test_solo_enemy_is_hidden_when_no_one_can_see_it_and_visible_once_someone_can():
	var cell: Vector2i = _isolated_cell()
	assert_ne(cell, Vector2i(-1, -1), "sanity: should always find an isolated cell in a 48x48 maze")
	var enemy := new_enemy()
	enemy.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])

	main._process(0.0)
	assert_false(enemy.visible, "an enemy nobody can see should be hidden")

	# Put a living NPC exactly on the enemy's cell -- trivially in line of
	# sight of itself regardless of maze layout -- and it should show.
	var observer: NpcAgent = main.npcs[0]
	observer.cell_pos = cell
	main._process(0.0)
	assert_true(enemy.visible, "an enemy a living NPC is standing right on top of should be visible")

func test_pack_followers_are_hidden_along_with_the_leader():
	var cell: Vector2i = _isolated_cell()
	var leader := new_enemy()
	var follower := new_enemy()
	leader.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	follower.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	EnemyAgent.form_pack([leader, follower])

	main._process(0.0)
	assert_false(leader.visible, "the pack leader should be hidden when nobody can see the cell")
	assert_false(follower.visible,
		"the follower must be hidden too -- this is the bug: enemy_map only has the leader, " +
		"so a loop that only walks enemy_map never touches followers at all")

func test_pack_followers_become_visible_along_with_the_leader():
	var cell: Vector2i = _isolated_cell()
	var leader := new_enemy()
	var follower := new_enemy()
	leader.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	follower.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	EnemyAgent.form_pack([leader, follower])

	var observer: NpcAgent = main.npcs[0]
	observer.cell_pos = cell
	main._process(0.0)

	assert_true(leader.visible, "the pack leader should be visible once someone can see the cell")
	assert_true(follower.visible,
		"the follower should become visible too, not stay stuck visible=true regardless of fog (the reported bug) nor stuck hidden")

func test_pack_followers_hide_again_once_out_of_sight():
	var cell: Vector2i = _isolated_cell()
	var leader := new_enemy()
	var follower := new_enemy()
	leader.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	follower.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	EnemyAgent.form_pack([leader, follower])

	var observer: NpcAgent = main.npcs[0]
	observer.cell_pos = cell
	main._process(0.0)
	assert_true(follower.visible)

	# Move the only nearby observer back to its own (isolated) start cell.
	observer.cell_pos = main.start_cells[0]
	main._process(0.0)
	assert_false(leader.visible)
	assert_false(follower.visible,
		"a follower must hide again once nothing can see that cell any more -- " +
		"it shouldn't get stuck visible=true the first time it was ever shown")
