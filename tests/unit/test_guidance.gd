extends DungeonTest

## Covers Guidance: select a character (left-click), then right-click the
## maze to send their whole party there, once every GUIDANCE_COOLDOWN
## seconds. Parties find their way by A* over what they know of the maze,
## assuming unseen passages are open and re-planning as they explore,
## applying the normal rules to anyone in the way.
## Most tests use small hand-built mazes with the character isolated on its
## own maps.

var a: NpcAgent
var players: Dictionary = {}

func before_each():
	load_main()
	a = main.npcs[0]

func after_each():
	get_tree().paused = false

## Moves `a` onto its own hand-built maze and maps, out of the real game's way.
func _isolate(g: Array, cell: Vector2i, explored: Array) -> void:
	main.player_map.erase(a.cell_pos)
	players = {}
	a.players = players
	a.enemies = {}
	a.chests = {}
	a.shops = {}
	a.known_shops = {}
	a.party = [a]
	a.is_party_leader = true
	a.is_moving = false
	a.finished = false
	a.stats.inventory.clear()
	a.grid = g
	a.cell_pos = cell
	a.position = a._cell_to_world(cell)
	a.visited = {}
	a.seen_cells = {}
	a.sight_cells = {}
	a._sight_cell = cell  # so nothing gets "seen" until it moves
	for c in explored:
		a.visited[c] = true
	a.visited[cell] = true
	players[cell] = a

func _row(from_x: int, to_x: int) -> Array:
	var cells: Array = []
	for x in range(from_x, to_x + 1):
		cells.append(Vector2i(x, 0))
	return cells

func _ring_cells() -> Array:
	return [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]

# ========================== Choosing the destination ======================

func test_order_to_an_explored_cell_goes_exactly_there():
	_isolate(corridor(6), Vector2i(0, 0), _row(0, 5))
	assert_true(a.guide_to(Vector2i(5, 0)))
	assert_eq(a.guidance_target, Vector2i(5, 0))

func test_order_into_unexplored_ground_goes_exactly_there():
	_isolate(corridor(6), Vector2i(0, 0), _row(0, 2))
	assert_true(a.guide_to(Vector2i(5, 0)))
	assert_eq(a.guidance_target, Vector2i(5, 0), "no stopping short at the edge of the known")

func test_seen_cells_count_as_known():
	_isolate(corridor(6), Vector2i(0, 0), [])
	a.seen_cells[Vector2i(3, 0)] = true
	assert_true(a._party_known_cells().has(Vector2i(3, 0)), "seen but never walked is still known")

func test_a_partys_pooled_map_counts():
	_isolate(corridor(6), Vector2i(0, 0), [])
	var mate: NpcAgent = main.npcs[1]
	a.party.append(mate)
	mate.party = a.party
	mate.is_party_leader = false
	mate.visited = {Vector2i(4, 0): true}
	mate.seen_cells = {Vector2i(5, 0): true}
	var known: Dictionary = a._party_known_cells()
	assert_true(known.has(Vector2i(4, 0)) and known.has(Vector2i(5, 0)), "what a party member has explored and seen counts too")

func test_order_to_where_the_party_already_is_does_nothing():
	_isolate(corridor(6), Vector2i(2, 0), _row(0, 5))
	assert_false(a.guide_to(Vector2i(2, 0)))
	assert_eq(a.guidance_target, MazeQuery.NONE)

# ============================== Following it ==============================

func test_order_takes_priority_over_a_chest():
	_isolate(corridor(7), Vector2i(3, 0), _row(0, 6))
	a.chests[Vector2i(0, 0)] = true
	a.guide_to(Vector2i(6, 0))
	a.current_action = "Exploring"  # so only the step itself can set it
	a._take_step()
	assert_eq(a.current_action, "Following guidance")

