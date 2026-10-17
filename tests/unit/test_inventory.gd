extends GutTest

## Covers NpcStats' equipment/inventory/shop economics in isolation -- no
## scene instantiation needed, just the Resource itself.

var stats: NpcStats

func before_each():
	stats = NpcStats.new()

# ============================ Equip vs spare ===============================

func test_acquire_item_fills_an_empty_slot():
	var worn: bool = stats.acquire_item("Iron Sword")
	assert_true(worn)
	assert_eq(stats.equipped_in("hand"), ["Iron Sword"])
	assert_eq(stats.spare_count("Iron Sword"), 0)

func test_acquire_item_keeps_a_duplicate_as_a_spare():
	stats.acquire_item("Iron Sword")
	var worn_second: bool = stats.acquire_item("Iron Sword")
	assert_false(worn_second, "a duplicate of something already worn shouldn't also get worn")
	assert_eq(stats.spare_count("Iron Sword"), 1)
	assert_eq(int(stats.inventory["Iron Sword"]), 2)

func test_acquire_item_swaps_out_the_weakest_when_a_full_slot_gets_a_better_item():
	# "hand" holds 2. Fill it with two weak items, then a stronger one should
	# bump the weakest (Iron Sword, attack 2) rather than Shield (defense 1 +
	# evasion 0.03, worth more under EFFECT_WEIGHTS since evasion is weighted
	# heavily) or stay a spare.
	stats.acquire_item("Iron Sword")
	stats.acquire_item("Shield")
	assert_eq(stats.equipped_in("hand").size(), 2)

	var worn: bool = stats.acquire_item("Arcane Tome")  # intelligence 2 -- worth more than Iron Sword's attack 2? check via value_of
	# Arcane Tome value = 2 * EFFECT_WEIGHTS[intelligence](0.5) = 1.0
	# Iron Sword value = 2 * EFFECT_WEIGHTS[attack](1.0) = 2.0
	# Shield value = 1*1.0 + 0.03*20.0 = 1.6
	# Arcane Tome (1.0) is weaker than BOTH -- should stay a spare, not swap in.
	assert_false(worn, "a weaker item than everything already worn should stay a spare")
	assert_eq(stats.spare_count("Arcane Tome"), 1)

func test_acquire_item_does_swap_in_a_genuinely_stronger_item():
	stats.acquire_item("Iron Sword")  # value 2.0
	stats.acquire_item("Shield")  # value 1.6, the weakest of the two
	var worn: bool = stats.acquire_item("Steel Sword")  # attack 4 -> value 4.0, clearly stronger
	assert_true(worn)
	assert_has(stats.equipped_in("hand"), "Steel Sword")
	assert_does_not_have(stats.equipped_in("hand"), "Shield")
	assert_eq(stats.spare_count("Shield"), 1, "the bumped item becomes a spare rather than vanishing")

func test_would_equip_is_always_false_for_a_consumable():
	assert_false(stats.would_equip("Health Potion"))

func test_consume_item_decrements_and_removes_at_zero():
	stats.inventory["Health Potion"] = 2
	stats.consume_item("Health Potion")
	assert_eq(int(stats.inventory["Health Potion"]), 1)
	stats.consume_item("Health Potion")
	assert_false(stats.inventory.has("Health Potion"), "the entry should be removed once it hits zero")

# ============================ Shop economics ===============================

func test_sell_spares_sells_everything_not_worn_and_pays_out():
	stats.charisma = 0
	stats.acquire_item("Iron Sword")
	stats.acquire_item("Iron Sword")  # one worn, one spare
	stats.acquire_item("Shield")  # worn (second hand slot)
	stats.acquire_item("Leather Armor")
	stats.acquire_item("Leather Armor")  # one worn, one spare

	var sold: int = stats.sell_spares()
	assert_eq(sold, 2)
	assert_eq(stats.gold, 2 * stats.sell_price())
	assert_eq(stats.spare_count("Iron Sword"), 0)
	assert_eq(stats.spare_count("Leather Armor"), 0)
	assert_true(stats.is_equipped("Iron Sword"), "the worn copy should survive the sale")

func test_buy_missing_only_buys_items_that_would_actually_be_worn():
	stats.charisma = 0
	stats.gold = 10000
	# Fill both hand slots with the two strongest hand items so every other
	# hand item in the catalog would_equip() to false.
	stats.acquire_item("Steel Sword")
	stats.acquire_item("Silver Shield")
	var before_gold: int = stats.gold

	var bought: Array = stats.buy_missing()

	assert_does_not_have(bought, "Iron Sword", "a weaker hand item that wouldn't be worn shouldn't be bought")
	assert_does_not_have(bought, "Shield")
	assert_does_not_have(bought, "Arcane Tome")
	assert_has(bought, "Leather Armor", "an empty slot's item should still be bought")
	assert_lt(stats.gold, before_gold, "buying anything should have spent some gold")

func test_buy_missing_stops_once_gold_runs_out():
	stats.charisma = 0
	stats.gold = stats.buy_price()  # enough for exactly one purchase
	var bought: Array = stats.buy_missing()
	assert_eq(bought.size(), 1)
	assert_eq(stats.gold, 0)

func test_charisma_discount_is_clamped_at_its_cap():
	# Buy and sell have different caps (0.5 vs 1.0), so the charisma needed
	# to clamp BOTH has to be based on whichever cap is larger.
	var larger_cap: float = max(NpcStats.MAX_BUY_DISCOUNT, NpcStats.MAX_SELL_BONUS)
	var at_cap := NpcStats.new()
	at_cap.charisma = int(ceil(larger_cap / NpcStats.CHARISMA_PRICE_STEP)) + 5
	var way_beyond := NpcStats.new()
	way_beyond.charisma = 1000  # absurdly high -- should clamp, not keep getting cheaper
	assert_eq(at_cap.buy_price(), way_beyond.buy_price(), "price should stop improving once the discount caps out")
	assert_eq(at_cap.sell_price(), way_beyond.sell_price())

func test_higher_charisma_means_cheaper_buying_and_better_selling():
	var poor_talker := NpcStats.new()
	poor_talker.charisma = 0
	var smooth_talker := NpcStats.new()
	smooth_talker.charisma = 10
	assert_lt(smooth_talker.buy_price(), poor_talker.buy_price())
	assert_gt(smooth_talker.sell_price(), poor_talker.sell_price())

func test_has_shop_business_false_when_nothing_to_do():
	stats.gold = 0
	assert_false(stats.has_shop_business())

func test_has_shop_business_true_with_spares_to_sell():
	stats.acquire_item("Iron Sword")
	stats.acquire_item("Iron Sword")
	assert_true(stats.has_shop_business())

func test_has_shop_business_true_with_gold_and_something_missing():
	stats.gold = 10000
	assert_true(stats.has_shop_business())

func test_buy_potions_tops_up_to_the_reserve_target():
	stats.charisma = 0
	stats.gold = 10000
	var bought: Array = stats.buy_potions()
	assert_gt(bought.size(), 0)
	for potion_name in ItemCatalog.stockable_names(ItemCatalog.RARITY_BRONZE):
		assert_eq(int(stats.inventory.get(potion_name, 0)), NpcStats.POTION_RESERVE_TARGET)
