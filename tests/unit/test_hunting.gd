extends DungeonTest

## Covers parties going after the strongest monster they're sure they can
## beat (see Hunting, CombatMath.group_win_chance): any in
## sight, and the bosses -- the boss on the exit and the mid bosses, none of
## whom ever leave their rooms -- wherever they've seen one.

var a: NpcAgent
var b: NpcAgent
var players: Dictionary = {}

func before_each():
	load_main()
	a = main.npcs[0]
	b = main.npcs[1]

## A at the start of a corridor eight cells long, all of it seen -- in sight
## up to (6, 0) -- with `hp` HP and otherwise middling stats, as every
## monster here has (see _monster): so HP alone sets the odds.
func _hunter(hp: int) -> void:
	isolate(a, corridor(8), Vector2i(0, 0), players)
	set_stats(a, 5, hp, 10, 10)
	for c in cells_along(0, 7):
		a.seen_cells[c] = true
	a.look_around()

## B joins A's party, with `hp` HP.
func _with_party_mate(hp: int) -> void:
	isolate(b, a.grid, a.cell_pos, {})
	set_stats(b, 5, hp, 10, 10)
	add_to_party(a, [b])

## A monster of `level` (worth more XP the higher it is) on `cell`, staying
## put, with `hp` HP.
func _monster(cell: Vector2i, hp: int, level: int = 5) -> EnemyAgent:
	var monster := new_enemy()
	monster.setup(cell, main.CELL_SIZE, level, a.grid, a.enemies, {}, [], false)
	monster.stats.strength = 10
	monster.stats.constitution = 10
	monster.stats.dexterity = 10
	monster.stats.hp = hp
	monster.stats.max_hp = hp
	return monster

## A mid boss of `hp` HP holding `cell`, with a guard for each of `guards`
## (their HP). Returns the mid boss.
func _mid_boss(cell: Vector2i, hp: int, guards: Array = [], level: int = 6) -> EnemyAgent:
	var boss := _monster(cell, hp, level)
	boss.is_mid_boss = true
	var members: Array = [boss]
	for guard_hp in guards:
		var guard := _monster(cell, guard_hp, 3)
		guard.guarding = boss.kind.called()
		members.append(guard)
	EnemyAgent.form_pack(members)
	return boss

func _odds(us: Array, enemy: EnemyAgent) -> float:
	return CombatMath.group_win_chance(us.map(func(m): return m.stats), enemy.living_pack().map(func(m): return m.stats))

## Which monster A would set off after now, if it weren't after one already.
func _pick() -> EnemyAgent:
	return Hunting.strongest(a, NpcRoutes.leave_alone(a), NpcRoutes.storm_cells(a))

# =============================== The odds ==================================

func test_one_against_one_its_the_usual_odds():
	_hunter(30)
	var monster := _monster(Vector2i(4, 0), 50)
	assert_almost_eq(CombatMath.group_win_chance([a.stats], [monster.stats]),
		CombatMath.win_chance_against(a.stats, monster.stats), 0.0001)

func test_more_on_a_side_better_its_odds():
	_hunter(30)
	_with_party_mate(30)
	var boss := _mid_boss(Vector2i(4, 0), 30)
	assert_gt(_odds([a, b], boss), _odds([a], boss))
	var guarded := _mid_boss(Vector2i(6, 0), 30, [30])
	assert_lt(_odds([a], guarded), _odds([a], boss))

# ========================== Which to go after ==============================

func test_it_goes_after_a_monster_in_sight_it_can_beat():
	_hunter(60)
	var monster := _monster(Vector2i(4, 0), 20)
	assert_eq(Hunting.step(a), Vector2i(1, 0))
	assert_eq(a.hunt_target, monster)
	a._take_step()
	assert_eq(a.current_action, "Off to fight %s" % monster.kind.called())

func test_not_one_out_of_sight():
	_hunter(60)
	_monster(Vector2i(7, 0), 20)
	assert_eq(Hunting.step(a), a.cell_pos, "it's seen where it was -- but it wanders")

func test_nor_one_too_strong_for_it():
	_hunter(20)
	_monster(Vector2i(4, 0), 60)
	assert_eq(Hunting.step(a), a.cell_pos, "exploring on, to level up first")

func test_the_strongest_it_can_beat_first():
	_hunter(60)
	_monster(Vector2i(2, 0), 20, 3)
	var stronger := _monster(Vector2i(5, 0), 20, 7)
	assert_eq(_pick(), stronger)

func test_of_two_alike_the_nearest():
	_hunter(60)
	_monster(Vector2i(5, 0), 20)
	var nearer := _monster(Vector2i(2, 0), 20)
	assert_eq(_pick(), nearer)