func test_order_routes_around_a_monster():
	_isolate(ring_maze(), Vector2i(0, 0), _ring_cells())
	var enemy := new_enemy()
	enemy.setup(Vector2i(1, 0), main.CELL_SIZE, 1, a.grid, a.enemies, {}, [], false)
	a.guide_to(Vector2i(2, 0))
	assert_eq(a._guidance_step(), Vector2i(0, 1))

func test_order_is_abandoned_if_the_party_backs_off_from_whoever_blocks_the_only_way():
	_isolate(corridor(5), Vector2i(1, 0), _row(0, 4))
	var enemy := new_enemy()
	enemy.setup(Vector2i(2, 0), main.CELL_SIZE, 1, a.grid, a.enemies, {}, [], false)
	# Mid-fight with nobody we could join -- so we can only back off.
	enemy.in_combat = true
	a.guide_to(Vector2i(4, 0))
	a._take_step()
	assert_eq(a.guidance_target, MazeQuery.NONE, "bouncing off the same monster forever helps no one")
	assert_eq(a.current_action, "Guidance blocked")

func test_arriving_clears_the_order():
	_isolate(corridor(5), Vector2i(2, 0), _row(0, 4))
	a.guidance_target = Vector2i(2, 0)
	a._take_step()
	assert_eq(a.guidance_target, MazeQuery.NONE)

func test_party_actually_walks_to_the_ordered_spot():
	# Unexplored ground lies to the right, which its own AI would head for --
	# the order sends it back left over ground it's already covered.
	_isolate(corridor(9), Vector2i(4, 0), _row(0, 5))
	a.guide_to(Vector2i(0, 0))
	var reached := false
	for i in range(50):  # polled in real time: moves are timed in seconds, not frames
		await wait_seconds(0.1)
		if a.cell_pos == Vector2i(0, 0):
			reached = true
			break
	assert_true(reached, "should have walked all the way back to (0,0)")

# ======================= Searching unexplored ground ======================

## Walks `a` one Guidance step at a time, synchronously (no tweens), seeing
## what it can from each new cell -- the cells it stood on, in order.
func _walk_guidance(max_steps: int) -> Array:
	var path: Array = []
	for i in range(max_steps):
		if a.guidance_target == MazeQuery.NONE or a.cell_pos == a.guidance_target:
			break
		var step: Vector2i = a._guidance_step()
		if step == a.cell_pos:
			break
		a.cell_pos = step
		a.visited[step] = true
		a.look_around()
		path.append(step)
	return path

func _open_room(w: int, h: int) -> Array:
	var g := walled_grid(w, h)
	for y in range(h):
		for x in range(w):
			if x < w - 1:
				open_between(g, Vector2i(x, y), Vector2i(x + 1, y))
			if y < h - 1:
				open_between(g, Vector2i(x, y), Vector2i(x, y + 1))
	return g

## 5x5 room with a wall down between x=1 and x=2, open only at the bottom:
## from the left half to the right, it's down, across and back up.
func _divided_room() -> Array:
	var g := _open_room(5, 5)
	for y in range(4):
		g[y][1] |= MazeGenerator.WALL_E
		g[y][2] |= MazeGenerator.WALL_W
	return g

func test_search_heads_straight_across_unseen_ground():
	assert_eq(MazeQuery.explore_step(_open_room(5, 5), Vector2i(0, 0), Vector2i(4, 0), {}), Vector2i(1, 0))

func test_search_plans_around_walls_it_has_seen():
	var known := {}
	for y in range(5):
		for x in range(2):
			known[Vector2i(x, y)] = true
	# Straight right is walled off -- and they've seen that.
	assert_eq(MazeQuery.explore_step(_divided_room(), Vector2i(1, 0), Vector2i(3, 0), known), Vector2i(1, 1))

func test_search_assumes_unseen_passages_are_open():
	# Same wall, but nobody's seen it: worth trying the direct way.
	assert_eq(MazeQuery.explore_step(_divided_room(), Vector2i(1, 0), Vector2i(3, 0), {}), Vector2i(2, 0))

