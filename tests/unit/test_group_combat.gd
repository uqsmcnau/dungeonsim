extends GutTest

## Covers multi-character combat: enemy packs (2-3 weaker enemies sharing
## one encounter), party-vs-pack fights, party-vs-party PvP fights, the
## mid-fight leader-death handoff, and a regression test for a real bug
## found in this system (see test_pvp_does_not_freeze_when_both_sides_share_a_cell).

const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")

var main: Node

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())

func _new_enemy() -> EnemyAgent:
	return add_child_autofree(ENEMY_SCENE.instantiate())

func _set_stats(npc: NpcAgent, level: int, hp: int, strength: int, constitution: int, dexterity: int = 10) -> void:
	npc.stats.level = level
	npc.stats.hp = hp
	npc.stats.max_hp = hp
	npc.stats.strength = strength
	npc.stats.constitution = constitution
	npc.stats.dexterity = dexterity
	npc.stats.mp = 0

## An enemy-free, chest-free, unrestricted cell -- used whenever a test needs
## a location that isn't inside anyone's safe zone or already occupied.
func _clear_cell() -> Vector2i:
	for c in main._unrestricted_cells():
		if not main.enemy_map.has(c) and not main.chest_map.has(c):
			return c
	return Vector2i(-1, -1)

# ============================= Enemy packs ================================

func test_form_pack_designates_the_first_member_as_leader():
	var e1 := _new_enemy()
	var e2 := _new_enemy()
	var e3 := _new_enemy()
	var enemy_map: Dictionary = {}
	var cell := Vector2i(5, 5)
	e1.setup(cell, main.CELL_SIZE, 3, main.grid, enemy_map, {}, [])
	e2.setup(cell, main.CELL_SIZE, 3, main.grid, enemy_map, {}, [])
	e3.setup(cell, main.CELL_SIZE, 3, main.grid, enemy_map, {}, [])
	EnemyAgent.form_pack([e1, e2, e3])

	assert_true(e1.is_pack_leader)
	assert_false(e2.is_pack_leader)
	assert_false(e3.is_pack_leader)
	assert_false(e2.wanders)
	assert_false(e3.wanders)
	assert_eq(enemy_map.get(cell), e1)
	assert_eq(e1.living_pack().size(), 3)

func test_pack_leader_death_promotes_a_follower():
	var e1 := _new_enemy()
	var e2 := _new_enemy()
	var enemy_map: Dictionary = {}
	var cell := Vector2i(5, 5)
	e1.setup(cell, main.CELL_SIZE, 3, main.grid, enemy_map, {}, [])
	e2.setup(cell, main.CELL_SIZE, 3, main.grid, enemy_map, {}, [])
	EnemyAgent.form_pack([e1, e2])

	e1.defeat()

	assert_true(e2.is_pack_leader)
	assert_true(e2.wanders)
	assert_eq(enemy_map.get(cell), e2)
	assert_eq(e2.living_pack().size(), 1)

func test_pack_cell_cleared_once_the_whole_pack_is_gone():
	var e1 := _new_enemy()
	var e2 := _new_enemy()
	var enemy_map: Dictionary = {}
	var cell := Vector2i(5, 5)
	e1.setup(cell, main.CELL_SIZE, 3, main.grid, enemy_map, {}, [])
	e2.setup(cell, main.CELL_SIZE, 3, main.grid, enemy_map, {}, [])
	EnemyAgent.form_pack([e1, e2])

	e1.defeat()
	e2.defeat()

	assert_false(enemy_map.has(cell))

# ========================== Party vs enemy pack ============================

