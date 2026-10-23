extends DungeonTest

## Covers the two silver shops: deeper in than the bronze ones, on opposite
## sides of the boss room, selling the silver gear (at a silver price) that
## otherwise only comes out of a silver chest.
## Also how any shop's reached (see Shopping.step).

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

# ============================ Getting to a shop ===========================

## `npc` alone on hand-built maze `g` at (0,0), knowing of a bronze shop at
## `shop` it has business at, with a monster on `monster_cell` (if any).
func _heading_for_a_shop(npc: NpcAgent, g: Array, shop: Vector2i, monster_cell: Vector2i = MazeQuery.NONE) -> void:
	isolate(npc, g, Vector2i(0, 0), {})
	npc.stats = _shopper()
	npc.stats.equipped.clear()
	npc.shops = {shop: ItemCatalog.RARITY_BRONZE}
	npc.known_shops = {shop: true}
	if monster_cell != MazeQuery.NONE:
		var monster := new_enemy()
		monster.setup(monster_cell, main.CELL_SIZE, 1, g, npc.enemies, {}, [], false)

func test_a_shop_route_steers_round_monsters():
	var npc: NpcAgent = main.npcs[0]
	_heading_for_a_shop(npc, ring_maze(), Vector2i(2, 0), Vector2i(1, 0))
	assert_eq(Shopping.step(npc), Vector2i(0, 1), "the long way round, not into the monster")

func test_a_shop_only_past_a_monster_is_set_aside():
	# Otherwise the next thing on the list -- a chest, say -- took the step
	# instead, and could lead straight back: to and fro between two cells.
	var npc: NpcAgent = main.npcs[0]
	_heading_for_a_shop(npc, corridor(3), Vector2i(2, 0), Vector2i(1, 0))
	assert_eq(Shopping.step(npc), npc.cell_pos)
	assert_true(npc.skipped_shops.has(Vector2i(2, 0)), "nor straight back to it the next step")

func test_once_its_picked_a_shop_it_keeps_going_for_it():
	# Picking the nearer shop afresh every step -- nearer as the crow flies,
	# though the ways there wind -- had it turn from one shop to another and
	# back. Here it set off for the shop at the far end; now the other's
	# nearer, but it carries on.
	var npc: NpcAgent = main.npcs[0]
	isolate(npc, corridor(5), Vector2i(1, 0), {})
	npc.stats = _shopper()
	npc.stats.equipped.clear()
	npc.shops = {Vector2i(0, 0): ItemCatalog.RARITY_BRONZE, Vector2i(4, 0): ItemCatalog.RARITY_BRONZE}
	npc.known_shops = {Vector2i(0, 0): true, Vector2i(4, 0): true}
	npc.shop_goal = Vector2i(4, 0)
	assert_eq(Shopping.step(npc), Vector2i(2, 0), "on towards the shop it picked")
	npc.shop_goal = MazeQuery.NONE
	assert_eq(Shopping.step(npc), Vector2i(0, 0), "sanity: picking afresh, it'd go the other way")

func test_a_shop_route_only_steers_round_monsters_in_sight():
	# Steering round monsters wandering about far off had the way to a
	# distant shop change with every step they took.
	var npc: NpcAgent = main.npcs[0]
	var g := walled_grid(10, 2)
	for x in range(9):
		open_between(g, Vector2i(x, 0), Vector2i(x + 1, 0))
		open_between(g, Vector2i(x, 1), Vector2i(x + 1, 1))
	open_between(g, Vector2i(0, 0), Vector2i(0, 1))
	open_between(g, Vector2i(9, 0), Vector2i(9, 1))
	# Two ways to the shop at (9,1): along the top, then down; or down, then
	# along the bottom. A monster far off at (8,0), on the top way.
	_heading_for_a_shop(npc, g, Vector2i(9, 1), Vector2i(8, 0))
	npc.cell_pos = Vector2i(1, 0)
	assert_eq(Shopping.step(npc), Vector2i(2, 0), "straight on: it's out of sight")

func test_a_way_to_a_shop_that_doubles_back_on_itself_is_given_up():
	# A monster pacing alongside, the far side of a wall, blocked one way
	# round and then the other: there, back, there, back...
	var npc: NpcAgent = main.npcs[0]
	_heading_for_a_shop(npc, corridor(5), Vector2i(4, 0))
	npc.cell_pos = Vector2i(2, 0)
	npc.shop_goal = Vector2i(4, 0)
	npc.shop_step_from = Vector2i(3, 0)  # its last step for the shop came from (3,0)
	assert_eq(Shopping.step(npc), npc.cell_pos, "not straight back there")
	assert_true(npc.skipped_shops.has(Vector2i(4, 0)), "the shop's set aside for now")

func test_but_turning_round_for_a_shop_just_walked_past_is_fine():
	var npc: NpcAgent = main.npcs[0]
	_heading_for_a_shop(npc, corridor(5), Vector2i(0, 0))
	npc.cell_pos = Vector2i(2, 0)  # exploring brought it here from (1,0)
	assert_eq(Shopping.step(npc), Vector2i(1, 0), "back the way it came: its last step wasn't for the shop")
