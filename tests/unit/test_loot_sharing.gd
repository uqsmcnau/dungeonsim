extends DungeonTest

## Covers parties splitting the xp and gold they gain (from kills, and the
## gold in chests) evenly across their living members, rather than it all
## going to whoever landed the killing blow or opened the chest.

func before_each():
	load_main()

## A party of `size` led by main.npcs[0], everyone's xp zeroed and with a
## high enough xp_to_next that nobody levels up mid-test (which would
## reset their xp counter and muddy the sums).
func _party(size: int) -> Array:
	var leader: NpcAgent = main.npcs[0]
	make_party(leader, main.npcs.slice(1, size), true)
	for m in leader.party:
		m.stats.xp = 0
		m.stats.xp_to_next = 100000
	return leader.party

func test_party_of_two_splits_xp_evenly():
	var members := _party(2)
	members[0].share_xp_with_party(10)
	assert_eq(members[0].stats.xp, 5)
	assert_eq(members[1].stats.xp, 5)

func test_uneven_split_gives_the_remainder_to_the_killer_first_and_loses_nothing():
	var members := _party(3)
	var killer: NpcAgent = members[2]  # a follower landed the blow
	killer.share_xp_with_party(10)
	assert_eq(killer.stats.xp, 4, "the killer gets the leftover point")
	assert_eq(members[0].stats.xp, 3)
	assert_eq(members[1].stats.xp, 3)

func test_party_of_four_with_two_left_over():
	var members := _party(4)
	members[0].share_xp_with_party(14)
	var total := 0
	for m in members:
		total += m.stats.xp
		assert_between(m.stats.xp, 3, 4, "everyone within a point of an even share")
	assert_eq(total, 14, "nothing lost to rounding")

func test_solo_character_keeps_all_the_xp():
	var members := _party(1)
	members[0].share_xp_with_party(10)
	assert_eq(members[0].stats.xp, 10)

func test_fallen_members_get_no_share():
	var members := _party(3)
	var fallen: NpcAgent = members[2]
	fallen.die()
	var xp_before: int = fallen.stats.xp
	members[0].share_xp_with_party(10)
	assert_eq(members[0].stats.xp, 5)
	assert_eq(members[1].stats.xp, 5)
	assert_eq(fallen.stats.xp, xp_before)

func test_each_member_who_levels_up_gets_their_level_up():
	var members := _party(2)
	for m in members:
		m.stats.xp_to_next = 5
	var leveled: Array = []
	for m in members:
		m.leveled_up.connect(func(npc): leveled.append(npc))
	members[0].share_xp_with_party(10)
	assert_eq(leveled.size(), 2, "both crossed their threshold with a 5-xp share")

func test_killing_a_monster_in_a_fight_shares_its_xp():
	var members := _party(2)
	var leader: NpcAgent = members[0]
	main.player_map[leader.cell_pos] = leader
	var enemy := new_enemy()
	var cell: Vector2i = Vector2i(-1, -1)
	for c in main.world.unrestricted_cells():
		if not main.enemy_map.has(c) and not main.chest_map.has(c):
			cell = c
			break
	enemy.setup(cell, main.CELL_SIZE, 3, main.grid, main.enemy_map, {}, [])
	var monster_xp: int = enemy.stats.xp
	assert_gt(monster_xp, 1, "sanity: enough xp to split")
	enemy.stats.hp = 0  # falls to the first action, whatever it is
	enemy.in_combat = true
	for m in members:
		m.in_pack_combat = true
		m.is_moving = true

	GroupCombat.resolve_pack_turn(leader.party, cell, leader.enemies)

	assert_eq(members[0].stats.xp + members[1].stats.xp, monster_xp, "the whole kill's xp, split between them")
	assert_gt(members[1].stats.xp, 0, "the member who didn't land the blow still gets a share")

# ================================== Gold ==================================

func _zero_gold(members: Array) -> void:
	for m in members:
		m.stats.gold = 0

func test_gold_splits_the_same_way_as_xp():
	var members := _party(3)
	_zero_gold(members)
	var killer: NpcAgent = members[1]
	killer.share_gold_with_party(11)
	assert_eq(killer.stats.gold, 4, "the killer gets the first leftover coin")
	assert_eq(members[0].stats.gold + members[2].stats.gold, 7)
	for m in members:
		assert_between(m.stats.gold, 3, 4)

func test_killing_a_monster_in_a_fight_shares_its_gold():
	var members := _party(2)
	_zero_gold(members)
	var leader: NpcAgent = members[0]
	main.player_map[leader.cell_pos] = leader
	var enemy := new_enemy()
	var cell: Vector2i = Vector2i(-1, -1)
	for c in main.world.unrestricted_cells():
		if not main.enemy_map.has(c) and not main.chest_map.has(c):
			cell = c
			break
	enemy.setup(cell, main.CELL_SIZE, 3, main.grid, main.enemy_map, {}, [])
	var monster_gold: int = enemy.stats.gold
	enemy.stats.hp = 0
	enemy.in_combat = true
	for m in members:
		m.in_pack_combat = true
		m.is_moving = true

	GroupCombat.resolve_pack_turn(leader.party, cell, leader.enemies)

	assert_eq(members[0].stats.gold + members[1].stats.gold, monster_gold)
	assert_gt(members[1].stats.gold, 0, "the member who didn't land the blow still gets a share")

func test_chest_gold_is_split_but_the_items_go_to_whoever_opened_it():
	var members := _party(2)
	_zero_gold(members)
	var opener: NpcAgent = members[0]
	opener.stats.inventory.clear()
	members[1].stats.inventory.clear()
	main.world.place_death_chest(opener.cell_pos, {"Health Potion": 1}, 10)

	opener._check_for_chest()

	assert_eq(opener.stats.gold, 5)
	assert_eq(members[1].stats.gold, 5)
	assert_true(opener.stats.has_item("Health Potion"), "items still go to whoever opened the chest")
	assert_false(members[1].stats.has_item("Health Potion"))

func test_solo_character_keeps_all_the_chest_gold():
	var members := _party(1)
	_zero_gold(members)
	main.world.place_death_chest(members[0].cell_pos, {}, 10)
	members[0]._check_for_chest()
	assert_eq(members[0].stats.gold, 10)
