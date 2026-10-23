extends DungeonTest

## Covers the storm (Storm): gathering for its first 30 seconds, then
## closing in to cover the whole maze at 600; what it does to anyone caught
## in it (HP drains away, none comes back); and how everyone's AI keeps out
## of it where it can, and gets out of it when caught.

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
	npc.storm = StormOver.new(stormy)

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
	a.stats.cast_recover()
	assert_eq(a.stats.hp, 10, "not from Recover")
	a.stats.inventory["Health Potion"] = 1
	a.stats.use_item("Health Potion")
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
	assert_eq(a.current_action, NpcAgent.ESCAPING)
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
	assert_eq(a.current_action, NpcAgent.ESCAPING, "not stopping to cast Recover")

func test_no_turn_wasted_on_healing_in_the_storm():
	_stand_in_storm(a, corridor(3), Vector2i(0, 0), [Vector2i(0, 0)])
	set_stats(a, 3, 40, 5, 5)
	a.stats.hp = 5
	a.stats.mp = 30
	a._weather_the_storm(0.01)
	assert_false(a._see_to_ourselves(), "no Recover, no potion, no resting")
	var foe := NpcStats.new()
	assert_eq(CombatActions.choose(a.stats, foe), CombatRules.ATTACK, "nor mid-fight")

func test_exploring_prefers_ground_out_of_the_storm():
	# Unexplored both ways from (1,0); only (2,0) is out of the storm.
	_stand_in_storm(a, corridor(3), Vector2i(1, 0), [Vector2i(0, 0)])
	for i in range(20):
		assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(a.grid, a.cell_pos)), Vector2i(2, 0))

func test_with_nothing_left_to_explore_on_safe_ground_they_stay_on_it():
	# The only unexplored cell is in the storm: going there would only mean
	# turning straight round and getting out again.
	_stand_in_storm(a, corridor(3), Vector2i(1, 0), [Vector2i(0, 0)], [Vector2i(2, 0)])
	for i in range(20):
		assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(a.grid, a.cell_pos)), Vector2i(2, 0))

func test_but_already_in_it_they_explore_it():
	_stand_in_storm(a, corridor(3), Vector2i(1, 0), [Vector2i(0, 0), Vector2i(1, 0)], [Vector2i(2, 0)])
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

func test_a_chest_the_storm_reaches_is_given_up():
	# Spotted while it was still dry -- then the storm got to it. Holding on
	# to it walked them up to the storm's edge, off exploring, and back again.
	_stand_in_storm(a, corridor(5), Vector2i(1, 0), [Vector2i(3, 0), Vector2i(4, 0)])
	a.chests = {Vector2i(4, 0): true}
	a.chest_goal = Vector2i(4, 0)
	assert_eq(a._chest_step(), a.cell_pos)
	assert_eq(a.chest_goal, MazeQuery.NONE)

func test_a_chest_only_reached_through_the_storm_is_set_aside():
	_stand_in_storm(a, corridor(5), Vector2i(2, 0), [Vector2i(3, 0)])
	a.chests = {Vector2i(4, 0): true}
	assert_eq(a._chest_step(), a.cell_pos, "not into the storm for it")
	assert_true(a.skipped_chests.has(Vector2i(4, 0)), "nor straight back the next step")

func test_nobody_heads_over_to_a_party_in_the_storm():
	var g := corridor(4)
	_stand_in_storm(a, g, Vector2i(0, 0), [])
	isolate(b, g, Vector2i(3, 0), players)
	for npc in [a, b]:
		npc.stats.alignment = NpcStats.ALIGNMENT_GOOD
		set_stats(npc, 3, 40, 5, 5)
	assert_ne(a._party_up_step(), a.cell_pos, "sanity: they'd team up")
	a.storm = StormOver.new([Vector2i(3, 0)])
	assert_eq(a._party_up_step(), a.cell_pos, "but not out there")

func test_backing_off_backs_out_of_the_storm():
	_stand_in_storm(a, corridor(3), Vector2i(1, 0), [Vector2i(0, 0)], [Vector2i(0, 0), Vector2i(2, 0)])
	for i in range(20):
		assert_eq(NpcRoutes.retreat_cell(a), Vector2i(2, 0))

func test_but_into_it_if_theres_nowhere_else():
	_stand_in_storm(a, corridor(2), Vector2i(1, 0), [Vector2i(0, 0)], [Vector2i(0, 0)])
	assert_eq(NpcRoutes.retreat_cell(a), Vector2i(0, 0))

# ========================= Cut off from the middle ========================

## A maze with a pocket: along the top from the middle, (0,0), out to (4,0),
## then back along the bottom from (4,1) to (1,1) -- a dead end lying close
## to the middle that only joins it the long way round.
func _hairpin() -> Array:
	var g := walled_grid(5, 2)
	for x in range(4):
		open_between(g, Vector2i(x, 0), Vector2i(x + 1, 0))
	for x in range(1, 4):
		open_between(g, Vector2i(x, 1), Vector2i(x + 1, 1))
	open_between(g, Vector2i(4, 0), Vector2i(4, 1))
	return g

## The storm on _hairpin, closed in to 3.5 cells round the middle: it covers
## the far end, (4,0) and (4,1) -- and so cuts the bottom row off.
func _hairpin_storm(g: Array) -> Storm:
	var storm := Storm.new(null, g)
	storm.center = Vector2(0.5, 0.5)
	storm.start_radius = 7.0
	storm.advance((Storm.START_SECONDS + Storm.CLOSED_SECONDS) / 2.0)
	return storm