func test_party_defeats_a_weaker_enemy_pack():
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	leader.party = [leader]
	leader.is_party_leader = true
	follower.party = leader.party
	follower.is_party_leader = false
	leader.party.append(follower)
	_set_stats(leader, 10, 60, 15, 10)
	_set_stats(follower, 10, 60, 15, 10)
	leader.stats.inventory.clear()
	follower.stats.inventory.clear()

	var f1 := _new_enemy()
	var f2 := _new_enemy()
	var foe_cell := _clear_cell()
	f1.setup(foe_cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	f2.setup(foe_cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	EnemyAgent.form_pack([f1, f2])
	f1.stats.hp = 8
	f1.stats.max_hp = 8
	f2.stats.hp = 8
	f2.stats.max_hp = 8

	main.player_map[leader.cell_pos] = leader
	GroupCombat.engage_pack(leader, foe_cell, f1)
	assert_true(f1.in_combat and f2.in_combat, "engaging should lock the whole pack into combat")

	var guard := 0
	while main.enemy_map.has(foe_cell) and guard < 30:
		GroupCombat.resolve_pack_turn(leader.party, foe_cell, leader.enemies)
		guard += 1

	assert_false(main.enemy_map.has(foe_cell), "the party should wipe out the 2-enemy pack")
	assert_gt(leader.living_party().size(), 0, "at least one party member should survive")

func test_mid_fight_leader_death_hands_off_to_a_surviving_follower():
	# A fragile "driver" and a tanky follower against a pack tough enough to
	# take several turns, engineered so the driver is overwhelmingly likely
	# to die first. Rather than relying on combat RNG to actually land that
	# killing blow within a turn budget (flaky -- the pack can just as
	# plausibly get wiped out first), the death is forced directly so this
	# test is deterministic about the one thing it actually checks: that
	# promotion hands the fight off cleanly rather than freezing it.
	var frail: NpcAgent = main.npcs[0]
	var tanky: NpcAgent = main.npcs[1]
	frail.party = [frail]
	frail.is_party_leader = true
	tanky.party = frail.party
	tanky.is_party_leader = false
	frail.party.append(tanky)
	_set_stats(frail, 5, 1, 10, 10, 3)
	_set_stats(tanky, 5, 300, 15, 15, 10)
	frail.stats.inventory.clear()
	tanky.stats.inventory.clear()

	var g1 := _new_enemy()
	var g2 := _new_enemy()
	var cell := _clear_cell()
	g1.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	g2.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	EnemyAgent.form_pack([g1, g2])
	for g in [g1, g2]:
		g.stats.hp = 20
		g.stats.max_hp = 20

	main.player_map[frail.cell_pos] = frail
	GroupCombat.engage_pack(frail, cell, g1)
	assert_true(g1.in_combat, "sanity: the fight should have actually started")

	var fight_cell: Vector2i = frail.cell_pos
	frail.die()

	assert_true(tanky.is_party_leader, "the tanky survivor should be promoted to party leader")
	assert_eq(main.player_map.get(fight_cell), tanky, "the shared player map should now point at the promoted leader")

	var guard := 0
	while main.enemy_map.has(cell) and not tanky.dead and guard < 30:
		GroupCombat.resolve_pack_turn(tanky.party, cell, tanky.enemies)
		guard += 1

	assert_false(main.enemy_map.has(cell), "the promoted leader should still be able to finish off the pack")

# ============================ Party vs party PvP ===========================

func test_stronger_party_defeats_a_weaker_one_in_pvp():
	var pa: NpcAgent = main.npcs[0]
	var pb: NpcAgent = main.npcs[1]
	pa.party = [pa]
	pa.is_party_leader = true
	pb.party = [pb]
	pb.is_party_leader = true
	_set_stats(pa, 5, 100, 20, 10)
	_set_stats(pb, 1, 40, 5, 10)
	pa.stats.inventory.clear()
	pb.stats.inventory.clear()
	main.player_map[pa.cell_pos] = pa
	main.player_map[pb.cell_pos] = pb
	var pa_cell: Vector2i = pa.cell_pos
	var pb_cell: Vector2i = pb.cell_pos

	GroupCombat.engage_players(pa, pb_cell, pb)
	assert_true(pa.in_pvp_combat and pb.in_pvp_combat, "engaging should lock both sides")

	var guard := 0
	while main.player_map.get(pb_cell) != null and guard < 30:
		GroupCombat.resolve_pvp_turn(pa.party, pb.party, pa_cell, pb_cell)
		guard += 1

	assert_true(pb.dead, "the weaker party's leader should have died")
	assert_false(pa.in_pvp_combat, "both sides' pvp locks should be released once it's over")

func _pvp_pair() -> Array:
	var attacker: NpcAgent = main.npcs[0]
	var defender: NpcAgent = main.npcs[1]
	for npc in [attacker, defender]:
		npc.party = [npc]
		npc.is_party_leader = true
		npc.is_moving = false
		npc.stats.inventory.clear()
		main.player_map[npc.cell_pos] = npc
	_set_stats(attacker, 5, 100, 20, 10)
	return [attacker, defender]

## Regression test for a reported bug: one player stuck "fighting" another
## who'd already run away. The attacker was locked with is_moving as well as
## in_pvp_combat, but a defender fleeing only released in_pvp_combat.
func test_attacker_is_freed_when_the_defender_flees():
	var pair := _pvp_pair()
	var attacker: NpcAgent = pair[0]
	var defender: NpcAgent = pair[1]
	_set_stats(defender, 1, 3, 5, 10)  # low enough to flee on the very first turn

	GroupCombat.engage_players(attacker, defender.cell_pos, defender)

	assert_false(defender.in_pvp_combat, "sanity: the defender should have fled")
	assert_false(attacker.in_pvp_combat)
	assert_false(attacker.is_moving, "the attacker must not be left locked in place")
	assert_eq(attacker.current_action, "Exploring", "and must not keep showing 'Fighting' someone who's gone")

	attacker.visited.clear()  # make sure there's somewhere new to go
	attacker._process(0.0)
	assert_true(attacker.is_moving, "the attacker should actually get on with exploring")

func test_attacker_is_freed_when_the_defenders_party_vanishes_mid_fight():
	# e.g. the defender killed by something else between two turns.
	var pair := _pvp_pair()
	var attacker: NpcAgent = pair[0]
	var defender: NpcAgent = pair[1]
	_set_stats(defender, 5, 100, 20, 10)
	GroupCombat.engage_players(attacker, defender.cell_pos, defender)
	assert_true(attacker.in_pvp_combat, "sanity: an even fight should be underway")

	var defender_party: Array = defender.party
	defender.die()
	GroupCombat.resolve_pvp_turn(attacker.party, defender_party, attacker.cell_pos, defender.cell_pos)

	assert_false(attacker.in_pvp_combat)
	assert_false(attacker.is_moving)

## Regression test for a real bug: when PvP starts because one leader finds
## the other already on ITS OWN cell (the idle-safety-net path), both sides
## end up registered at the exact same cell. The combat code used to look
## both sides up by cell coordinate in the same shared dictionary, which
## collapsed them into the SAME object (me == them) -- the fight's
## bookkeeping broke down into "fighting itself", freezing both characters
## with no label updates and no progress. Fixed by identifying each side by
## its party array reference instead of by cell.
func test_pvp_does_not_freeze_when_both_sides_share_a_cell():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	a.stats.alignment = NpcStats.ALIGNMENT_GOOD
	b.stats.alignment = NpcStats.ALIGNMENT_EVIL
	_set_stats(a, 5, 100, 20, 10)
	_set_stats(b, 1, 40, 5, 10)
	a.stats.inventory.clear()
	b.stats.inventory.clear()

	var shared_cell: Vector2i = _clear_cell()
	a.cell_pos = shared_cell
	b.cell_pos = shared_cell
	main.player_map[shared_cell] = b  # b's registration overwrites a's -- the exact collision scenario
	a.is_moving = false
	a.finished = false
	a.in_pvp_combat = false
	b.in_pvp_combat = false
	a.party = [a]
	a.is_party_leader = true
	b.party = [b]
	b.is_party_leader = true

	a._process(0.0)
	assert_true(a.in_pvp_combat and b.in_pvp_combat, "the fight should actually engage, not silently skip")
	assert_ne(a, b, "the two sides must not collapse into the same object")

	var guard := 0
	while a.in_pvp_combat and b.in_pvp_combat and guard < 15:
		GroupCombat.resolve_pvp_turn(a.party, b.party, shared_cell, shared_cell)
		if a.in_pvp_combat and b.in_pvp_combat:
			assert_ne(a.current_action, "Exploring", "turn %d: the good player's action should update" % guard)
			assert_ne(b.current_action, "Exploring", "turn %d: the evil player's action should update" % guard)
		guard += 1
		if not a.dead and not b.dead and a.in_pvp_combat:
			GroupCombat.run_pvp_turn(a.party, b.party, shared_cell, shared_cell)

	assert_gt(guard, 0, "the fight should actually progress, not freeze in place")
	# A real conclusion is either side falling *or* the losing side fleeing
	# once its HP gets low -- this used to demand a death within 5 turns,
	# and flaked whenever b sensibly ran for it (or a missed a few swings).
	assert_false(a.in_pvp_combat or b.in_pvp_combat, "the fight should reach a real conclusion -- a death or a retreat -- releasing both combat locks")

# ============ Regression: party frozen by a stuck pack mid-fight ===========
#
# Real reported bug: a pack-fighting party's leader could die mid-fight,
# get replaced by a promoted follower (see PartyOps.promote_next_leader),
# but that follower's own is_moving was never set true -- only the
# *original* driver got that lock in GroupCombat.engage_pack. That let the promoted
# follower's own idle _process wander off exploring while the combat-turn
# loop (bound to the *cell*, not to a specific character) was still
# supposedly driving it. If its own movement unregistered it from the
# fight's anchor cell before the next scheduled turn fired, the turn loop
# found nobody there and silently gave up -- without ever clearing the
# pack's enemy.in_combat flag. A pack stuck "in combat" forever is
# permanently un-fightable AND un-passable (_process/_attempt_move both
# retreat from a cell whose enemy.in_combat is true rather than walking
# past it) -- exactly a party (or anyone else who runs into that pack
# afterward) rendered unable to move through it.

func test_engaging_a_pack_locks_is_moving_for_every_party_member_not_just_the_driver():
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	leader.party = [leader]
	leader.is_party_leader = true
	follower.party = leader.party
	follower.is_party_leader = false
	leader.party.append(follower)
	follower.is_moving = false  # sanity: a follower's own flag starts false

	var enemy := _new_enemy()
	var cell: Vector2i = _clear_cell()
	enemy.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])

	GroupCombat.engage_pack(leader, cell, enemy)

	assert_true(leader.is_moving, "the driver should be locked, as before")
	assert_true(follower.is_moving, "the follower must be locked too -- otherwise it's free to wander off the moment it gets promoted to leader")

