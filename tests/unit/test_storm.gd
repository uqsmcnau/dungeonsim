extends DungeonTest

## Covers the storm (Storm): gathering for its first 30 seconds, then
## closing in to cover the whole maze at 600; what it does to anyone caught
## in it (HP drains away, none comes back); and how everyone's AI keeps out
## of it where it can, and gets out of it when caught.

## A storm covering just the cells it's given -- for steering tests on a
## hand-built maze, where the real storm's ring means nothing.
class _Region extends Storm:
	func _init(cells: Array) -> void:
		elapsed = START_SECONDS + 1.0
		for c in cells:
			covered[c] = true

	func covers(cell: Vector2i) -> bool:
		return covered.has(cell)

var a: NpcAgent
var b: NpcAgent
var players: Dictionary = {}

func before_each():
	load_main()
	a = main.npcs[0]
	b = main.npcs[1]

## `npc` alone on hand-built maze `g` at `cell`, with a storm over `stormy`.
func _stand_in_storm(npc: NpcAgent, g: Array, cell: Vector2i, stormy: Array, explored: Array = []) -> void:
	isolate(npc, g, cell, players, explored)
	npc.storm = _Region.new(stormy)

## A maze cell the real storm covers, once it's been closing for a while.
func _a_stormy_cell(storm: Storm) -> Vector2i:
	for c in storm.covered:
		return c
	return MazeQuery.NONE

# ================================ The ring ================================

func test_the_storm_gathers_for_thirty_seconds():
	var storm: Storm = main.storm
	assert_eq(storm.radius_at(0.0), storm.start_radius)
	assert_eq(storm.radius_at(Storm.START_SECONDS), storm.start_radius)
	storm.advance(Storm.START_SECONDS - 1.0)
	assert_true(storm.covered.is_empty(), "nowhere's covered yet")
	assert_false(storm.covers(main.start_cells[0]))

func test_it_starts_just_outside_the_maze():
	var storm: Storm = main.storm
	assert_gt(storm.start_radius, main.maze_shape.radius, "every cell of the maze inside it")
	assert_lte(storm.start_radius, main.maze_shape.radius + 1.5)
	assert_eq(storm.center, main.maze_shape.center)

func test_then_it_closes_steadily_to_nothing_at_600_seconds():
	var storm: Storm = main.storm
	var halfway := (Storm.START_SECONDS + Storm.CLOSED_SECONDS) / 2.0
	assert_almost_eq(storm.radius_at(halfway), storm.start_radius / 2.0, 0.001)
	assert_eq(storm.radius_at(Storm.CLOSED_SECONDS), 0.0)
	var last := INF
	for t in range(30, 601, 30):
		assert_lt(storm.radius_at(t), last + 0.0001)
		last = storm.radius_at(t)

func test_by_600_seconds_it_covers_everything():
	var storm: Storm = main.storm
	storm.advance(Storm.CLOSED_SECONDS)
	assert_true(storm.covers(main.exit_cell), "even the very middle")
	var maze_cells := 0
	for y in range(main.MAZE_HEIGHT):
		for x in range(main.MAZE_WIDTH):
			if not MazeGenerator.is_outside(main.grid, Vector2i(x, y)):
				maze_cells += 1
	assert_eq(storm.covered.size(), maze_cells)

func test_its_covered_cells_follow_the_ring():
	var storm: Storm = main.storm
	storm.advance(300.0)
	assert_false(storm.covered.is_empty())
	for y in range(main.MAZE_HEIGHT):
		for x in range(main.MAZE_WIDTH):
			var c := Vector2i(x, y)
			if not MazeGenerator.is_outside(main.grid, c):
				assert_eq(storm.covered.has(c), storm.covers(c), str(c))

func test_everyone_shares_the_one_storm():
	for npc in main.npcs:
		assert_eq(npc.storm, main.storm)
	assert_eq(main.maze_view.storm, main.storm)

