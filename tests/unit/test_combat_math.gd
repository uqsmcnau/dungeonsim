extends GutTest

## Covers CombatMath's hit chance, damage, and win-chance estimation --
## pure functions over two NpcStats blocks, no scene instantiation needed.

func _stats(level: int, hp: int, strength: int, constitution: int, dexterity: int = 10) -> NpcStats:
	var s := NpcStats.new()
	s.level = level
	s.hp = hp
	s.max_hp = hp
	s.strength = strength
	s.constitution = constitution
	s.dexterity = dexterity
	return s

# ============================== Hit chance =================================

func test_combat_rules_hit_chance_clamps_to_its_minimum():
	var chance: float = CombatRules.hit_chance(0.0, 1000.0)
	assert_eq(chance, CombatRules.MIN_HIT_CHANCE)

func test_combat_rules_hit_chance_clamps_to_its_maximum():
	var chance: float = CombatRules.hit_chance(1000.0, 0.0)
	assert_eq(chance, CombatRules.MAX_HIT_CHANCE)

func test_hit_chance_against_uses_attackers_accuracy_and_defenders_evasion():
	var attacker := _stats(1, 10, 5, 5, 10)  # accuracy 0.2
	var defender := _stats(1, 10, 5, 5, 10)  # evasion 0.2
	var expected: float = CombatRules.hit_chance(attacker.accuracy(), defender.evasion())
	assert_eq(CombatMath.hit_chance_against(attacker, defender), expected)

func test_hit_chance_against_is_not_symmetric_when_dexterity_differs():
	var sharpshooter := _stats(1, 10, 5, 5, 20)  # accuracy 0.4
	var klutz := _stats(1, 10, 5, 5, 0)  # accuracy/evasion 0.0
	assert_gt(CombatMath.hit_chance_against(sharpshooter, klutz), CombatMath.hit_chance_against(klutz, sharpshooter))

# ================================ Damage ====================================

func test_damage_dealt_per_hit_floors_at_one_against_heavy_defense():
	var me := _stats(1, 20, 1, 1)  # attack_power = 1 + 1 = 2
	var tough_opponent := _stats(1, 9999, 1, 500)  # defense 250, far exceeds our attack
	assert_eq(CombatMath.damage_dealt_per_hit(me, tough_opponent), 1.0)

func test_damage_taken_per_hit_floors_at_one_against_heavy_defense():
	var me := _stats(1, 20, 1, 500)  # our defense 250
	var weak_opponent := _stats(1, 10, 1, 1)  # attack_power = 2
	assert_eq(CombatMath.damage_taken_per_hit(me, weak_opponent), 1.0)

func test_damage_dealt_per_hit_scales_with_attack_power():
	var me := _stats(10, 20, 20, 1)  # attack_power = 20 + 10 = 30
	var opponent := _stats(1, 10, 1, 1)  # defense ~0
	assert_almost_eq(CombatMath.damage_dealt_per_hit(me, opponent), 30.0 + CombatMath.OUTGOING_DAMAGE_BONUS, 0.01)

func test_dealt_and_taken_use_different_bonuses_for_the_same_matchup():
	# The asymmetry (1.5 vs 1.0) is deliberate -- see CombatMath's own doc
	# comment and test_win_chance_against_an_identical_opponent_is_just_above_half.
	var me := _stats(5, 50, 10, 10)
	var opponent := _stats(5, 50, 10, 10)  # identical, so defense cancels out
	var dealt: float = CombatMath.damage_dealt_per_hit(me, opponent)
	var taken: float = CombatMath.damage_taken_per_hit(me, opponent)
	assert_almost_eq(dealt - taken, CombatMath.OUTGOING_DAMAGE_BONUS - CombatMath.INCOMING_DAMAGE_BONUS, 0.01)

# ============================== Win chance ===================================

func test_win_chance_is_clamped_to_its_upper_bound_against_a_trivial_opponent():
	var me := _stats(50, 500, 80, 80)
	var trivial := _stats(1, 1, 1, 1)
	assert_almost_eq(CombatMath.win_chance_against(me, trivial), 0.95, 0.001)

func test_win_chance_is_clamped_to_its_lower_bound_against_an_overwhelming_opponent():
	var me := _stats(1, 1, 1, 1)
	var overwhelming := _stats(50, 500, 80, 80)
	assert_almost_eq(CombatMath.win_chance_against(me, overwhelming), 0.05, 0.001)

func test_win_chance_against_an_identical_opponent_is_just_above_half():
	# The damage formulas give the attacker a slightly higher bonus than the
	# defender's counter (+1.5 vs +1.0), so identical stats come out just
	# barely favoring "self" rather than landing on an exact 50/50 --
	# this is exactly why the party-merge confidence bar sits well above 0.5
	# (see PartyOps.SOLO_CONFIDENCE_THRESHOLD) rather than reusing this value.
	var me := _stats(5, 50, 10, 10)
	var twin := _stats(5, 50, 10, 10)
	var chance: float = CombatMath.win_chance_against(me, twin)
	assert_gt(chance, 0.5)
	assert_lt(chance, 0.55)

func test_win_chance_increases_as_the_opponent_gets_weaker():
	var me := _stats(5, 50, 10, 10)
	var medium := _stats(5, 50, 10, 10)
	var weaker := _stats(1, 10, 3, 3)
	assert_gt(CombatMath.win_chance_against(me, weaker), CombatMath.win_chance_against(me, medium))

# ================================ Decisions ===================================

func test_decide_fight_against_an_overwhelming_opponent_is_effectively_never_taken():
	var me := _stats(1, 1, 1, 1)
	var overwhelming := _stats(50, 500, 80, 80)
	var fought := 0
	for i in range(200):
		if CombatMath.decide_fight(me, overwhelming):
			fought += 1
	assert_lt(fought, 30, "a near-hopeless fight should be picked only rarely (~5% of the time)")

func test_decide_fight_against_a_trivial_opponent_is_effectively_always_taken():
	var me := _stats(50, 500, 80, 80)
	var trivial := _stats(1, 1, 1, 1)
	var fought := 0
	for i in range(200):
		if CombatMath.decide_fight(me, trivial):
			fought += 1
	assert_gt(fought, 170, "an easy fight should be picked almost every time (~95%)")
