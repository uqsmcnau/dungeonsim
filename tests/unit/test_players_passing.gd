extends DungeonTest

## Covers two players who won't fight each other and can't team up meeting
## in a corridor -- e.g. right after a fight one of them fled. They used to
## back off from each other forever (each refusing the other, retreating,
## then coming straight back), or freeze outright once one had nowhere to
## back off to. Now they squeeze past each other instead.

var a: NpcAgent
var b: NpcAgent
var players: Dictionary = {}

func before_each():
	load_main()
	a = main.npcs[0]
	b = main.npcs[1]

func _row(from_x: int, to_x: int) -> Array:
	var cells: Array = []
	for x in range(from_x, to_x + 1):
		cells.append(Vector2i(x, 0))
	return cells

## A (Evil, too weak to pick a fight) and B (Neutral, never starts one) face
## each other in the middle of a corridor, each having explored its own end
## -- so each one's way on is past the other.
func _standoff(length: int = 6) -> void:
	var g := corridor(length)
	var mid := length / 2
	isolate(a, g, Vector2i(mid - 1, 0), players, _row(0, mid - 1))
	isolate(b, g, Vector2i(mid, 0), players, _row(mid, length - 1))
	a.stats.alignment = NpcStats.ALIGNMENT_EVIL
	b.stats.alignment = NpcStats.ALIGNMENT_NEUTRAL
	set_stats(a, 1, 10, 1, 1)
	set_stats(b, 5, 60, 10, 10)
	assert_false(a._decide_pvp_fight(b), "sanity: A won't start a fight")
	assert_false(b._decide_pvp_fight(a), "sanity: B won't either")
	assert_false(PartyOps.can_form_party_with(a, b), "sanity: and they can't team up")

## Lets the two play out in real time (moves are timed in seconds).
func _run_until(done: Callable, seconds: float) -> bool:
	var waited := 0.0
	while waited < seconds:
		if done.call():
			return true
		await wait_seconds(0.1)
		waited += 0.1
	return done.call()

func test_players_who_wont_fight_squeeze_past_each_other():
	_standoff()
	var a_end := Vector2i(5, 0)
	var b_end := Vector2i(0, 0)
	var passed: bool = await _run_until(func(): return a.visited.has(a_end) and b.visited.has(b_end), 8.0)
	assert_true(passed, "each should reach the far end it was heading for (A at %s, B at %s)" % [a.cell_pos, b.cell_pos])

func test_passing_works_in_a_safe_room_too():
	# No fights at all in a safe room -- so Good and Evil can't settle it
	# that way either.
	_standoff()
	a.stats.alignment = NpcStats.ALIGNMENT_GOOD
	b.stats.alignment = NpcStats.ALIGNMENT_EVIL
	set_stats(a, 5, 60, 10, 10)
	set_stats(b, 5, 60, 10, 10)
	for c in _row(0, 5):
		a.safe_cells[c] = true
		b.safe_cells[c] = true
	var passed: bool = await _run_until(func(): return a.visited.has(Vector2i(5, 0)) and b.visited.has(Vector2i(0, 0)), 8.0)
	assert_true(passed)
	assert_false(a.in_pvp_combat or b.in_pvp_combat, "and no fight broke out")

func test_both_are_on_the_map_again_once_past():
	_standoff()
	await _run_until(func(): return a.visited.has(Vector2i(5, 0)) and b.visited.has(Vector2i(0, 0)), 8.0)
	await _run_until(func(): return not a.is_moving and not b.is_moving, 2.0)
	a._process(0.0)
	b._process(0.0)
	assert_eq(players.get(a.cell_pos), a, "A registered where it stands")
	assert_eq(players.get(b.cell_pos), b, "B registered where it stands")

func test_a_leader_whose_registration_was_lost_reclaims_it():
	# Sharing a cell for a moment (one passing the other) can leave the
	# one standing still without a map entry -- it takes it back.
	_standoff()
	players.erase(a.cell_pos)
	a._process(0.0)
	assert_eq(players.get(a.cell_pos), a)

func test_nobody_squeezes_into_a_fight_in_progress():
	_standoff()
	b.in_pack_combat = true  # B is busy fighting something
	b.is_moving = true
	a._attempt_move(b.cell_pos)
	assert_ne(a.cell_pos, b.cell_pos)
	await wait_seconds(1.0)
	assert_ne(a.cell_pos, b.cell_pos, "backed off rather than wading into someone else's fight")
