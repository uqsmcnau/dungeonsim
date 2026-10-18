extends DungeonTest

## Covers how a party shares items: chest loot goes to whichever member it
## helps most (gear to whoever it's the biggest upgrade for, a spell tome to
## whoever can learn from it, potions to whoever has fewest), and at a shop
## the whole party trades -- passing spare gear to party-mates who'd wear it
## before anyone sells, then everyone buying with their own gold.

func before_each():
	load_main()

## Takes off and throws away everything a character owns, so tests start
## from a known, empty kit.
func _strip(npc: NpcAgent) -> void:
	for slot in npc.stats.equipped.keys():
		for item_name in npc.stats.equipped[slot].duplicate():
			npc.stats._unequip(item_name)
	npc.stats.inventory.clear()
	npc.stats.known_spells.clear()
	npc.stats.gold = 0

## A stripped party of `size` led by main.npcs[0].
func _party(size: int) -> Array:
	var leader: NpcAgent = main.npcs[0]
	leader.party = [leader]
	leader.is_party_leader = true
	for i in range(1, size):
		var member: NpcAgent = main.npcs[i]
		member.party = leader.party
		member.is_party_leader = false
		member.cell_pos = leader.cell_pos
		leader.party.append(member)
	for m in leader.party:
		_strip(m)
	return leader.party

func _open_chest_with(opener: NpcAgent, loot: Dictionary) -> void:
	main.world.place_death_chest(opener.cell_pos, loot, 0)
	opener._check_for_chest()

# ============================ upgrade_value ===============================

func test_upgrade_value_is_the_items_worth_when_its_slot_is_free():
	var npc: NpcAgent = _party(1)[0]
	assert_eq(npc.stats.upgrade_value("Helmet"), ItemCatalog.value_of("Helmet"))

func test_upgrade_value_is_the_gain_over_what_it_would_replace():
	var npc: NpcAgent = _party(1)[0]
	npc.stats.acquire_item("Leather Armor")
	assert_eq(npc.stats.upgrade_value("Chainmail"), ItemCatalog.value_of("Chainmail") - ItemCatalog.value_of("Leather Armor"))

func test_upgrade_value_is_zero_for_anything_that_would_not_be_worn():
	var npc: NpcAgent = _party(1)[0]
	npc.stats.acquire_item("Chainmail")
	assert_eq(npc.stats.upgrade_value("Leather Armor"), 0.0, "a downgrade")
	assert_eq(npc.stats.upgrade_value("Chainmail"), 0.0, "already wearing one")
	assert_eq(npc.stats.upgrade_value("Health Potion"), 0.0, "consumables aren't worn")

# =============================== Chests ===================================

func test_chest_gear_goes_to_the_member_it_helps_most():
	var members := _party(2)
	var opener: NpcAgent = members[0]
	var mate: NpcAgent = members[1]
	opener.stats.acquire_item("Helmet")  # the opener's already covered
	_open_chest_with(opener, {"Helmet": 1})

	assert_true(mate.stats.is_equipped("Helmet"), "the bare-headed member should get it and wear it")
	assert_eq(opener.stats.spare_count("Helmet"), 0, "not left as a useless spare with the opener")

func test_chest_gear_goes_to_the_bigger_upgrade():
	var members := _party(2)
	var opener: NpcAgent = members[0]
	var mate: NpcAgent = members[1]
	opener.stats.acquire_item("Leather Armor")  # Chainmail is a modest upgrade for the opener...
	# ...but a full upgrade for the unarmoured mate.
	_open_chest_with(opener, {"Chainmail": 1})
	assert_true(mate.stats.is_equipped("Chainmail"))

func test_chest_gear_nobody_can_use_stays_with_the_opener_as_a_spare():
	var members := _party(2)
	for m in members:
		m.stats.acquire_item("Helmet")
	_open_chest_with(members[0], {"Helmet": 1})
	assert_eq(members[0].stats.spare_count("Helmet"), 1)
	assert_eq(members[1].stats.spare_count("Helmet"), 0)