func test_it_waits_while_the_game_is_paused():
	get_tree().paused = true
	var before: float = main.storm.elapsed
	await get_tree().create_timer(0.3, true).timeout
	assert_eq(main.storm.elapsed, before)
	get_tree().paused = false

func test_the_hud_counts_it_down():
	var storm: Storm = main.storm
	storm.elapsed = 5.0
	assert_eq(Hud.storm_text(storm), "The storm gathers in 0:25")
	storm.elapsed = 100.0
	assert_eq(Hud.storm_text(storm), "The storm is closing in: 8:20 until it covers everything")
	storm.elapsed = Storm.CLOSED_SECONDS
	assert_eq(Hud.storm_text(storm), "The storm covers everything")

# =========================== Caught in the storm ==========================

func test_out_in_the_storm_hp_drains_away():
	_stand_in_storm(a, corridor(3), Vector2i(0, 0), [Vector2i(0, 0)])
	a.stats.hp = 20
	a._weather_the_storm(3.0)
	assert_eq(a.stats.hp, 20 - int(3.0 * Storm.DAMAGE_PER_SECOND))

func test_it_drains_slowly_frame_by_frame():
	_stand_in_storm(a, corridor(3), Vector2i(0, 0), [Vector2i(0, 0)])
	a.stats.hp = 20
	for i in range(8):
		a._weather_the_storm(0.25)
	assert_eq(a.stats.hp, 18, "two seconds' worth, bit by bit")

func test_inside_the_ring_nothing_happens():
	_stand_in_storm(a, corridor(3), Vector2i(2, 0), [Vector2i(0, 0)])
	a.stats.hp = 20
	a._weather_the_storm(5.0)
	assert_eq(a.stats.hp, 20)
	assert_true(a.stats.can_heal)

func test_nothing_heals_in_the_storm():
	_stand_in_storm(a, corridor(3), Vector2i(0, 0), [Vector2i(0, 0)])
	set_stats(a, 3, 40, 5, 5)
	a.stats.hp = 10
	a.stats.mp = 30
	a._weather_the_storm(0.01)
	assert_false(a.stats.can_heal)
	a._finish_recover_idle()
	assert_eq(a.stats.hp, 10, "not from Recover")
	a.stats.inventory["Health Potion"] = 1
	a._apply_consumable_effect("Health Potion")
	assert_eq(a.stats.hp, 10, "nor a potion")
	var max_before: int = a.stats.max_hp
	a.stats.add_xp(10000)
	assert_gt(a.stats.max_hp, max_before, "a level-up still makes them tougher...")
	assert_eq(a.stats.hp, 10, "...but doesn't refill them")

func test_out_of_the_storm_healing_comes_back():
	_stand_in_storm(a, corridor(3), Vector2i(2, 0), [Vector2i(0, 0)])
	a.stats.can_heal = false
	a._weather_the_storm(0.01)
	assert_true(a.stats.can_heal)
	a.stats.hp = 10
	assert_eq(a.stats.heal(5), 5)

func test_the_storm_can_kill():
	_stand_in_storm(a, corridor(3), Vector2i(0, 0), [Vector2i(0, 0)])
	a.stats.hp = 1
	a._weather_the_storm(1.0)
	assert_true(a.dead)
	assert_eq(a.killed_by, "the storm")

func test_followers_suffer_it_too():
	_stand_in_storm(a, corridor(3), Vector2i(0, 0), [Vector2i(0, 0)])
	PartyOps.join_party_of(b, a)
	b.storm = a.storm
	b.stats.hp = 20
	b._process(2.0)
	assert_eq(b.stats.hp, 18)

# ============================= Keeping out of it ==========================

