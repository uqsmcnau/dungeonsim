extends GutTest

## Covers the combat math shared by monster fights and PvP fights -- hit
## chance, damage, and win-chance estimation -- using a single NpcAgent
## instantiated directly (no need for the full Main scene).

const NPC_SCENE: PackedScene = preload("res://scenes/NPC.tscn")

var npc: NpcAgent

func before_each():
	npc = add_child_autofree(NPC_SCENE.instantiate())
	npc.setup(Vector2i(1, 1), Vector2i(2, 2), [[0, 0], [0, 0]], 48.0, Color.WHITE, "Test", {}, {}, {}, {})

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

func test_hit_chance_against_uses_our_accuracy_and_their_evasion():
	npc.stats.dexterity = 10  # accuracy 0.2
	var opponent := _stats(1, 10, 5, 5, 10)  # evasion 0.2
	var expected: float = CombatRules.hit_chance(npc.stats.accuracy(), opponent.evasion())
	assert_eq(npc._hit_chance_against(opponent), expected)

func test_hit_chance_from_uses_their_accuracy_and_our_evasion():
	npc.stats.dexterity = 10
	var opponent := _stats(1, 10, 5, 5, 20)  # accuracy 0.4
	var expected: float = CombatRules.hit_chance(opponent.accuracy(), npc.stats.evasion())
	assert_eq(npc._hit_chance_from(opponent), expected)

# ================================ Damage ====================================

func test_damage_per_hit_dealt_floors_at_one_against_heavy_defense():
	npc.stats = _stats(1, 20, 1, 1)  # attack_power = 1 + 1 = 2
	var tough_opponent := _stats(1, 9999, 1, 500)  # defense 250, far exceeds our attack
	assert_eq(npc._damage_per_hit_dealt(tough_opponent), 1.0)

func test_damage_per_hit_taken_floors_at_one_against_heavy_defense():
	npc.stats = _stats(1, 20, 1, 500)  # our defense 250
	var weak_opponent := _stats(1, 10, 1, 1)  # attack_power = 2
	assert_eq(npc._damage_per_hit_taken(weak_opponent), 1.0)

func test_damage_per_hit_dealt_scales_with_attack_power():
	npc.stats = _stats(10, 20, 20, 1)  # attack_power = 20 + 10 = 30
	var opponent := _stats(1, 10, 1, 1)  # defense ~0
	assert_almost_eq(npc._damage_per_hit_dealt(opponent), 30.0 + 1.5, 0.01)

# ============================== Win chance ===================================

func test_win_chance_is_clamped_to_its_upper_bound_against_a_trivial_opponent():
	npc.stats = _stats(50, 500, 80, 80)
	var trivial := _stats(1, 1, 1, 1)
	assert_almost_eq(npc._win_chance_against(trivial), 0.95, 0.001)

func test_win_chance_is_clamped_to_its_lower_bound_against_an_overwhelming_opponent():
	npc.stats = _stats(1, 1, 1, 1)
	var overwhelming := _stats(50, 500, 80, 80)
	assert_almost_eq(npc._win_chance_against(overwhelming), 0.05, 0.001)

func test_win_chance_against_an_identical_opponent_is_just_above_half():
	# The damage formulas give the attacker a slightly higher bonus than the
	# defender's counter (+1.5 vs +1.0), so identical stats come out just
	# barely favoring "self" rather than landing on an exact 50/50 --
	# this is exactly why the party-merge confidence bar sits well above 0.5
	# (see NpcAgent.SOLO_CONFIDENCE_THRESHOLD) rather than reusing this value.
	npc.stats = _stats(5, 50, 10, 10)
	var twin := _stats(5, 50, 10, 10)
	var chance: float = npc._win_chance_against(twin)
	assert_gt(chance, 0.5)
	assert_lt(chance, 0.55)

func test_win_chance_increases_as_the_opponent_gets_weaker():
	npc.stats = _stats(5, 50, 10, 10)
	var medium := _stats(5, 50, 10, 10)
	var weaker := _stats(1, 10, 3, 3)
	assert_gt(npc._win_chance_against(weaker), npc._win_chance_against(medium))

# ================================ Decisions ===================================

func test_decide_fight_against_an_overwhelming_opponent_is_effectively_never_taken():
	npc.stats = _stats(1, 1, 1, 1)
	var overwhelming := _stats(50, 500, 80, 80)
	var fought := 0
	for i in range(200):
		if npc._decide_fight(overwhelming):
			fought += 1
	assert_lt(fought, 30, "a near-hopeless fight should be picked only rarely (~5% of the time)")

func test_decide_fight_against_a_trivial_opponent_is_effectively_always_taken():
	npc.stats = _stats(50, 500, 80, 80)
	var trivial := _stats(1, 1, 1, 1)
	var fought := 0
	for i in range(200):
		if npc._decide_fight(trivial):
			fought += 1
	assert_gt(fought, 170, "an easy fight should be picked almost every time (~95%)")
