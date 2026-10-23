extends DungeonTest

## Covers the gold tier: the best items in the dungeon, found only in the
## gold chest an Ogre Warlord's party leaves once all three of it are
## beaten -- never in a shop or an ordinary chest -- and the silver chest an
## Orc Chieftain's party leaves. Also that the silver tier sits between
## bronze and gold, slot by slot.

const GOLD_ITEMS := [
	"Mithril Sword", "Aegis Shield", "Archmage's Staff", "Plate Armor", "Golden Helm", "Winged Boots", "Ring of Might",
]

func before_each():
	load_main()

## Gold chests in the maze, by cell.
func _gold_chests() -> Array:
	return main.chest_map.keys().filter(func(c): return main.chest_map[c].rarity == ItemCatalog.RARITY_GOLD)

# ================================= Items ==================================

func test_the_gold_tier_has_its_items():
	var gold := ItemCatalog.names(ItemCatalog.RARITY_GOLD)
	gold.sort()
	var expected := GOLD_ITEMS.duplicate()
	expected.sort()
	assert_eq(gold, expected)

func test_each_beats_what_came_before_it():
	assert_gt(ItemCatalog.value_of("Mithril Sword"), ItemCatalog.value_of("Steel Sword"))
	assert_gt(ItemCatalog.value_of("Plate Armor"), ItemCatalog.value_of("Chainmail"))
	assert_gt(ItemCatalog.value_of("Aegis Shield"), ItemCatalog.value_of("Silver Shield"))
	assert_gt(ItemCatalog.value_of("Golden Helm"), ItemCatalog.value_of("Helmet"))
	assert_gt(ItemCatalog.value_of("Winged Boots"), ItemCatalog.value_of("Leather Boots"))

func test_silver_fills_the_gap_between_bronze_and_gold():
	for tiers in [["Helmet", "Steel Helm", "Golden Helm"], ["Leather Boots", "Swift Boots", "Winged Boots"],
			["Arcane Tome", "Enchanted Tome", "Archmage's Staff"], ["Sage's Amulet", "Moonstone Amulet"],
			["Silver Ring", "Ring of Vigor", "Ring of Might"]]:
		for i in range(tiers.size() - 1):
			assert_gt(ItemCatalog.value_of(tiers[i + 1]), ItemCatalog.value_of(tiers[i]), "%s over %s" % [tiers[i + 1], tiers[i]])
		assert_eq(ItemCatalog.find(tiers[1]).rarity, ItemCatalog.RARITY_SILVER, tiers[1])

func test_the_new_silver_pieces_show_in_battle():
	var stats := NpcStats.new()
	for item in ["Enchanted Tome", "Steel Helm", "Swift Boots", "Moonstone Amulet", "Ring of Vigor"]:
		stats.acquire_item(item)
	var look := BattleFighter.look_of(stats)
	assert_eq(look["off_hand"], "tome")
	for part in ["helmet", "boots", "amulet", "ring"]:
		assert_true(look[part], part)

func test_a_gold_chest_holds_a_gold_item():
	for i in range(20):
		var item := ItemCatalog.random_item(ItemCatalog.RARITY_GOLD)
		assert_eq(item.rarity, ItemCatalog.RARITY_GOLD)

func test_nowhere_else_has_them():
	for i in range(40):
		assert_false(GOLD_ITEMS.has(ItemCatalog.random_item(ItemCatalog.RARITY_BRONZE).name), "not in an ordinary chest")
		assert_false(GOLD_ITEMS.has(ItemCatalog.random_item(ItemCatalog.RARITY_SILVER).name), "nor a silver one")
	for item_name in ItemCatalog.names(ItemCatalog.RARITY_BRONZE, ItemCatalog.KIND_EQUIPMENT) + ItemCatalog.stockable_names():
		assert_false(GOLD_ITEMS.has(item_name), "nor a shop")
	assert_true(_gold_chests().is_empty(), "and none lying about to start with")

func test_they_can_be_worn():
	var stats := NpcStats.new()
	var attack_before := stats.attack_power()
	stats.acquire_item("Mithril Sword")
	assert_eq(stats.attack_power(), attack_before + 6)

# ============================== Mid boss chests ===========================

## The middle of the first mid boss room led by `kind_name`.
func _room_of(kind_name: String) -> Vector2i:
	for cell in main.mid_boss_cells:
		if main.enemy_map[cell].kind.name == kind_name:
			return cell
	return MazeQuery.NONE

func _beat(cell: Vector2i, last_first: bool = false) -> void:
	var party := monster_on(cell).pack.duplicate()
	if last_first:
		party.reverse()
	for member in party:
		member.defeat()

func test_beating_an_ogre_warlords_party_leaves_a_gold_chest():
	var cell := _room_of("Ogre Warlord")
	_beat(cell)
	assert_eq(_gold_chests(), [cell], "where the party stood")
	assert_eq(ItemCatalog.find(main.chest_map[cell].loot.keys()[0]).rarity, ItemCatalog.RARITY_GOLD)

func test_beating_an_orc_chieftains_party_leaves_a_silver_chest():
	var cell := _room_of("Orc Chieftain")
	_beat(cell)
	assert_eq(main.chest_map[cell].rarity, ItemCatalog.RARITY_SILVER)
	assert_true(_gold_chests().is_empty())

func test_whichever_falls_last():
	var cell := _room_of("Ogre Warlord")
	_beat(cell, true)  # the guards first, the Ogre Warlord last
	assert_eq(_gold_chests(), [cell])

func test_not_until_the_whole_party_is_beaten():
	for kind_name in ["Ogre Warlord", "Orc Chieftain"]:
		var cell := _room_of(kind_name)
		var party := monster_on(cell).pack.duplicate()
		party[0].defeat()
		party[1].defeat()
		assert_false(main.chest_map.has(cell), "%s's party still has a guard standing" % kind_name)

func test_only_mid_boss_parties_leave_chests():
	var pack: Array = []
	for enemy in main.enemy_container.get_children():
		if enemy.pack.size() > 1 and enemy.guarding == "" and not enemy.is_mid_boss and not enemy.is_boss:
			pack = enemy.pack.duplicate()
			break
	assert_false(pack.is_empty(), "sanity: there's an ordinary pack")
	var cell: Vector2i = pack[0].cell_pos
	for member in pack:
		member.defeat()
	assert_false(main.chest_map.has(cell))

func test_a_gold_chest_looks_it():
	main.world.place_chest(clear_cell(), ItemCatalog.RARITY_GOLD)
	var chest: ChestAgent = main.chest_map[_gold_chests()[0]]
	assert_ne(chest.box.color, main.chest_map.values().filter(func(c): return c.rarity == ItemCatalog.RARITY_BRONZE)[0].box.color)