func test_caught_in_it_they_head_for_the_nearest_way_out():
	_stand_in_storm(a, corridor(6), Vector2i(2, 0), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	a.finished = false
	assert_true(a._escape_the_storm())
	assert_eq(a.current_action, "Escaping the storm")
	assert_true(a.is_moving, "on their way to (3,0)")

func test_the_way_out_is_the_shortest():
	var g := corridor(6)
	var stormy := {Vector2i(0, 0): true, Vector2i(1, 0): true, Vector2i(2, 0): true}
	assert_eq(MazeQuery.step_out_of(g, Vector2i(1, 0), stormy), Vector2i(2, 0))
	assert_eq(MazeQuery.step_out_of(g, Vector2i(4, 0), stormy), Vector2i(4, 0), "already out")

func test_escaping_comes_before_healing():
	_stand_in_storm(a, corridor(6), Vector2i(0, 0), [Vector2i(0, 0), Vector2i(1, 0)])
	set_stats(a, 3, 40, 5, 5)
	a.stats.hp = 5
	a.stats.mp = 30
	a._process(0.01)
	assert_eq(a.current_action, "Escaping the storm", "not stopping to cast Recover")

func test_no_turn_wasted_on_healing_in_the_storm():
	_stand_in_storm(a, corridor(3), Vector2i(0, 0), [Vector2i(0, 0)])
	set_stats(a, 3, 40, 5, 5)
	a.stats.hp = 5
	a.stats.mp = 30
	a._weather_the_storm(0.01)
	assert_false(a._see_to_ourselves(), "no Recover, no potion, no resting")
	var foe := NpcStats.new()
	assert_eq(a.choose_combat_action(foe), CombatRules.ATTACK, "nor mid-fight")

func test_exploring_prefers_ground_out_of_the_storm():
	# Unexplored both ways from (1,0); only (2,0) is out of the storm.
	_stand_in_storm(a, corridor(3), Vector2i(1, 0), [Vector2i(0, 0)])
	for i in range(20):
		assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(a.grid, a.cell_pos)), Vector2i(2, 0))

func test_but_it_will_explore_the_storm_if_thats_all_there_is():
	_stand_in_storm(a, corridor(3), Vector2i(1, 0), [Vector2i(0, 0)], [Vector2i(2, 0)])
	assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(a.grid, a.cell_pos)), Vector2i(0, 0))

func test_routes_steer_round_the_storm():
	# Straight along the top to (2,0) is quicker -- but the storm's on (1,0).
	_stand_in_storm(a, ring_maze(), Vector2i(0, 0), [Vector2i(1, 0)])
	assert_eq(NpcRoutes.step_toward(a, Vector2i(2, 0), 10), Vector2i(0, 1))

func test_through_the_storm_when_theres_no_other_way():
	_stand_in_storm(a, corridor(4), Vector2i(0, 0), [Vector2i(1, 0), Vector2i(2, 0)])
	assert_eq(NpcRoutes.step_toward(a, Vector2i(3, 0), 10), Vector2i(1, 0))

func test_guidance_steers_round_the_storm_too():
	_stand_in_storm(a, ring_maze(), Vector2i(0, 0), [Vector2i(1, 0)])
	a.guidance_target = Vector2i(2, 0)
	assert_eq(a._guidance_step(), Vector2i(0, 1))

func test_chests_in_the_storm_arent_worth_it():
	_stand_in_storm(a, corridor(3), Vector2i(2, 0), [Vector2i(0, 0)])
	a.chests = {Vector2i(0, 0): true, Vector2i(1, 0): true}
	assert_eq(a._chests_worth_trying().keys(), [Vector2i(1, 0)])

func test_backing_off_backs_out_of_the_storm():
	_stand_in_storm(a, corridor(3), Vector2i(1, 0), [Vector2i(0, 0)], [Vector2i(0, 0), Vector2i(2, 0)])
	for i in range(20):
		assert_eq(NpcRoutes.retreat_cell(a), Vector2i(2, 0))

func test_but_into_it_if_theres_nowhere_else():
	_stand_in_storm(a, corridor(2), Vector2i(1, 0), [Vector2i(0, 0)], [Vector2i(0, 0)])
	assert_eq(NpcRoutes.retreat_cell(a), Vector2i(0, 0))