func test_search_never_plans_through_a_known_wall_even_onto_unseen_ground():
	# (1,0) is known; (2,0) isn't -- but the wall between them belongs to
	# (1,0) too, so it's been seen.
	assert_eq(MazeQuery.explore_step(_divided_room(), Vector2i(1, 0), Vector2i(3, 0), {Vector2i(1, 0): true}), Vector2i(1, 1))

func test_search_finds_a_way_round_once_its_guess_turns_out_wrong():
	# Starts out having seen nothing, so its first guess is straight through
	# the wall; it only learns otherwise by looking around as it goes.
	_isolate(_divided_room(), Vector2i(0, 0), [])
	a.guide_to(Vector2i(4, 0))
	var path := _walk_guidance(40)
	assert_eq(a.cell_pos, Vector2i(4, 0), "found it: %s" % [path])
	assert_true(path.has(Vector2i(2, 4)), "through the only gap in the wall")

func test_search_does_not_detour_to_the_nearest_known_cell_first():
	# Open 6x6 room. It's explored the top row and down column 3, so the
	# known cell nearest the target (0,5) is (3,4) -- off to one side...
	var explored := _row(0, 5)
	for y in range(1, 5):
		explored.append(Vector2i(3, y))
	_isolate(_open_room(6, 6), Vector2i(0, 0), explored)
	a.guide_to(Vector2i(0, 5))
	var path := _walk_guidance(20)
	# ...but A* heads straight down the unexplored left side: 5 steps,
	# rather than 7 to (3,4) and 4 more back across.
	assert_eq(path.size(), 5, "shortest way: %s" % [path])
	assert_eq(a.cell_pos, Vector2i(0, 5))
	assert_false(path.has(Vector2i(3, 4)))

func test_party_finds_an_unexplored_spot_in_the_real_maze():
	# The far side of the real 48x48 maze, nowhere near anything it's seen.
	var start: Vector2i = a.cell_pos
	main.player_map.erase(start)
	a.players = {}
	a.enemies = {}
	a.party = [a]
	var target := Vector2i(main.MAZE_WIDTH - 1 - start.x, main.MAZE_HEIGHT - 1 - start.y)
	if target == main.exit_cell:
		target += Vector2i(2, 0)
	assert_false(a._party_known_cells().has(target), "sanity: somewhere unexplored")
	a.guide_to(target)
	_walk_guidance(3000)
	assert_eq(a.cell_pos, target)

# =========================== Party bookkeeping ============================

func test_order_carries_over_to_a_promoted_leader():
	_isolate(corridor(6), Vector2i(0, 0), _row(0, 5))
	var mate: NpcAgent = main.npcs[1]
	a.party.append(mate)
	mate.party = a.party
	mate.is_party_leader = false
	mate.cell_pos = a.cell_pos
	a.guide_to(Vector2i(5, 0))
	a.die()
	assert_eq(mate.guidance_target, Vector2i(5, 0))

func test_order_is_dropped_when_the_party_merges_into_another():
	_isolate(corridor(6), Vector2i(0, 0), _row(0, 5))
	var host: NpcAgent = main.npcs[1]
	host.players = players
	a.guide_to(Vector2i(5, 0))
	PartyOps.join_party_of(a, host)
	assert_eq(a.guidance_target, MazeQuery.NONE, "the host's party isn't ours to steer")

# ============================ Mouse handling ==============================

func _explored_neighbor(npc: NpcAgent, index: int = 0) -> Vector2i:
	var n: Vector2i = MazeQuery.open_neighbors(main.grid, npc.cell_pos)[index]
	npc.visited[n] = true
	return n

func _world_center(cell: Vector2i) -> Vector2:
	return main.npc_container.to_global(a._cell_to_world(cell))

func test_world_to_cell_round_trips():
	var cell := Vector2i(7, 11)
	assert_eq(main.world_to_cell(_world_center(cell)), cell)