func test_dry_ground_the_storm_cuts_off_from_the_middle_isnt_safe():
	var storm := _hairpin_storm(_hairpin())
	for c in [Vector2i(4, 0), Vector2i(4, 1)]:
		assert_true(storm.covers(c), "sanity: %s is in the storm" % c)
	for c in cells_along(1, 3, 1):
		assert_false(storm.covers(c), "sanity: %s is dry" % c)
		assert_false(storm.is_safe(c), "but cut off: %s" % c)
	for c in cells_along(0, 3, 0):
		assert_true(storm.is_safe(c), str(c))

func test_on_the_real_map_safe_ground_is_all_joined_to_the_middle():
	var storm: Storm = main.storm
	storm.advance(300.0)
	var joined := {main.exit_cell: true}
	var frontier: Array = [main.exit_cell]
	while not frontier.is_empty():
		for n in MazeQuery.open_neighbors(main.grid, frontier.pop_back()):
			if not joined.has(n) and storm.is_safe(n):
				joined[n] = true
				frontier.append(n)
	var safe := 0
	for y in range(main.MAZE_HEIGHT):
		for x in range(main.MAZE_WIDTH):
			var c := Vector2i(x, y)
			if MazeGenerator.is_outside(main.grid, c):
				continue
			if storm.covers(c):
				assert_false(storm.is_safe(c), "%s is in the storm" % c)
			if storm.is_safe(c):
				safe += 1
				assert_true(joined.has(c), "%s is joined to the middle by safe ground" % c)
	assert_gt(safe, 0, "sanity: there's still some")

func test_it_steers_clear_of_where_the_ring_is_about_to_be():
	# Worked out only every RECOUNT_STEP the ring shrinks, so it looks that
	# far ahead -- or the ring could creep onto a cell still counted safe.
	var g := _hairpin()
	var storm := Storm.new(null, g)
	storm.center = Vector2(0.5, 0.5)
	storm.start_radius = 7.0
	var r := 3.1  # (3,0)'s middle is 3.0 from the maze's
	storm.advance(Storm.CLOSED_SECONDS - r / storm.start_radius * (Storm.CLOSED_SECONDS - Storm.START_SECONDS))
	assert_false(storm.covers(Vector2i(3, 0)), "sanity: not in the storm yet")
	assert_false(storm.is_safe(Vector2i(3, 0)), "but about to be")
	assert_true(storm.is_safe(Vector2i(2, 0)))

func test_caught_in_it_they_make_for_the_middle_not_the_nearest_dry_cell():
	var g := _hairpin()
	isolate(a, g, Vector2i(4, 1), players)
	a.storm = _hairpin_storm(g)
	assert_eq(NpcRoutes.out_of_storm(a), Vector2i(4, 0), "not back into the pocket at (3,1)")

func test_out_of_a_pocket_they_never_turn_back():
	# The reported loop: out of the pocket into the storm, straight back to
	# the pocket (the nearest dry cell), out again... until the storm had it.
	var g := _hairpin()
	isolate(a, g, Vector2i(1, 1), players)
	a.storm = _hairpin_storm(g)
	var path: Array = []
	while not a.storm.is_safe(a.cell_pos) and path.size() < 10:
		var step := NpcRoutes.out_of_storm(a)
		assert_false(path.has(step) or step == a.cell_pos, "no going back (at %s, to %s)" % [a.cell_pos, step])
		path.append(step)
		a.cell_pos = step
	assert_eq(path, [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(4, 0), Vector2i(3, 0)])

func test_and_they_actually_walk_out_through_the_storm():
	fast_forward()
	var g := _hairpin()
	isolate(a, g, Vector2i(1, 1), players)
	a.storm = _hairpin_storm(g)
	set_stats(a, 5, 500, 5, 5)
	var seen: Array = [a.cell_pos]
	for i in range(80):  # polled in real time: steps are timed in seconds
		await wait_seconds(0.1)
		if seen.back() != a.cell_pos:
			seen.append(a.cell_pos)
		if a.storm.is_safe(a.cell_pos):
			break
	assert_true(a.storm.is_safe(a.cell_pos), "made it to the middle's side (went %s)" % [seen])
	assert_eq(seen.count(Vector2i(1, 1)) + seen.count(Vector2i(2, 1)) + seen.count(Vector2i(3, 1)), 3,
		"through the pocket once, never back (went %s)" % [seen])

func test_safe_ground_isnt_left_for_anything_but_safety():
	_stand_in_storm(a, corridor(4), Vector2i(2, 0), [Vector2i(1, 0)])
	assert_true(NpcRoutes.leaves_safe_ground(a, Vector2i(1, 0)), "a chest, a shop, a party there: not worth it")
	assert_false(NpcRoutes.leaves_safe_ground(a, Vector2i(3, 0)))
	a.cell_pos = Vector2i(1, 0)
	assert_false(NpcRoutes.leaves_safe_ground(a, Vector2i(0, 0)), "already in it, it's no worse")

func test_chests_in_a_cut_off_pocket_arent_worth_it():
	isolate(a, corridor(4), Vector2i(2, 0), players)
	a.storm = StormOver.new([Vector2i(0, 0)], [Vector2i(1, 0)])
	a.chests = {Vector2i(1, 0): true, Vector2i(3, 0): true}
	assert_eq(a._chests_worth_trying().keys(), [Vector2i(3, 0)])

func test_guidance_can_still_send_them_through_the_storm():
	_stand_in_storm(a, corridor(4), Vector2i(1, 0), [Vector2i(1, 0)])
	a.guidance_target = Vector2i(0, 0)
	assert_false(a._escape_the_storm(), "the spectator's order comes first")