func test_a_follower_promoted_mid_fight_cannot_act_independently():
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	leader.party = [leader]
	leader.is_party_leader = true
	follower.party = leader.party
	follower.is_party_leader = false
	leader.party.append(follower)
	_set_stats(follower, 5, 100, 15, 15)
	follower.stats.inventory.clear()

	var enemy := _new_enemy()
	var cell: Vector2i = _clear_cell()
	enemy.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])

	GroupCombat.engage_pack(leader, cell, enemy)
	leader.die()  # forces the promotion mid-fight

	assert_true(follower.is_party_leader, "sanity: the follower should be promoted")
	assert_true(follower.is_moving, "the promoted follower must still be locked out of its own idle AI")

	var cell_before: Vector2i = follower.cell_pos
	follower._process(0.0)  # if the lock failed, this would try to explore/move
	assert_eq(follower.cell_pos, cell_before, "a locked character's _process must not move it")
	assert_true(follower.is_moving, "the lock should still be in place -- _process should have returned immediately")

func test_enemy_in_combat_is_released_if_the_fight_loop_finds_no_one_left_in_the_party():
	# The whole party gone (as if killed between turns): the pack's in_combat
	# flag must be cleared rather than staying stuck forever.
	var leader: NpcAgent = main.npcs[0]
	var enemy := _new_enemy()
	var cell: Vector2i = _clear_cell()
	enemy.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	var party_ref: Array = leader.party

	GroupCombat.engage_pack(leader, cell, enemy)
	assert_true(enemy.in_combat, "sanity: engaging should mark the pack in_combat")

	for member in party_ref.duplicate():
		member.die()
	GroupCombat.run_pack_turn(party_ref, cell, leader.enemies)

	assert_false(enemy.in_combat, "the pack must not stay permanently marked in_combat with no one left to resolve the fight")

