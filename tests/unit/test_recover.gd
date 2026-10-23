extends DungeonTest

## Covers Recover being cast only between fights (see
## NpcAgent._see_to_ourselves), never mid-fight (see
## NpcAgent.choose_combat_action) -- where a Health Potion is the only
## healing -- and spellcasters, with no Recover to keep mana back for,
## spending the last of it on their attack spells.

var a: NpcAgent
var foe: NpcStats

func before_each():
	load_main()
	a = main.npcs[0]
	set_stats(a, 5, 40, 10, 10)
	a.stats.inventory.clear()
	a.stats.known_spells.clear()
	foe = NpcStats.new()

func test_not_mid_fight():
	a.stats.hp = 5
	a.stats.mp = 50
	assert_eq(a.choose_combat_action(foe), CombatRules.ATTACK, "fighting on, however much mana it has")

func test_a_potion_still_heals_mid_fight():
	a.stats.hp = 5
	a.stats.mp = 50
	a.stats.inventory["Health Potion"] = 1
	assert_eq(a.choose_combat_action(foe), CombatRules.POTION)

func test_but_between_fights_it_casts_recover():
	a.stats.hp = 5
	a.stats.mp = 50
	assert_true(a._see_to_ourselves())
	assert_eq(a.current_action, "Casting Recover")

func test_a_spellcaster_spends_its_last_mana_on_a_spell():
	set_stats(a, 5, 40, 1, 10)  # a weakling with a sword
	a.stats.intelligence = 18
	a.stats.learn_spell("spark")
	a.stats.mp = NpcStats.SPARK_MP_COST
	assert_gt(float(a.stats.spark_power()), CombatMath.expected_damage_dealt(a.stats, foe), "sanity: Spark hits harder")
	assert_eq(a.choose_combat_action(foe), CombatRules.SPARK, "nothing to keep back for a Recover mid-fight")