func test_right_click_orders_the_selected_party_and_marks_the_spot():
	var target := _explored_neighbor(a)
	main.hud.inspect(a)
	main._on_world_right_clicked(_world_center(target))
	assert_eq(a.guidance_target, target)
	assert_eq(main.maze_view.guidance_marker, target)

func test_right_click_with_a_follower_selected_orders_their_leader():
	var follower: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(follower, a)
	var target := _explored_neighbor(a)
	main.hud.inspect(follower)
	main._on_world_right_clicked(_world_center(target))
	assert_eq(a.guidance_target, target)

func test_right_click_with_nobody_selected_does_nothing():
	var target := _explored_neighbor(a)
	main._on_world_right_clicked(_world_center(target))
	assert_eq(a.guidance_target, MazeQuery.NONE)
	assert_eq(main.maze_view.guidance_marker, MazeQuery.NONE)

func test_right_click_works_while_paused():
	var target := _explored_neighbor(a)
	main.hud.inspect(a)
	main.hud.set_paused(true)
	main._on_world_right_clicked(_world_center(target))
	assert_eq(a.guidance_target, target)

# ================================ Cooldown ================================

func _guide(target: Vector2i) -> void:
	main._on_world_right_clicked(_world_center(target))

func test_giving_guidance_starts_the_cooldown():
	var target := _explored_neighbor(a)
	main.hud.inspect(a)
	_guide(target)
	assert_eq(main.guidance_cooldown_left, main.GUIDANCE_COOLDOWN)
	assert_eq(main.hud.guidance_widget["label"].text, "Guidance 15s")

func test_guidance_is_refused_while_on_cooldown():
	var first := _explored_neighbor(a, 0)
	var second := _explored_neighbor(a, 1)
	main.hud.inspect(a)
	_guide(first)
	_guide(second)
	assert_eq(a.guidance_target, first, "the second right-click should be ignored")

func test_guidance_is_usable_again_once_the_cooldown_runs_out():
	var first := _explored_neighbor(a, 0)
	var second := _explored_neighbor(a, 1)
	main.hud.inspect(a)
	_guide(first)
	main._process(main.GUIDANCE_COOLDOWN)
	assert_eq(main.guidance_cooldown_left, 0.0)
	assert_eq(main.hud.guidance_widget["label"].text, "Guidance ready")
	_guide(second)
	assert_eq(a.guidance_target, second)

func test_indicator_fills_up_as_guidance_recharges():
	var target := _explored_neighbor(a)
	main.hud.inspect(a)
	_guide(target)
	main._process(main.GUIDANCE_COOLDOWN / 2.0)
	assert_almost_eq(main.hud.guidance_widget["bar"].value, 0.5, 0.01)
	assert_eq(main.hud.guidance_widget["label"].text, "Guidance 8s")

func test_right_click_that_gives_no_guidance_does_not_use_up_the_cooldown():
	main.hud.inspect(a)
	_guide(a.cell_pos)  # already there -- nowhere to go
	assert_eq(main.guidance_cooldown_left, 0.0)
	_guide(Vector2i(-50, -50))  # off the maze entirely
	assert_eq(main.guidance_cooldown_left, 0.0)

func test_right_click_with_nobody_selected_does_not_use_up_the_cooldown():
	var target := _explored_neighbor(a)
	_guide(target)
	assert_eq(main.guidance_cooldown_left, 0.0)

func test_cooldown_does_not_tick_while_paused():
	var target := _explored_neighbor(a)
	main.hud.inspect(a)
	main.hud.set_paused(true)
	_guide(target)
	# Not wait_seconds(): GUT's own waiting freezes along with the paused
	# tree and would never return. A process_always timer keeps running.
	await get_tree().create_timer(0.5, true).timeout
	assert_eq(main.guidance_cooldown_left, main.GUIDANCE_COOLDOWN)
