extends DungeonTest

## Covers a character's icon and its cell_pos agreeing about where it is.
## The fog of war is lit from cell_pos (see NpcAgent.look_around), so when
## the two came apart the walls stayed lit around a spot the character's
## icon had long since left. Two ways that happened: two moves under way at
## once (one pulling the icon while the other's arrival set cell_pos), and a
## fight's winner "claiming" a loser's cell that was no longer next door.

var a: NpcAgent
var b: NpcAgent
var players: Dictionary = {}

func before_each():
	load_main()
	a = main.npcs[0]
	b = main.npcs[1]

## Stands `npc` alone on `cell` of `g`, holding still between the moves a
## test makes itself (a finished character's _process does nothing).
func _stand(npc: NpcAgent, g: Array, cell: Vector2i) -> void:
	isolate(npc, g, cell, players)
	npc.finished = true

func _assert_at(npc: NpcAgent, cell: Vector2i) -> void:
	assert_eq(npc.cell_pos, cell, "%s's cell" % npc.npc_name)
	var offset: Vector2 = Vector2.ZERO if npc.is_party_leader else npc.party_offset
	assert_almost_eq(npc.position, npc._cell_to_world(cell) + offset, Vector2.ONE * 0.5, "%s's icon is on its cell" % npc.npc_name)

## A 2x2 maze open along the top and down the right: (0,0) and (1,1) are
## diagonal neighbours with walls between them -- the way round is through
## (1,0).
func _corner() -> Array:
	var g := walled_grid(2, 2)
	open_between(g, Vector2i(0, 0), Vector2i(1, 0))
	open_between(g, Vector2i(1, 0), Vector2i(1, 1))
	return g

# ================================ Moving ==================================

func test_a_new_move_replaces_one_still_under_way():
	_stand(a, corridor(4), Vector2i(1, 0))
	a.stats.dexterity = 1  # a slow step...
	a.move_to(Vector2i(2, 0))
	await wait_seconds(0.05)
	a.stats.dexterity = 40  # ...overtaken by a quick one back the other way
	a.move_to(Vector2i(0, 0))
	await wait_seconds(1.0)
	_assert_at(a, Vector2i(0, 0))

func test_a_player_fleeing_gets_away_even_if_attacked_again_mid_step():
	# Still registered on the cell it's fleeing from until it arrives, so
	# an attacker sharing that cell attacks it again -- every frame. Each
	# time it flees afresh, choosing a way out at random; that used to
	# restart its escape, now this way, now that, so it never got anywhere.
	var g := corridor(5)
	isolate(a, g, Vector2i(2, 0), players, [Vector2i(1, 0), Vector2i(3, 0)])
	a.finished = true
	_stand(b, g, Vector2i(2, 0))
	players[Vector2i(2, 0)] = a
	set_stats(a, 1, 3, 1, 1)
	set_stats(b, 3, 40, 8, 8)
	# Two seconds of being set on every frame: time for a few steps.
	for i in range(120):
		if a.cell_pos != Vector2i(2, 0):
			break
		if not a.in_pvp_combat:
			GroupCombat.engage_players(b, Vector2i(2, 0), a)
		await wait_process_frames(1)
	assert_false(a.in_pvp_combat, "sanity: it fled rather than fighting on")
	assert_ne(a.cell_pos, Vector2i(2, 0), "got away while still being attacked")
	await wait_seconds(0.5)
	_assert_at(a, a.cell_pos)

func test_a_leader_killed_mid_step_stays_off_the_map():
	_stand(a, corridor(4), Vector2i(1, 0))
	a.move_to(Vector2i(2, 0))
	a.die()
	await wait_seconds(1.0)
	assert_false(players.values().has(a), "the step finishing doesn't put them back on the map")

# ============================ Joining a party =============================