## Regression test for a reported bug: a party of 2 stuck unable to move
## after a third member joined (and then died). A follower's die() erased
## whoever was registered on its cell -- i.e. its own leader -- and the
## fight loop, which found its driver by that registration, quit with the
## party still locked. It now tracks the party array, and die() only
## removes its own registration.
func test_follower_dying_mid_fight_does_not_strand_the_party():
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	var doomed: NpcAgent = main.npcs[2]
	leader.party = [leader, follower, doomed]
	leader.is_party_leader = true
	for m in [follower, doomed]:
		m.party = leader.party
		m.is_party_leader = false
		m.cell_pos = leader.cell_pos
	for m in leader.party:
		_set_stats(m, 10, 500, 30, 30)
		m.stats.inventory.clear()
	main.player_map[leader.cell_pos] = leader

	var enemy := _new_enemy()
	var cell: Vector2i = _clear_cell()
	enemy.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	enemy.stats.hp = 60
	GroupCombat.engage_pack(leader, cell, enemy)

	doomed.die()  # a follower falls mid-fight
	assert_eq(main.player_map.get(leader.cell_pos), leader, "a follower dying must not erase its leader's registration")

	var guard := 0
	while main.enemy_map.has(cell) and guard < 40:
		GroupCombat.resolve_pack_turn(leader.party, cell, leader.enemies)
		guard += 1
	assert_false(main.enemy_map.has(cell), "the fight should carry on to the end, not quit")
	for m in [leader, follower]:
		assert_false(m.in_pack_combat, "%s should be released once it's over" % m.npc_name)

