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
	leader._engage(foe_cell, f1)
	assert_true(f1.in_combat and f2.in_combat, "engaging should lock the whole pack into combat")

	var guard := 0
	while main.enemy_map.has(foe_cell) and guard < 30:
		leader._resolve_group_combat_turn(leader.cell_pos, foe_cell)
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
	frail._engage(cell, g1)
	assert_true(g1.in_combat, "sanity: the fight should have actually started")

	var fight_cell: Vector2i = frail.cell_pos
	frail._die()

	assert_true(tanky.is_party_leader, "the tanky survivor should be promoted to party leader")
	assert_eq(main.player_map.get(fight_cell), tanky, "the shared player map should now point at the promoted leader")

	var guard := 0
	while main.enemy_map.has(cell) and not tanky.dead and guard < 30:
		var driver: NpcAgent = main.player_map.get(fight_cell)
		if driver == null:
			break
		driver._resolve_group_combat_turn(fight_cell, cell)
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

	pa._engage_player(pb_cell, pb)
	assert_true(pa.in_pvp_combat and pb.in_pvp_combat, "engaging should lock both sides")

	var guard := 0
	while main.player_map.get(pb_cell) != null and guard < 30:
		pa._resolve_group_pvp_turn(pa.party, pb.party, pa_cell, pb_cell)
		guard += 1

	assert_true(pb.dead, "the weaker party's leader should have died")
	assert_false(pa.in_pvp_combat, "both sides' pvp locks should be released once it's over")

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
	while a.in_pvp_combat and b.in_pvp_combat and guard < 5:
		a._resolve_group_pvp_turn(a.party, b.party, shared_cell, shared_cell)
		if a.in_pvp_combat and b.in_pvp_combat:
			assert_ne(a.current_action, "Exploring", "turn %d: the good player's action should update" % guard)
			assert_ne(b.current_action, "Exploring", "turn %d: the evil player's action should update" % guard)
		guard += 1
		if not a.dead and not b.dead and a.in_pvp_combat:
			a._run_group_pvp_turn(a.party, b.party, shared_cell, shared_cell)

	assert_gt(guard, 0, "the fight should actually progress, not freeze in place")
	assert_true(a.dead or b.dead, "the fight should reach a real conclusion within a reasonable number of turns")
	assert_false(a.in_pvp_combat, "both combat locks should be released once it's over")
	assert_false(b.in_pvp_combat)

# ============ Regression: party frozen by a stuck pack mid-fight ===========
#
# Real reported bug: a pack-fighting party's leader could die mid-fight,
# get replaced by a promoted follower (see PartyOps.promote_next_leader),
# but that follower's own is_moving was never set true -- only the
# *original* driver got that lock in _engage. That let the promoted
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

	leader._engage(cell, enemy)

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

	leader._engage(cell, enemy)
	leader._die()  # forces the promotion mid-fight

	assert_true(follower.is_party_leader, "sanity: the follower should be promoted")
	assert_true(follower.is_moving, "the promoted follower must still be locked out of its own idle AI")

	var cell_before: Vector2i = follower.cell_pos
	follower._process(0.0)  # if the lock failed, this would try to explore/move
	assert_eq(follower.cell_pos, cell_before, "a locked character's _process must not move it")
	assert_true(follower.is_moving, "the lock should still be in place -- _process should have returned immediately")

func test_enemy_in_combat_is_released_if_the_fight_loop_finds_no_one_left_at_its_anchor_cell():
	# Reproduces the exact leak: simulate the fight's anchor cell no longer
	# having anyone registered there (as if the driver had wandered off, or
	# the whole party vanished) and confirm the pack's in_combat flag gets
	# cleared rather than staying stuck forever.
	var leader: NpcAgent = main.npcs[0]
	var enemy := _new_enemy()
	var cell: Vector2i = _clear_cell()
	enemy.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	var my_cell: Vector2i = leader.cell_pos

	leader._engage(cell, enemy)
	assert_true(enemy.in_combat, "sanity: engaging should mark the pack in_combat")

	main.player_map.erase(my_cell)  # simulate nobody being registered there any more
	leader._run_group_combat_turn(my_cell, cell)

	assert_false(enemy.in_combat, "the pack must not stay permanently marked in_combat with no one left to resolve the fight")

func test_a_pack_freed_this_way_can_be_fought_normally_afterwards():
	var leader: NpcAgent = main.npcs[0]
	var enemy := _new_enemy()
	var cell: Vector2i = _clear_cell()
	enemy.setup(cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	enemy.stats.hp = 5
	enemy.stats.max_hp = 5
	var my_cell: Vector2i = leader.cell_pos

	leader._engage(cell, enemy)
	main.player_map.erase(my_cell)
	leader._run_group_combat_turn(my_cell, cell)
	assert_false(enemy.in_combat)

	# A second, fresh character should be able to engage the now-freed pack
	# normally, rather than being forced to retreat from it forever.
	var newcomer: NpcAgent = main.npcs[1]
	_set_stats(newcomer, 20, 200, 40, 40)
	newcomer.stats.inventory.clear()
	main.player_map[newcomer.cell_pos] = newcomer
	var newcomer_cell: Vector2i = newcomer.cell_pos

	assert_true(CombatMath.decide_fight(newcomer.stats, enemy.stats), "sanity: the newcomer should be confident against this weak enemy")
	newcomer._engage(cell, enemy)
	assert_true(enemy.in_combat, "the pack should be engageable again, not stuck refusing all future fights")

	var guard := 0
	while main.enemy_map.has(cell) and guard < 30:
		newcomer._resolve_group_combat_turn(newcomer_cell, cell)
		guard += 1
	assert_false(main.enemy_map.has(cell), "the newcomer should be able to actually finish off the freed pack")
