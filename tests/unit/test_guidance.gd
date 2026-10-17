extends GutTest

## Covers Guidance: select a character (left-click), then right-click the
## maze to send their whole party there, once every GUIDANCE_COOLDOWN
## seconds. Parties only route through ground they've explored, apply the
## normal rules to anyone in the way, then carry on. Most tests use small
## hand-built mazes with the character isolated on its own maps.

const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")

var main: Node
var a: NpcAgent
var players: Dictionary = {}

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())
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
	for c in explored:
		a.visited[c] = true
	a.visited[cell] = true
	players[cell] = a

func _walled_grid(w: int, h: int) -> Array:
	var g: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			row.append(MazeGenerator.WALL_N | MazeGenerator.WALL_E | MazeGenerator.WALL_S | MazeGenerator.WALL_W)
		g.append(row)
	return g

func _open(g: Array, p: Vector2i, q: Vector2i) -> void:
	if q.x > p.x:
		g[p.y][p.x] &= ~MazeGenerator.WALL_E
		g[q.y][q.x] &= ~MazeGenerator.WALL_W
	elif q.x < p.x:
		_open(g, q, p)
	elif q.y > p.y:
		g[p.y][p.x] &= ~MazeGenerator.WALL_S
		g[q.y][q.x] &= ~MazeGenerator.WALL_N
	else:
		_open(g, q, p)

func _corridor(length: int) -> Array:
	var g := _walled_grid(length, 1)
	for x in range(length - 1):
		_open(g, Vector2i(x, 0), Vector2i(x + 1, 0))
	return g

func _row(from_x: int, to_x: int) -> Array:
	var cells: Array = []
	for x in range(from_x, to_x + 1):
		cells.append(Vector2i(x, 0))
	return cells

## 3x2 ring: straight along the top, or the long way round the bottom.
func _ring() -> Array:
	var g := _walled_grid(3, 2)
	_open(g, Vector2i(0, 0), Vector2i(1, 0))
	_open(g, Vector2i(1, 0), Vector2i(2, 0))
	_open(g, Vector2i(0, 0), Vector2i(0, 1))
	_open(g, Vector2i(0, 1), Vector2i(1, 1))
	_open(g, Vector2i(1, 1), Vector2i(2, 1))
	_open(g, Vector2i(2, 1), Vector2i(2, 0))
	return g

func _ring_cells() -> Array:
	return [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]

# ========================== Choosing the destination ======================

func test_order_to_an_explored_cell_goes_exactly_there():
	_isolate(_corridor(6), Vector2i(0, 0), _row(0, 5))
	assert_true(a.guide_to(Vector2i(5, 0)))
	assert_eq(a.guidance_target, Vector2i(5, 0))

func test_order_into_unexplored_ground_stops_at_the_nearest_known_cell():
	_isolate(_corridor(6), Vector2i(0, 0), _row(0, 2))
	a.guide_to(Vector2i(5, 0))
	assert_eq(a.guidance_target, Vector2i(2, 0), "only explored ground is routable")

func test_known_but_unreachable_cell_is_not_a_valid_destination():
	# (4,0) has been seen before, but the cells joining it to here haven't.
	_isolate(_corridor(6), Vector2i(0, 0), [Vector2i(1, 0), Vector2i(4, 0)])
	a.guide_to(Vector2i(4, 0))
	assert_eq(a.guidance_target, Vector2i(1, 0))

func test_order_to_where_the_party_already_is_does_nothing():
	_isolate(_corridor(6), Vector2i(2, 0), _row(0, 5))
	assert_false(a.guide_to(Vector2i(2, 0)))
	assert_eq(a.guidance_target, MazeQuery.NONE)

func test_party_pools_what_its_members_have_explored():
	_isolate(_corridor(6), Vector2i(0, 0), _row(0, 1))
	var mate: NpcAgent = main.npcs[1]
	a.party.append(mate)
	mate.party = a.party
	mate.is_party_leader = false
	mate.visited = {}
	for c in _row(2, 5):
		mate.visited[c] = true
	a.guide_to(Vector2i(5, 0))
	assert_eq(a.guidance_target, Vector2i(5, 0), "a party member's exploring counts too")

# ============================== Following it ==============================

func test_order_takes_priority_over_a_chest():
	_isolate(_corridor(7), Vector2i(3, 0), _row(0, 6))
	a.chests[Vector2i(0, 0)] = true
	a.guide_to(Vector2i(6, 0))
	a.current_action = "Exploring"  # so only the step itself can set it
	a._take_step()
	assert_eq(a.current_action, "Following guidance")

func test_order_routes_around_a_monster():
	_isolate(_ring(), Vector2i(0, 0), _ring_cells())
	var enemy: EnemyAgent = add_child_autofree(ENEMY_SCENE.instantiate())
	enemy.setup(Vector2i(1, 0), main.CELL_SIZE, 1, a.grid, a.enemies, {}, [], false)
	a.guide_to(Vector2i(2, 0))
	assert_eq(a._route_through_known(a.guidance_target, a._party_known_cells(), a._live_enemy_cells()), Vector2i(0, 1))

func test_order_is_abandoned_if_the_party_backs_off_from_whoever_blocks_the_only_way():
	_isolate(_corridor(5), Vector2i(1, 0), _row(0, 4))
	var enemy: EnemyAgent = add_child_autofree(ENEMY_SCENE.instantiate())
	enemy.setup(Vector2i(2, 0), main.CELL_SIZE, 1, a.grid, a.enemies, {}, [], false)
	# Mid-fight with nobody we could join -- so we can only back off.
	enemy.in_combat = true
	a.guide_to(Vector2i(4, 0))
	a._take_step()
	assert_eq(a.guidance_target, MazeQuery.NONE, "bouncing off the same monster forever helps no one")
	assert_eq(a.current_action, "Guidance blocked")

func test_arriving_clears_the_order():
	_isolate(_corridor(5), Vector2i(2, 0), _row(0, 4))
	a.guidance_target = Vector2i(2, 0)
	a._take_step()
	assert_eq(a.guidance_target, MazeQuery.NONE)

func test_party_actually_walks_to_the_ordered_spot():
	# Unexplored ground lies to the right, which its own AI would head for --
	# the order sends it back left over ground it's already covered.
	_isolate(_corridor(9), Vector2i(4, 0), _row(0, 5))
	a.guide_to(Vector2i(0, 0))
	var reached := false
	for i in range(50):  # polled in real time: moves are timed in seconds, not frames
		await wait_seconds(0.1)
		if a.cell_pos == Vector2i(0, 0):
			reached = true
			break
	assert_true(reached, "should have walked all the way back to (0,0)")

# =========================== Party bookkeeping ============================

func test_order_carries_over_to_a_promoted_leader():
	_isolate(_corridor(6), Vector2i(0, 0), _row(0, 5))
	var mate: NpcAgent = main.npcs[1]
	a.party.append(mate)
	mate.party = a.party
	mate.is_party_leader = false
	mate.cell_pos = a.cell_pos
	a.guide_to(Vector2i(5, 0))
	a._die()
	assert_eq(mate.guidance_target, Vector2i(5, 0))

func test_order_is_dropped_when_the_party_merges_into_another():
	_isolate(_corridor(6), Vector2i(0, 0), _row(0, 5))
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