func test_fight_carries_on_even_if_the_leaders_registration_is_lost():
	# Belt and braces: whatever knocks the party off the player map, its own
	# fight must still be driven to a proper end rather than abandoned.
	var leader: NpcAgent = main.npcs[0]
	_set_stats(leader, 10, 500, 30, 30)
	leader.stats.inventory.clear()
	var enemy := _new_enemy()
	var cell: Vector2i = _clear_cell()
	enemy.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	enemy.stats.hp = 60
	GroupCombat.engage_pack(leader, cell, enemy)

	main.player_map.erase(leader.cell_pos)
	var guard := 0
	while main.enemy_map.has(cell) and guard < 40:
		GroupCombat.resolve_pack_turn(leader.party, cell, leader.enemies)
		guard += 1
	assert_false(main.enemy_map.has(cell))
	assert_false(leader.in_pack_combat, "the party must be released, not left locked in place")

func test_leader_leaving_a_shared_cell_does_not_erase_the_other_leaders_registration():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	var shared: Vector2i = a.cell_pos
	b.cell_pos = shared
	main.player_map[shared] = b  # b arrived second, so b holds the cell

	a._on_move_finished(shared + Vector2i(1, 0))

	assert_eq(main.player_map.get(shared), b, "a moving off must not knock b off the map")

func test_promotion_does_not_overwrite_another_partys_registration():
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	var other: NpcAgent = main.npcs[2]
	leader.party = [leader, follower]
	follower.party = leader.party
	follower.is_party_leader = false
	other.cell_pos = leader.cell_pos
	main.player_map[leader.cell_pos] = other  # the other party's leader holds the shared cell

	leader.die()

	assert_true(follower.is_party_leader, "sanity: the follower should be promoted")
	assert_eq(main.player_map.get(leader.cell_pos), other)

