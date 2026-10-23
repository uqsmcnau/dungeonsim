extends DungeonTest

## Covers characters getting stuck dithering back and forth -- loops the
## soak test's pacing check caught (see tools/soak.gd): a hurt character
## harried by monsters it can't get away from; one exploring towards a cell
## where someone else is mid-fight, or a monster too strong for it; and one
## heading to team up with a party that a wall hides for a step.

var a: NpcAgent
var b: NpcAgent
var players: Dictionary = {}

func before_each():
	load_main()
	a = main.npcs[0]
	b = main.npcs[1]

## A monster far too strong for `a` to want to fight, on `a`'s cell.
func _monster_on_a() -> EnemyAgent:
	var monster := new_enemy()
	monster.setup(a.cell_pos, main.CELL_SIZE, 10, a.grid, a.enemies, {}, [], false)
	return monster

# ============================== Harried ===================================

func test_a_monster_it_cant_beat_is_backed_away_from():
	isolate(a, corridor(3), Vector2i(1, 0), players, [Vector2i(0, 0), Vector2i(2, 0)])
	set_stats(a, 1, 5, 1, 1)
	_monster_on_a()
	a._settle_enemy_on_our_cell()
	assert_false(a.in_pack_combat, "sanity: it backs off")
	assert_true(a.is_moving)

func test_but_backed_off_again_and_again_it_stands_and_fights():
	# Two monsters chasing it up and down a corridor: back off from one,
	# rest, back off again... while it never got a step of its own.
	isolate(a, corridor(3), Vector2i(1, 0), players, [Vector2i(0, 0), Vector2i(2, 0)])
	set_stats(a, 1, 5, 1, 1)
	_monster_on_a()
	a._backed_off = NpcAgent.CORNERED_AFTER
	a._settle_enemy_on_our_cell()
	assert_true(a.cornered)
	assert_true(a.in_pack_combat, "fighting it out -- not fleeing, which would only be backing off again")

func test_a_step_of_its_own_and_its_not_cornered():
	isolate(a, corridor(3), Vector2i(1, 0), players, [Vector2i(0, 0), Vector2i(2, 0)])
	a._backed_off = NpcAgent.CORNERED_AFTER
	a.cornered = true
	a._take_step()
	assert_eq(a._backed_off, 0)
	assert_false(a.cornered)

# ========================= Someone else's fight ===========================

func _fighting_on(npc: NpcAgent, g: Array, cell: Vector2i) -> void:
	isolate(npc, g, cell, players)
	npc.in_pack_combat = true
	npc.is_moving = true

func test_exploring_leaves_someone_elses_fight_alone():
	var g := corridor(3)
	isolate(a, g, Vector2i(1, 0), players)
	_fighting_on(b, g, Vector2i(2, 0))
	for i in range(20):
		assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(g, a.cell_pos)), Vector2i(0, 0),
			"the other way, not up to their fight and back")

func test_unless_theres_nowhere_else():
	var g := corridor(2)
	isolate(a, g, Vector2i(0, 0), players)
	_fighting_on(b, g, Vector2i(1, 0))
	assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(g, a.cell_pos)), Vector2i(1, 0))

func test_a_party_mates_fight_isnt_someone_elses():
	var g := corridor(3)
	isolate(a, g, Vector2i(1, 0), players)
	_fighting_on(b, g, Vector2i(2, 0))
	a.party = [a, b]
	assert_false(NpcRoutes.leave_alone(a).has(Vector2i(2, 0)))

# ========================== A monster too strong ==========================

func test_a_monster_it_backed_away_from_is_left_alone_while_exploring():
	# The last unexplored cell about, held by a mid boss: up to it, back off,
	# up to it again...
	var g := corridor(3)
	isolate(a, g, Vector2i(1, 0), players, [Vector2i(0, 0)])
	set_stats(a, 1, 20, 1, 1)
	var monster := new_enemy()
	monster.setup(Vector2i(2, 0), main.CELL_SIZE, 11, g, a.enemies, {}, [], false)
	a._attempt_move(Vector2i(2, 0))
	assert_true(a.daunted.has(Vector2i(2, 0)), "sanity: it backed off")
	a.is_moving = false
	a.cell_pos = Vector2i(1, 0)
	for i in range(20):
		assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(g, a.cell_pos)), Vector2i(0, 0))

