extends DungeonTest

## Covers the two silver shops: deeper in than the bronze ones, on opposite
## sides of the boss room, selling the silver gear (at a silver price) that
## otherwise only comes out of a silver chest.

func before_each():
	load_main()

func _shops_of(rarity: String) -> Array:
	return main.shop_cells.filter(func(c): return main.shop_map[c] == rarity)

## A character with plenty of gold, nothing to sell and potions enough --
## its only business at a shop is gear.
func _shopper() -> NpcStats:
	var stats := NpcStats.new()
	stats.gold = 1000
	for potion in ItemCatalog.stockable_names():
		stats.inventory[potion] = NpcStats.POTION_RESERVE_TARGET
	return stats

# ================================ Placing =================================

func test_two_silver_shops_nearer_the_middle_than_any_bronze_one():
	var silver := _shops_of(ItemCatalog.RARITY_SILVER)
	assert_eq(silver.size(), WorldBuilder.SILVER_SHOP_COUNT)
	var nearest_bronze := INF
	for shop in _shops_of(ItemCatalog.RARITY_BRONZE):
		nearest_bronze = minf(nearest_bronze, from_middle(shop))
	for shop in silver:
		assert_between(from_middle(shop), WorldBuilder.SILVER_SHOP_REACH.x - 1.0, WorldBuilder.SILVER_SHOP_REACH.y + 1.0)
		assert_lt(from_middle(shop), nearest_bronze)

func test_on_opposite_sides_of_the_boss_room():
	var silver := _shops_of(ItemCatalog.RARITY_SILVER)
	var a := Vector2(silver[0] - main.exit_cell)
	var b := Vector2(silver[1] - main.exit_cell)
	assert_gt(absf(a.angle_to(b)), PI / 2.0)

func test_a_silver_shop_is_a_safe_room_like_any_other():
	for shop in _shops_of(ItemCatalog.RARITY_SILVER):
		for c in main.world.zone_cells(shop):
			assert_true(main.restricted_cells.has(c), str(c))

func test_it_shows_silver_on_the_map():
	for shop in _shops_of(ItemCatalog.RARITY_SILVER):
		assert_eq(main.maze_view.shops[shop], ItemCatalog.RARITY_SILVER)
	assert_ne(MazeView.SILVER_SHOP_COLOR, MazeView.SHOP_COLOR)

# ================================ Selling =================================

func test_it_sells_the_silver_gear():
	var stock := _shopper().missing_items(ItemCatalog.RARITY_SILVER)
	stock.sort()
	var silver := ItemCatalog.names(ItemCatalog.RARITY_SILVER, ItemCatalog.KIND_EQUIPMENT)
	silver.sort()
	assert_eq(stock, silver)
	for item_name in _shopper().missing_items():
		assert_eq(ItemCatalog.find(item_name).rarity, ItemCatalog.RARITY_BRONZE, "a bronze shop sells none of it")

func test_at_a_silver_price():
	var stats := _shopper()
	assert_gt(stats.buy_price(ItemCatalog.RARITY_SILVER), stats.buy_price())

func test_too_dear_and_theres_no_business_there():
	var stats := _shopper()
	stats.gold = stats.buy_price(ItemCatalog.RARITY_SILVER) - 1
	assert_true(stats.has_shop_business(), "a bronze shop's gear's affordable")
	assert_false(stats.has_shop_business(ItemCatalog.RARITY_SILVER))

func test_a_party_at_a_silver_shop_buys_silver():
	var npc: NpcAgent = main.npcs[0]
	var shop: Vector2i = _shops_of(ItemCatalog.RARITY_SILVER)[0]
	npc.stats = _shopper()
	npc.stats.equipped.clear()
	npc.stats.inventory.erase("Iron Sword")
	npc.cell_pos = shop
	npc._finish_shopping()
	assert_true(npc.stats.has_item("Steel Sword") or npc.stats.has_item("Chainmail"), "came away with silver gear")
	for item_name in npc.stats.inventory:
		var item := ItemCatalog.find(item_name)
		if item.kind == ItemCatalog.KIND_EQUIPMENT:
			assert_eq(item.rarity, ItemCatalog.RARITY_SILVER, "no bronze gear from a silver shop: %s" % item_name)

func test_they_only_make_for_a_silver_shop_with_business_there():
	var npc: NpcAgent = main.npcs[0]
	var shop: Vector2i = _shops_of(ItemCatalog.RARITY_SILVER)[0]
	npc.stats = _shopper()
	npc.stats.gold = npc.stats.buy_price(ItemCatalog.RARITY_SILVER) - 1
	npc.known_shops = {shop: true}
	assert_eq(Shopping.step(npc), npc.cell_pos, "can't afford a thing there")
	npc.stats.gold = 1000
	assert_ne(Shopping.step(npc), npc.cell_pos, "now it's worth the trip")
