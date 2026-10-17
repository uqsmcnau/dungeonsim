extends GutTest

## Covers NpcStats.add_xp's leveling math in isolation.

var stats: NpcStats

func before_each():
	stats = NpcStats.new()

func test_add_xp_below_threshold_does_not_level_up():
	var leveled: bool = stats.add_xp(stats.xp_to_next - 1)
	assert_false(leveled)
	assert_eq(stats.level, 1)

func test_add_xp_crossing_the_threshold_levels_up_exactly_once():
	var threshold: int = stats.xp_to_next
	var leveled: bool = stats.add_xp(threshold)
	assert_true(leveled)
	assert_eq(stats.level, 2)
	assert_eq(stats.xp, 0, "exactly enough xp should leave no remainder")

func test_add_xp_remainder_carries_over_correctly():
	var threshold: int = stats.xp_to_next
	stats.add_xp(threshold + 3)
	assert_eq(stats.level, 2)
	assert_eq(stats.xp, 3)

func test_level_up_fully_restores_hp_and_mp():
	stats.hp = 1
	stats.mp = 0
	stats.add_xp(stats.xp_to_next)
	assert_eq(stats.hp, stats.max_hp)
	assert_eq(stats.mp, stats.max_mp)

func test_level_up_increases_max_hp_and_max_mp_by_fixed_amounts():
	var before_max_hp: int = stats.max_hp
	var before_max_mp: int = stats.max_mp
	stats.add_xp(stats.xp_to_next)
	assert_eq(stats.max_hp, before_max_hp + 6)
	assert_eq(stats.max_mp, before_max_mp + 2)

func test_level_up_raises_the_xp_threshold_for_the_next_one():
	var before: int = stats.xp_to_next
	stats.add_xp(before)
	assert_eq(stats.xp_to_next, int(before * 1.5))

func test_level_up_boosts_exactly_one_random_ability_by_one_point():
	var before_total: int = stats.strength + stats.dexterity + stats.constitution \
		+ stats.intelligence + stats.wisdom + stats.charisma
	stats.add_xp(stats.xp_to_next)
	var after_total: int = stats.strength + stats.dexterity + stats.constitution \
		+ stats.intelligence + stats.wisdom + stats.charisma
	assert_eq(after_total, before_total + 1)

func test_a_large_xp_gain_applies_every_level_up_it_covers():
	# Compute exactly how much xp it takes to go from level 1 to level 4,
	# then confirm that single gain lands exactly on level 4 with no xp left.
	var total_needed := 0
	var threshold: int = stats.xp_to_next
	for i in range(3):
		total_needed += threshold
		threshold = int(threshold * 1.5)

	var leveled: bool = stats.add_xp(total_needed)

	assert_true(leveled)
	assert_eq(stats.level, 4)
	assert_eq(stats.xp, 0)

func test_zero_xp_never_levels_up():
	assert_false(stats.add_xp(0))
	assert_eq(stats.level, 1)