func test_it_counts_the_whole_pack():
	_hunter(60)
	var boss := _mid_boss(Vector2i(5, 0), 20, [20, 20])
	assert_gt(CombatMath.win_chance_against(a.stats, boss.stats), Hunting.CONFIDENCE,
		"sanity: the mid boss alone it could take")
	assert_eq(Hunting.step(a), a.cell_pos, "but not all three")

func test_and_its_own_party():
	_hunter(20)
	_with_party_mate(40)
	var monster := _monster(Vector2i(5, 0), 40)
	assert_lt(CombatMath.win_chance_against(a.stats, monster.stats), Hunting.CONFIDENCE,
		"sanity: alone it couldn't")
	assert_eq(Hunting.step(a), Vector2i(1, 0), "but with B it can")

func test_not_straight_back_after_backing_off_from_one():
	_hunter(60)
	_monster(Vector2i(4, 0), 20)
	a.daunted[Vector2i(4, 0)] = NpcAgent.DAUNTED_STEPS
	assert_eq(Hunting.step(a), a.cell_pos)

# ============================== The bosses =================================

func test_a_boss_room_its_seen_is_remembered():
	# Out of sight now, but bosses never leave their rooms.
	_hunter(60)
	var boss := _mid_boss(Vector2i(7, 0), 20)
	assert_false(a.sight_cells.has(boss.cell_pos), "sanity: out of sight")
	assert_eq(Hunting.step(a), Vector2i(1, 0))
	assert_eq(a.hunt_target, boss)
	assert_string_ends_with(a.current_action, boss.kind.called(true))

func test_but_not_one_it_hasnt_seen():
	_hunter(60)
	_mid_boss(Vector2i(7, 0), 20)
	a.seen_cells.erase(Vector2i(7, 0))
	assert_eq(Hunting.step(a), a.cell_pos)

func test_guards_still_holding_the_room_after_their_boss_fell_count_too():
	_hunter(60)
	var boss := _mid_boss(Vector2i(7, 0), 20, [20])
	boss.defeat()
	assert_true(a.has_live_enemy(Vector2i(7, 0)), "sanity: the guard holds the room")
	assert_eq(Hunting.step(a), Vector2i(1, 0))

func test_the_boss_on_the_exit_before_any_other():
	_hunter(60)
	_mid_boss(Vector2i(3, 0), 20)
	a.exit_cell = Vector2i(6, 0)
	var boss := _monster(a.exit_cell, 20, 12)
	boss.is_boss = true
	assert_eq(_pick(), boss, "the strongest -- and beating it wins the race")

# ============================= Getting there ===============================

func test_it_keeps_after_one_a_wall_hides_for_a_moment():
	_hunter(60)
	var monster := _monster(Vector2i(4, 0), 20)
	Hunting.step(a)
	a.sight_cells = {}  # behind a wall, say
	assert_eq(Hunting.step(a), Vector2i(1, 0))
	assert_eq(a.hunt_target, monster)

func test_but_not_once_its_got_far_away():
	_hunter(60)
	var monster := _monster(Vector2i(4, 0), 20)
	Hunting.step(a)
	a.sight_cells = {}
	a.cell_pos = Vector2i(0, 0)
	monster.cell_pos = Vector2i(NpcAgent.SIGHT_RANGE * 2 + 1, 0)
	assert_false(Hunting.worth_hunting(a, monster, {}, {}, true))

func test_meeting_it_it_fights_rather_than_rolling_for_it():
	# A alone would most likely back off (decide_fight rolls on A's own
	# odds); it set out knowing its party could win.
	_hunter(12)
	_with_party_mate(100)
	a.cell_pos = Vector2i(4, 0)
	b.cell_pos = a.cell_pos
	a.look_around()
	var monster := _monster(Vector2i(5, 0), 60)
	assert_lt(CombatMath.win_chance_against(a.stats, monster.stats), 0.25, "sanity: A alone would likely back off")
	a._take_step()
	assert_true(a.in_pack_combat, "fighting it")
	assert_true(monster.in_combat)

func test_never_through_the_storm_to_get_there():
	# The short way's in the storm, the long way past another monster: past
	# the monster it goes, rather than into the storm -- only to turn back
	# to escape it, and in again.
	isolate(a, ring_maze(), Vector2i(0, 0), players)
	set_stats(a, 5, 60, 10, 10)
	for y in range(2):
		for c in cells_along(0, 2, y):
			a.seen_cells[c] = true
	var boss := _mid_boss(Vector2i(2, 0), 20, [], 9)
	_monster(Vector2i(0, 1), 200, 1)  # in the way, and not worth going after
	a.storm = StormOver.new([Vector2i(1, 0)])
	assert_eq(Hunting.step(a), Vector2i(0, 1))
	assert_eq(a.hunt_target, boss)