func test_but_only_for_a_while():
	isolate(a, corridor(3), Vector2i(1, 0), players)
	a.daunted = {Vector2i(2, 0): 2}
	a._take_step()
	a.is_moving = false
	a._take_step()
	assert_false(a.daunted.has(Vector2i(2, 0)), "worth another look after DAUNTED_STEPS steps")

# ======================== A party out of sight ============================

## An L-shaped passage: (0,0) east to (1,0), down to (1,2), back west to
## (0,2) -- whose end can't be seen from the start, through the wall
## between (0,0) and (0,1).
func _round_a_corner() -> Array:
	var g := walled_grid(2, 3)
	open_between(g, Vector2i(0, 0), Vector2i(1, 0))
	open_between(g, Vector2i(1, 0), Vector2i(1, 1))
	open_between(g, Vector2i(1, 1), Vector2i(1, 2))
	open_between(g, Vector2i(1, 2), Vector2i(0, 2))
	return g

func test_a_party_its_heading_for_isnt_dropped_the_moment_a_wall_hides_them():
	# Dropping them out of sight had it step towards them, lose sight, turn
	# back to something else, see them again...
	var g := _round_a_corner()
	isolate(a, g, Vector2i(0, 0), players)
	isolate(b, g, Vector2i(0, 2), players)
	for npc in [a, b]:
		npc.stats.alignment = NpcStats.ALIGNMENT_GOOD
		set_stats(npc, 3, 40, 5, 5)
	assert_eq(a._party_up_step(), a.cell_pos, "sanity: out of sight, so not spotted")
	a.party_goal = b
	assert_eq(a._party_up_step(), Vector2i(1, 0), "but once set off for, still headed for")

func test_but_dropped_when_theyre_no_longer_worth_joining():
	var g := _round_a_corner()
	isolate(a, g, Vector2i(0, 0), players)
	isolate(b, g, Vector2i(0, 2), players)
	a.stats.alignment = NpcStats.ALIGNMENT_GOOD
	b.stats.alignment = NpcStats.ALIGNMENT_EVIL
	a.party_goal = b
	assert_eq(a._party_up_step(), a.cell_pos)
	assert_null(a.party_goal)

func test_on_safe_ground_with_only_the_storm_or_a_fight_about_it_waits():
	# The only safe way on is someone else's fight; the other way's the
	# storm. Into the storm and straight back out, over and over, was worse.
	var g := corridor(3)
	isolate(a, g, Vector2i(1, 0), players, [Vector2i(0, 0), Vector2i(2, 0)])
	_fighting_on(b, g, Vector2i(2, 0))
	a.storm = StormOver.new([Vector2i(0, 0)])
	assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(g, a.cell_pos)), a.cell_pos)

func test_on_safe_ground_with_only_a_fight_ahead_it_waits():
	# A dead end, the only way on someone else's fight: up to it, unable to
	# get past or back off, over and over, every frame.
	var g := corridor(2)
	isolate(a, g, Vector2i(0, 0), players, [Vector2i(1, 0)])
	_fighting_on(b, g, Vector2i(1, 0))
	assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(g, a.cell_pos)), a.cell_pos)

# ========================== Nowhere to run ================================

func test_losing_a_fight_with_nowhere_to_run_it_fights_on():
	# Fleeing on the spot only ended the fight for the other side to start it
	# again, every frame, nobody ever moving.
	var g := corridor(2)
	isolate(a, g, Vector2i(0, 0), players)
	isolate(b, g, Vector2i(1, 0), players)  # a dead end, a in the only way out
	set_stats(a, 5, 60, 10, 10)
	set_stats(b, 1, 1, 1, 1)
	assert_false(GroupCombat._should_flee(b, a.stats))

func test_but_with_somewhere_to_go_it_flees():
	var g := corridor(3)
	isolate(a, g, Vector2i(0, 0), players)
	isolate(b, g, Vector2i(1, 0), players, [Vector2i(2, 0)])
	set_stats(a, 5, 60, 10, 10)
	set_stats(b, 1, 1, 1, 1)
	assert_true(GroupCombat._should_flee(b, a.stats))
