extends DungeonTest

## Covers the gold tier: the best items in the dungeon, found only in the
## gold chest a mini boss's party leaves once all three of it are beaten --
## never in a shop or an ordinary chest.

const GOLD_ITEMS := [
	"Mithril Sword", "Aegis Shield", "Archmage's Staff", "Plate Armor", "Golden Helm", "Winged Boots", "Ring of Might",
]

func before_each():
	load_main()

## The mini boss party on `cell`, all of it.
func _party_on(cell: Vector2i) -> Array:
	return main.enemy_map[cell].pack.duplicate()

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

func test_a_gold_chest_holds_a_gold_item():
	for i in range(20):
		var item := ItemCatalog.random_item(ItemCatalog.RARITY_GOLD)
		assert_eq(item["rarity"], ItemCatalog.RARITY_GOLD)

func test_nowhere_else_has_them():
	for i in range(40):
		assert_false(GOLD_ITEMS.has(ItemCatalog.random_item(ItemCatalog.RARITY_BRONZE)["name"]), "not in an ordinary chest")
		assert_false(GOLD_ITEMS.has(ItemCatalog.random_item(ItemCatalog.RARITY_SILVER)["name"]), "nor a silver one")
	for item_name in ItemCatalog.names(ItemCatalog.RARITY_BRONZE, ItemCatalog.KIND_EQUIPMENT) + ItemCatalog.stockable_names():
		assert_false(GOLD_ITEMS.has(item_name), "nor a shop")
	assert_true(_gold_chests().is_empty(), "and none lying about to start with")

func test_they_can_be_worn():
	var stats := NpcStats.new()
	var attack_before := stats.attack_power()
	stats.acquire_item("Mithril Sword")
	assert_eq(stats.attack_power(), attack_before + 6)

# ============================== Gold chests ===============================

func test_beating_a_mini_boss_party_leaves_a_gold_chest_in_its_room():
	var cell: Vector2i = main.mini_boss_cells[0]
	for member in _party_on(cell):
		member.defeat()
	assert_true(main.chest_map.has(cell), "the Ogre Warlord's silver chest, where it fell")
	assert_eq(main.chest_map[cell].rarity, ItemCatalog.RARITY_SILVER)
	var gold := _gold_chests()
	assert_eq(gold.size(), 1)
	assert_true(main.world.zone_cells(cell).has(gold[0]), "beside it, in the room")
	assert_eq(ItemCatalog.find(main.chest_map[gold[0]].loot.keys()[0])["rarity"], ItemCatalog.RARITY_GOLD)

func test_whichever_falls_last():
	var cell: Vector2i = main.mini_boss_cells[0]
	var party := _party_on(cell)
	party.reverse()  # the guards first, the Ogre Warlord last
	for member in party:
		member.defeat()
	assert_eq(_gold_chests().size(), 1)
	assert_eq(main.chest_map[cell].rarity, ItemCatalog.RARITY_SILVER)

func test_not_until_the_whole_party_is_beaten():
	var cell: Vector2i = main.mini_boss_cells[0]
	var party := _party_on(cell)
	party[0].defeat()
	party[1].defeat()
	assert_true(_gold_chests().is_empty())

func test_only_mini_boss_parties_leave_gold():
	var pack: Array = []
	for enemy in main.enemy_container.get_children():
		if enemy.pack.size() > 1 and enemy.guarding == "" and not enemy.is_mini_boss and not enemy.is_boss:
			pack = enemy.pack.duplicate()
			break
	assert_false(pack.is_empty(), "sanity: there's an ordinary pack")
	for member in pack:
		member.defeat()
	assert_true(_gold_chests().is_empty())

func test_a_gold_chest_looks_it():
	main.world.place_chest(clear_cell(), ItemCatalog.RARITY_GOLD)
	var chest: ChestAgent = main.chest_map[_gold_chests()[0]]
	assert_ne(chest.box.color, main.chest_map.values().filter(func(c): return c.rarity == ItemCatalog.RARITY_BRONZE)[0].box.color)