## Regression test for a reported bug: a monster kills a player, then never
## moves again. The fight loop captured the pack leader at the start of the
## turn; if the party killed that leader (promoting a follower) and was then
## wiped out by the survivor in the same turn, the in_combat release landed
## on the dead leader and the survivor stayed locked -- frozen -- forever.
## The enemy's hits are random, so this retries with fresh fights until one
## actually plays out that way.
func test_pack_survivor_is_released_when_its_leader_and_the_party_fall_in_the_same_turn():
	var scenario_happened := false
	for attempt in range(15):
		var player: NpcAgent = main.npcs[0]
		player.party = [player]
		player.is_party_leader = true
		_set_stats(player, 1, 1, 1, 1, 1)
		player.stats.inventory.clear()
		main.player_map[player.cell_pos] = player

		var cell: Vector2i = _clear_cell()
		var leader := _new_enemy()
		var survivor := _new_enemy()
		leader.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
		survivor.setup(cell, main.CELL_SIZE, 5, main.grid, main.enemy_map, {}, [])
		EnemyAgent.form_pack([leader, survivor])
		leader.stats.hp = 0  # falls to the player's first action, whatever it is
		survivor.stats.hp = 1000
		# Engaged by hand rather than via GroupCombat.engage_pack, whose first turn would
		# have this 1-HP player flee before anything happened.
		leader.in_combat = true
		survivor.in_combat = true
		player.in_pack_combat = true
		player.is_moving = true

		GroupCombat.resolve_pack_turn(player.party, cell, player.enemies)

		assert_true(survivor.is_pack_leader, "sanity: the survivor should have taken over the pack")
		if player.dead:
			scenario_happened = true
			assert_false(survivor.in_combat, "the surviving monster must be released, not left frozen in_combat")
			break
	assert_true(scenario_happened, "sanity: the survivor should land a killing blow within 15 tries")

func test_releasing_a_fight_frees_every_pack_member_not_just_the_leader():
	# e.g. a party fleeing: the followers used to stay in_combat, so whichever
	# was promoted when the leader later fell came out frozen.
	var leader := _new_enemy()
	var follower := _new_enemy()
	var cell: Vector2i = _clear_cell()
	leader.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	follower.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	EnemyAgent.form_pack([leader, follower])
	leader.in_combat = true
	follower.in_combat = true

	GroupCombat.release_pack(main.enemy_map, cell)

	assert_false(leader.in_combat)
	assert_false(follower.in_combat, "the follower must be released too")
	leader.defeat()
	assert_true(follower.is_pack_leader and not follower.in_combat, "a later promotion must not inherit a stale combat lock")

func test_a_pack_freed_this_way_can_be_fought_normally_afterwards():
	var leader: NpcAgent = main.npcs[0]
	var enemy := _new_enemy()
	var cell: Vector2i = _clear_cell()
	enemy.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	enemy.stats.hp = 5
	enemy.stats.max_hp = 5
	var party_ref: Array = leader.party

	GroupCombat.engage_pack(leader, cell, enemy)
	leader.die()  # the whole (solo) party gone mid-fight
	GroupCombat.run_pack_turn(party_ref, cell, leader.enemies)
	assert_false(enemy.in_combat)

	# A second, fresh character should be able to engage the now-freed pack
	# normally, rather than being forced to retreat from it forever.
	var newcomer: NpcAgent = main.npcs[1]
	_set_stats(newcomer, 20, 200, 40, 40)
	newcomer.stats.inventory.clear()
	main.player_map[newcomer.cell_pos] = newcomer
	var newcomer_cell: Vector2i = newcomer.cell_pos

	# Check the odds, not decide_fight itself -- that rolls randf() against a
	# chance capped at 0.95, so it would flake ~5% of runs even here.
	assert_gte(CombatMath.win_chance_against(newcomer.stats, enemy.stats), 0.95, "sanity: the newcomer should be confident against this weak enemy")
	GroupCombat.engage_pack(newcomer, cell, enemy)
	assert_true(enemy.in_combat, "the pack should be engageable again, not stuck refusing all future fights")

	var guard := 0
	while main.enemy_map.has(cell) and guard < 30:
		GroupCombat.resolve_pack_turn(newcomer.party, cell, newcomer.enemies)
		guard += 1
	assert_false(main.enemy_map.has(cell), "the newcomer should be able to actually finish off the freed pack")
