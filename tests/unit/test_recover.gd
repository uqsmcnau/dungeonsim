extends DungeonTest

## Covers Recover being cast only between fights (see
## NpcAgent._see_to_ourselves), never mid-fight (see
## CombatActions.choose) -- where a Health Potion is the only
## healing -- and spellcasters, with no Recover to keep mana back for,
## spending the last of it on their attack spells. And between fights the
## whole party sees to itself, not just its leader.

var a: NpcAgent
var b: NpcAgent
var foe: NpcStats
var players: Dictionary = {}

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
	assert_eq(CombatActions.choose(a.stats, foe), CombatRules.ATTACK, "fighting on, however much mana it has")

func test_a_potion_still_heals_mid_fight():
	a.stats.hp = 5
	a.stats.mp = 50
	a.stats.inventory["Health Potion"] = 1
	assert_eq(CombatActions.choose(a.stats, foe), CombatRules.POTION)

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
	assert_eq(CombatActions.choose(a.stats, foe), CombatRules.SPARK, "nothing to keep back for a Recover mid-fight")

# ============================ The whole party ==============================

## A, healthy, leads B on a maze of their own -- no monsters, no storm.
func _party() -> void:
	b = main.npcs[1]
	var g := corridor(3)
	isolate(a, g, Vector2i(1, 0), players)
	isolate(b, g, Vector2i(1, 0), {})
	set_stats(b, 5, 40, 10, 10)
	b.stats.inventory.clear()
	a.party.append(b)
	b.party = a.party
	b.is_party_leader = false
	a.stats.mp = 50

func test_a_hurt_party_mate_stops_the_party():
	_party()
	b.stats.hp = 5
	b.stats.mp = 50
	assert_true(a._see_to_ourselves())
	assert_eq(b.current_action, "Casting Recover")
	assert_eq(a.current_action, "Waiting for the party")
	assert_true(a.is_moving, "held while B casts")

func test_it_moves_on_once_theyre_done():
	_party()
	b.stats.hp = 5
	b.stats.mp = 50
	a._see_to_ourselves()
	await wait_seconds(NpcAgent.RECOVER_CAST_SECONDS + 0.2)
	assert_gt(b.stats.hp, 5, "B's healed")
	assert_lt(b.stats.mp, 50, "and paid for it in mana")

func test_everyone_hurt_heals_at_once():
	_party()
	a.stats.hp = 5
	b.stats.hp = 5
	b.stats.inventory["Health Potion"] = 1
	b.stats.mp = 0
	a._see_to_ourselves()
	assert_eq(a.current_action, "Casting Recover")
	assert_eq(b.current_action, "Drinking Health Potion", "no mana for Recover, but a potion")

func test_with_no_mana_or_potion_the_party_rests_with_them():
	_party()
	b.stats.hp = 5
	b.stats.mp = 0
	assert_true(a._see_to_ourselves())
	assert_eq(a.current_action, NpcAgent.RESTING)
	assert_false(a.is_moving, "waiting on B's mana, ready to set off once healed")

func test_a_healthy_party_carries_on():
	_party()
	assert_false(a._see_to_ourselves())
