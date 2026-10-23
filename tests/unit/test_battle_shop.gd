extends DungeonTest

## Covers the shop in the battle window: the shopkeeper behind their counter
## while the selected party's at a shop (NpcAgent.shopping_at), sliding in
## and back out.

var bw: BattleWindow
var a: NpcAgent
var b: NpcAgent

func before_each():
	load_main()
	bw = main.hud.battle_window
	a = main.npcs[0]
	b = main.npcs[1]

# ================================ At a shop ===============================

func test_a_party_at_a_shop_finds_its_shopkeeper_there():
	main.hud.inspect(a)
	a.shopping_at = ItemCatalog.RARITY_SILVER
	main._sync_battle_window()
	assert_eq(bw.shop, ItemCatalog.RARITY_SILVER, "the counter trimmed in silver")
	a.shopping_at = ""
	main._sync_battle_window()
	assert_eq(bw.shop, "", "gone once they've moved on")

func test_not_for_a_party_nobodys_watching():
	main.hud.inspect(a)
	b.shopping_at = ItemCatalog.RARITY_BRONZE
	main._sync_battle_window()
	assert_eq(bw.shop, "")

func test_nor_with_nobody_selected():
	main.hud.inspect(a)
	a.shopping_at = ItemCatalog.RARITY_BRONZE
	main._sync_battle_window()
	main.hud.close_inspector()
	assert_eq(bw.shop, "")

## Where the shopkeeper stands once slid in.
func _shop_home() -> Vector2:
	return Vector2(bw.size.x - BattleWindow.SHOP_SPOT.x, BattleWindow.SHOP_SPOT.y)

## A's selected and on its way, then arrives at a silver shop.
func _arrive_at_shop() -> void:
	main.hud.inspect(a)
	main._sync_battle_window()
	a.shopping_at = ItemCatalog.RARITY_SILVER
	main._sync_battle_window()

func test_the_shop_slides_in_from_the_right():
	_arrive_at_shop()
	assert_gt(bw.shop_position().x, bw.size.x, "out of sight to start with")
	bw.advance(BattleWindow.ENTER_SECONDS / 2.0)
	assert_between(bw.shop_position().x, _shop_home().x + 1.0, bw.size.x, "on its way in")
	bw.advance(BattleWindow.ENTER_SECONDS / 2.0)
	assert_eq(bw.shop_position(), _shop_home())

func test_and_back_out_once_they_leave():
	_arrive_at_shop()
	bw.advance(BattleWindow.ENTER_SECONDS)
	a.shopping_at = ""
	main._sync_battle_window()
	bw.advance(BattleWindow.LEAVE_SECONDS / 2.0)
	assert_eq(bw._shop_drawn, ItemCatalog.RARITY_SILVER, "still the shop they left, on its way out")
	assert_between(bw.shop_position().x, _shop_home().x + 1.0, bw.size.x)
	bw.advance(BattleWindow.LEAVE_SECONDS / 2.0)
	assert_eq(bw._shop_drawn, "", "gone")

func test_a_party_selected_mid_visit_is_shown_at_the_counter_straight_away():
	a.shopping_at = ItemCatalog.RARITY_BRONZE
	main.hud.inspect(a)
	main._sync_battle_window()
	assert_eq(bw.shop_position(), _shop_home(), "as everyone in a scene just started appears at once")

func test_a_visit_says_which_shop_while_it_lasts():
	var players: Dictionary = {}
	isolate(a, corridor(2), Vector2i(0, 0), players)
	a.shops[Vector2i(0, 0)] = ItemCatalog.RARITY_BRONZE
	a._start_shopping()
	assert_eq(a.shopping_at, ItemCatalog.RARITY_BRONZE)
	await wait_seconds(Shopping.SECONDS + 0.2)
	assert_eq(a.shopping_at, "")
