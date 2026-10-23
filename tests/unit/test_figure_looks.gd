extends DungeonTest

## Covers how a player's figure looks in the battle window in the gear
## they're wearing (FigureLook), and the figure keeping up as it changes.

var bw: BattleWindow
var a: NpcAgent
var b: NpcAgent

func before_each():
	load_main()
	bw = main.hud.battle_window
	a = main.npcs[0]
	b = main.npcs[1]

## Puts `party` and `foes` in the window directly, as GameManager would.
func _scene(party: Array, foes: Array, status: String = "Exploring", on_the_move: bool = false) -> void:
	bw.show_fight(party, foes, status, on_the_move)

# ================================== Gear ==================================

func _wearing(items: Array) -> NpcStats:
	var stats := NpcStats.new()
	for item in items:
		stats.acquire_item(item)
	return stats

func test_nothing_worn_is_a_bare_fisted_tunic():
	var look := FigureLook.of(NpcStats.new())
	assert_eq([look.weapon, look.off_hand, look.armor], ["", "", ""])
	for part in ["helmet", "gold_helm", "boots", "winged", "amulet", "ring", "might"]:
		assert_false(look.get(part), part)

func test_everything_worn_shows():
	var look := FigureLook.of(_wearing([
		"Iron Sword", "Shield", "Leather Armor", "Helmet", "Leather Boots", "Sage's Amulet", "Silver Ring",
	]))
	assert_eq(look.weapon, "iron_sword")
	assert_eq(look.off_hand, "shield")
	assert_eq(look.armor, "leather")
	for part in ["helmet", "boots", "amulet", "ring"]:
		assert_true(look.get(part), part)

func test_silver_gear_looks_the_part():
	var look := FigureLook.of(_wearing(["Steel Sword", "Silver Shield", "Chainmail"]))
	assert_eq(look.weapon, "steel_sword")
	assert_eq(look.off_hand, "silver_shield")
	assert_eq(look.armor, "chainmail")

func test_gold_gear_looks_the_part():
	var look := FigureLook.of(_wearing([
		"Mithril Sword", "Aegis Shield", "Plate Armor", "Golden Helm", "Winged Boots", "Ring of Might",
	]))
	assert_eq(look.weapon, "mithril_sword")
	assert_eq(look.off_hand, "aegis")
	assert_eq(look.armor, "plate")
	for part in ["helmet", "gold_helm", "boots", "winged", "might"]:
		assert_true(look.get(part), part)
	assert_eq(FigureLook.of(_wearing(["Mithril Sword", "Archmage's Staff"])).off_hand, "staff")

func test_the_best_sword_goes_in_front():
	var look := FigureLook.of(_wearing(["Steel Sword", "Mithril Sword"]))
	assert_eq(look.weapon, "mithril_sword")
	assert_eq(look.off_hand, "iron_sword", "the other over the shoulder")

func test_a_tome_is_held_in_the_off_hand():
	assert_eq(FigureLook.of(_wearing(["Arcane Tome"])).off_hand, "tome")
	assert_eq(FigureLook.of(_wearing(["Arcane Tome"])).weapon, "", "no sword: it's held out in front instead")

func test_two_swords_carry_both():
	var look := FigureLook.of(_wearing(["Iron Sword", "Steel Sword"]))
	assert_eq(look.weapon, "steel_sword", "the better one in front")
	assert_eq(look.off_hand, "iron_sword")

func test_new_gear_shows_on_their_figure():
	a.stats.equipped.clear()
	_scene([a], [])
	assert_false(bw.fighter_of(a).look.helmet)
	a.stats.acquire_item("Helmet")
	_scene([a], [])
	assert_true(bw.fighter_of(a).look.helmet)

func test_a_rival_players_gear_shows_too():
	b.stats.equipped.clear()
	b.stats.acquire_item("Steel Sword")
	_scene([a], [b])
	assert_eq(bw.fighter_of(b).look.weapon, "steel_sword")
