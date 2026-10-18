extends DungeonTest

## Covers a player walking up to another player who's already mid-fight
## (with a monster pack, or with other players): rather than being turned
## away, a compatible newcomer merges into the fighter's party and joins the
## fight in progress -- without that fight being interrupted or restarted.

var host: NpcAgent
var newcomer: NpcAgent

func before_each():
	load_main()
	host = main.npcs[0]
	newcomer = main.npcs[1]
	for npc in [host, newcomer]:
		npc.party = [npc]
		npc.is_party_leader = true
		npc.stats.alignment = NpcStats.ALIGNMENT_GOOD
		npc.stats.inventory.clear()
		# Tanky enough that nobody flees or dies mid-test by accident.
		set_stats(npc, 10, 10000, 20, 20)
		main.player_map[npc.cell_pos] = npc

## Starts `host` fighting a pack too tough to finish within the test.
func _start_monster_fight() -> Array:
	var enemy := new_enemy()
	var enemy_cell: Vector2i = clear_cell()
	enemy.setup(enemy_cell, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	enemy.stats.hp = 100000
	enemy.stats.max_hp = 100000
	GroupCombat.engage_pack(host, enemy_cell, enemy)
	return [enemy, enemy_cell]

func _start_pvp_fight() -> NpcAgent:
	var villain: NpcAgent = main.npcs[2]
	villain.party = [villain]
	villain.is_party_leader = true
	villain.stats.alignment = NpcStats.ALIGNMENT_EVIL
	villain.stats.inventory.clear()
	set_stats(villain, 10, 10000, 20, 20)
	main.player_map[villain.cell_pos] = villain
	GroupCombat.engage_players(host, villain.cell_pos, villain)
	return villain

# ============================ Monster fights ==============================

func test_newcomer_joins_the_party_of_a_player_fighting_monsters():
	var fight := _start_monster_fight()
	newcomer._attempt_move(host.cell_pos)

	assert_true(host.party.has(newcomer), "the newcomer should merge into the fighter's party")
	assert_same(newcomer.party, host.party, "sharing the same array is what makes the fight loop include them")
	assert_true(host.is_party_leader, "the fighter stays in charge of its own fight")
	assert_false(newcomer.is_party_leader)
	assert_true(fight[0].in_combat, "the pack must still be locked in the same fight")

func test_joining_does_not_interrupt_the_fighters_combat():
	_start_monster_fight()
	var action_before: String = host.current_action
	newcomer._attempt_move(host.cell_pos)

	assert_true(host.in_pack_combat, "the host must still be fighting")
	assert_true(host.is_moving, "the host's combat lock must not be released by someone joining")
	assert_eq(host.current_action, action_before, "the 'party formed' announcement shouldn't clobber the fight status")

func test_newcomer_takes_on_the_fights_combat_lock():
	_start_monster_fight()
	newcomer._attempt_move(host.cell_pos)

	assert_true(newcomer.in_pack_combat)
	assert_true(newcomer.is_moving, "locked like every other party member (see GroupCombat.engage_pack)")

func test_newcomer_stays_locked_after_its_walk_over_finishes_mid_fight():
	# relocate_to_party's tween used to unconditionally set is_moving = false
	# when it finished -- which would have unlocked the newcomer while the
	# fight was still going, letting it wander off if later promoted to leader.
	_start_monster_fight()
	newcomer._attempt_move(host.cell_pos)
	await wait_seconds(1.5)

	assert_true(host.in_pack_combat, "sanity: the fight should still be going")
	assert_true(newcomer.is_moving, "the finished walk-in tween must not release the combat lock")

func test_newcomer_fights_alongside_and_is_released_when_the_fight_ends():
	var fight := _start_monster_fight()
	var enemy: EnemyAgent = fight[0]
	var enemy_cell: Vector2i = fight[1]
	newcomer._attempt_move(host.cell_pos)
	assert_true(host.living_party().has(newcomer), "the fight loop iterates living_party() -- the newcomer must be in it")

	enemy.stats.hp = 0  # not 1: attacks can miss, and the test would flake
	GroupCombat.resolve_pack_turn(host.party, enemy_cell, host.enemies)

	assert_false(main.enemy_map.has(enemy_cell), "sanity: the pack should be defeated")
	assert_false(newcomer.in_pack_combat, "the newcomer's combat flag should be released with everyone else's")
	assert_false(newcomer.is_moving)

func test_incompatible_newcomer_retreats_instead_of_joining_or_attacking():
	_start_monster_fight()
	newcomer.stats.alignment = NpcStats.ALIGNMENT_EVIL
	newcomer._attempt_move(host.cell_pos)

	assert_false(host.party.has(newcomer), "Good and Evil never band together")
	assert_false(host.in_pvp_combat, "a player mid-fight is never jumped by someone else")
	assert_false(newcomer.in_pvp_combat)

func test_newcomer_cannot_join_when_it_would_exceed_the_party_cap():
	_start_monster_fight()
	for i in range(3, 2 + PartyOps.MAX_PARTY_SIZE):
		var extra: NpcAgent = main.npcs[i]
		host.party.append(extra)
		extra.party = host.party
		extra.is_party_leader = false
	assert_eq(host.party.size(), PartyOps.MAX_PARTY_SIZE, "sanity: the host's party is already full")
	newcomer._attempt_move(host.cell_pos)

	assert_false(host.party.has(newcomer))

func test_idle_newcomer_sharing_a_cell_joins_the_fighter_not_the_other_way_round():
	_start_monster_fight()
	newcomer.cell_pos = host.cell_pos
	main.player_map[host.cell_pos] = host
	newcomer.is_moving = false
	newcomer.finished = false
	newcomer._process(0.0)

	assert_true(host.party.has(newcomer))
	assert_true(host.is_party_leader, "the fighter must stay leader -- pulling it into the newcomer's party would abandon its fight")
	assert_true(host.in_pack_combat)

# ================ Approaching from the monster's side =====================

func test_newcomer_walking_into_the_monster_joins_the_party_fighting_it():
	var fight := _start_monster_fight()
	var enemy_cell: Vector2i = fight[1]
	newcomer._attempt_move(enemy_cell)

	assert_true(host.party.has(newcomer), "should find and join the party already fighting this monster")
	assert_true(host.is_party_leader)
	assert_true(newcomer.in_pack_combat)
	assert_true(host.in_pack_combat, "the host's fight must carry on uninterrupted")
	assert_true(fight[0].in_combat)

func test_newcomer_joining_from_the_monster_side_moves_to_the_fighters_cell():
	var fight := _start_monster_fight()
	newcomer._attempt_move(fight[1])
	await wait_seconds(1.5)

	assert_eq(newcomer.cell_pos, host.cell_pos, "should end up alongside the party, not on the monster's cell")

func test_incompatible_newcomer_walking_into_the_monster_still_backs_off():
	var fight := _start_monster_fight()
	newcomer.stats.alignment = NpcStats.ALIGNMENT_EVIL
	newcomer._attempt_move(fight[1])

	assert_false(host.party.has(newcomer))
	assert_eq(newcomer.party, [newcomer])

func test_pack_records_the_party_it_is_fighting():
	var fight := _start_monster_fight()
	var enemy: EnemyAgent = fight[0]
	assert_same(enemy.fighting_party, host.party, "the same shared array, so it tracks joins and deaths")

func test_newcomer_finds_the_promoted_leader_if_the_original_fighter_died():
	var follower: NpcAgent = main.npcs[3]
	follower.stats.alignment = NpcStats.ALIGNMENT_GOOD
	host.party.append(follower)
	follower.party = host.party
	follower.is_party_leader = false
	var fight := _start_monster_fight()
	host.die()
	assert_true(follower.is_party_leader, "sanity: the follower should be promoted")

	newcomer._attempt_move(fight[1])

	assert_true(follower.party.has(newcomer), "should join whoever's leading the fight now")
	assert_true(newcomer.in_pack_combat)

# ============================== PvP fights ================================

func test_newcomer_joins_a_pvp_fight_on_its_allys_side():
	var villain := _start_pvp_fight()
	newcomer._attempt_move(host.cell_pos)

	assert_true(host.party.has(newcomer))
	assert_true(newcomer.in_pvp_combat, "should take on the PvP lock like the rest of its new party")
	assert_true(host.in_pvp_combat and villain.in_pvp_combat, "the PvP fight itself must carry on")
	assert_false(villain.party.has(newcomer), "joined the ally's side, not the enemy's")

func test_pvp_lock_is_released_for_the_newcomer_when_the_fight_ends():
	var villain := _start_pvp_fight()
	newcomer._attempt_move(host.cell_pos)

	villain.stats.hp = 0  # not 1: attacks can miss, and the test would flake
	GroupCombat.resolve_pvp_turn(host.party, villain.party, host.cell_pos, villain.cell_pos)

	assert_true(villain.dead, "sanity: the fight should be over")
	assert_false(newcomer.in_pvp_combat)