func test_two_copies_go_to_two_different_members():
	var members := _party(2)
	_open_chest_with(members[0], {"Helmet": 2})
	assert_true(members[0].stats.is_equipped("Helmet"))
	assert_true(members[1].stats.is_equipped("Helmet"), "the second copy should go to whoever's still bare-headed")

func test_tome_goes_to_a_member_who_does_not_know_the_spell_and_is_read_at_once():
	var members := _party(2)
	var opener: NpcAgent = members[0]
	var mate: NpcAgent = members[1]
	opener.stats.learn_spell("spark")
	_open_chest_with(opener, {"Tome of Spark": 1})

	assert_true(mate.stats.knows_spell("spark"), "a follower can't stop to read later, so it learns on the spot")
	assert_false(mate.stats.has_item("Tome of Spark"), "the tome is used up")
	assert_false(opener.stats.has_item("Tome of Spark"))

func test_tome_goes_to_the_smartest_member_who_can_learn_it():
	var members := _party(3)
	members[0].stats.intelligence = 3
	members[1].stats.intelligence = 9
	members[2].stats.intelligence = 5
	_open_chest_with(members[0], {"Tome of Fireball": 1})
	assert_true(members[1].stats.knows_spell("fireball"))

func test_tome_for_the_leader_is_kept_to_read_at_the_next_idle_moment():
	var members := _party(2)
	members[0].stats.intelligence = 9
	members[1].stats.intelligence = 3
	_open_chest_with(members[0], {"Tome of Spark": 1})
	assert_true(members[0].stats.has_item("Tome of Spark"), "the leader reads tomes on its own idle time, as before")
	assert_eq(members[0]._pending_tome(), "Tome of Spark")

func test_potions_go_to_whoever_holds_fewest():
	var members := _party(2)
	members[0].stats.acquire_item("Health Potion")
	_open_chest_with(members[0], {"Health Potion": 1})
	assert_eq(int(members[1].stats.inventory.get("Health Potion", 0)), 1)

func test_solo_character_keeps_everything():
	var members := _party(1)
	_open_chest_with(members[0], {"Helmet": 1, "Health Potion": 1})
	assert_true(members[0].stats.is_equipped("Helmet"))
	assert_true(members[0].stats.has_item("Health Potion"))

# ================================ Shops ===================================

func test_spare_gear_is_passed_to_a_party_mate_who_would_wear_it():
	var members := _party(2)
	members[0].stats.acquire_item("Helmet")
	members[0].stats.acquire_item("Helmet")  # a spare
	var passed := PartyOps.pass_spares_around(members)
	assert_eq(passed, 1)
	assert_true(members[1].stats.is_equipped("Helmet"))
	assert_eq(members[0].stats.spare_count("Helmet"), 0)

func test_the_whole_party_shops_together():
	var members := _party(2)
	var leader: NpcAgent = members[0]
	var mate: NpcAgent = members[1]
	leader.stats.acquire_item("Helmet")
	leader.stats.acquire_item("Helmet")  # spare: goes to the mate
	mate.stats.acquire_item("Shield")
	mate.stats.acquire_item("Shield")
	mate.stats.acquire_item("Shield")  # mate's hand slots: Shield + spares
	mate.stats.gold = 500  # enough to buy what the mate's missing

	leader._finish_shopping()

	assert_true(mate.stats.is_equipped("Helmet"), "spares go to a party-mate before anything's sold")
	# (Not total_spares() == 0: buying can bump an older item out of a full
	# slot, which then sits as a spare until the next visit -- solo or not.)
	assert_eq(mate.stats.spare_count("Shield"), 0, "the follower sells its own spares too")
	assert_gt(mate.stats.equipped_in("armor").size(), 0, "the follower spends its own gold on gear it'd wear")

func test_party_has_shop_business_if_any_member_does():
	var members := _party(2)
	members[1].stats.acquire_item("Helmet")
	members[1].stats.acquire_item("Helmet")  # the follower has a spare to sell
	assert_false(members[0].stats.has_shop_business(), "sanity: the leader alone has nothing to do there")
	assert_true(members[0]._party_has_shop_business())