func test_a_joiner_takes_the_partys_cell_at_once():
	var g := corridor(4)
	_stand(a, g, Vector2i(1, 0))
	_stand(b, g, Vector2i(2, 0))
	PartyOps.join_party_of(b, a)
	assert_eq(b.cell_pos, a.cell_pos, "on the party's cell straight away -- only the icon still has to walk over")
	await wait_seconds(1.0)
	_assert_at(b, Vector2i(1, 0))

func test_a_joiner_caught_mid_step_ends_up_with_its_party():
	var g := corridor(5)
	_stand(a, g, Vector2i(1, 0))
	_stand(b, g, Vector2i(3, 0))
	b.move_to(Vector2i(4, 0))
	await wait_seconds(0.05)
	PartyOps.join_party_of(b, a)
	await wait_seconds(1.0)
	_assert_at(b, Vector2i(1, 0))
	assert_false(players.values().has(b), "only the party's leader is on the map")
	assert_false(b.is_moving, "and free to lead, should it ever have to")

# ============================ After a fight ===============================

func test_a_fight_winner_claims_the_losers_cell_next_door():
	var g := corridor(4)
	_stand(a, g, Vector2i(1, 0))
	_stand(b, g, Vector2i(2, 0))
	b.die()
	GroupCombat.conclude_pvp(a.party, b.party, Vector2i(1, 0), Vector2i(2, 0))
	await wait_seconds(1.0)
	_assert_at(a, Vector2i(2, 0))

func test_a_fight_winner_doesnt_cut_through_walls_to_a_losers_cell():
	# The loser stepped away as the fight began, so it fell on a cell that
	# isn't next door -- here diagonally across a wall's corner.
	var g := _corner()
	_stand(a, g, Vector2i(0, 0))
	_stand(b, g, Vector2i(1, 1))
	b.die()
	GroupCombat.conclude_pvp(a.party, b.party, Vector2i(0, 0), Vector2i(1, 1))
	await wait_seconds(1.0)
	_assert_at(a, Vector2i(0, 0))
	assert_false(a.is_moving, "and free to carry on")

func test_a_pack_fight_winner_doesnt_cut_through_walls_either():
	_stand(a, _corner(), Vector2i(0, 0))
	a.in_pack_combat = true
	a.is_moving = true
	GroupCombat.conclude_pack_fight(a, Vector2i(1, 1))
	await wait_seconds(1.0)
	_assert_at(a, Vector2i(0, 0))
	assert_false(a.is_moving, "and free to carry on")

# ============================ Stale entries ===============================

func test_a_stale_map_entry_doesnt_count_as_someone_there():
	# b is registered on (3,0) but has since moved on to (1,0) -- nobody's
	# really on (3,0) to fight or team up with.
	var g := corridor(4)
	_stand(a, g, Vector2i(2, 0))
	_stand(b, g, Vector2i(1, 0))
	players[Vector2i(3, 0)] = b
	assert_false(a._has_live_player(Vector2i(3, 0)))
	assert_true(a._has_live_player(Vector2i(1, 0)), "sanity: where b really is still counts")

func test_a_follower_left_on_the_map_doesnt_count_as_someone_there():
	var g := corridor(4)
	_stand(a, g, Vector2i(1, 0))
	_stand(b, g, Vector2i(2, 0))
	PartyOps.join_party_of(b, a)
	players[b.cell_pos] = b  # as a step finishing after the merge used to
	var c: NpcAgent = main.npcs[2]
	_stand(c, g, Vector2i(2, 0))
	assert_false(c._has_live_player(Vector2i(1, 0)), "b follows a, it doesn't lead a party of its own")

func test_a_leader_takes_its_cell_back_from_a_stale_entry():
	var g := corridor(4)
	_stand(a, g, Vector2i(1, 0))
	_stand(b, g, Vector2i(3, 0))
	players[Vector2i(1, 0)] = b  # left over from when b was here
	a._reclaim_registration()
	assert_eq(players[Vector2i(1, 0)], a)
