extends GutTest

## Covers the leaderboard's death grace period: a character that was
## visible on the leaderboard the moment it died keeps its (frozen, death-
## flashed) panel on screen for Hud.DEATH_GRACE_SECONDS before actually
## dropping off, rather than vanishing the instant it's removed from the
## living roster.

var main: Node

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())

func _rank_npcs_by_index(count: int) -> void:
	for i in range(main.npcs.size()):
		var npc: NpcAgent = main.npcs[i]
		npc.stats.strength = 1
		npc.stats.constitution = 1
		npc.stats.attack_bonus = 0
		npc.stats.defense_bonus = 0
		npc.stats.max_hp = 1
	for i in range(count):
		var npc: NpcAgent = main.npcs[i]
		npc.stats.attack_bonus = i * 10
		npc.stats.max_hp = 10 + i * 10

func test_a_leaderboard_death_stays_visible_immediately_after_dying():
	var n: int = main.npcs.size()
	_rank_npcs_by_index(n)
	main._process(0.0)
	var champion: NpcAgent = main.npcs[n - 1]
	assert_true(main.hud.rows[champion]["panel"].visible, "sanity: the champion should start out visible")

	champion._die()

	assert_true(main.hud.rows[champion]["panel"].visible, "the panel should stay visible right after death, not vanish instantly")
	assert_true(main.hud.dying.has(champion), "the champion should be tracked as being in its grace period")
	assert_string_contains(main.hud.rows[champion]["header"].text, "DEAD")

func test_leaderboard_updates_do_not_override_a_character_mid_grace_period():
	var n: int = main.npcs.size()
	_rank_npcs_by_index(n)
	main._process(0.0)
	var champion: NpcAgent = main.npcs[n - 1]
	champion._die()

	# Several real leaderboard recalculations happen while the champion is
	# still serving its grace period -- none of them should hide it, even
	# though it's no longer in main.npcs (the living roster) at all.
	for i in range(5):
		main._process(0.0)
	assert_true(main.hud.rows[champion]["panel"].visible, "should still be visible partway through its grace period")
	assert_true(main.hud.dying.has(champion))

func test_dying_keeps_reserving_its_leaderboard_slot_until_the_grace_period_ends():
	# While a leaderboard death is in its grace period, it keeps occupying
	# its slot in the combined ranking -- the next-strongest living
	# character must wait for that slot to actually free up rather than
	# being promoted the instant the dead one is removed from the living
	# roster (see Hud._update_leaderboard).
	var n: int = main.npcs.size()
	_rank_npcs_by_index(n)
	main._process(0.0)
	var champion: NpcAgent = main.npcs[n - 1]
	var next_in_line: NpcAgent = main.npcs[n - 1 - Hud.VISIBLE_HUD_COUNT]
	champion._die()
	main._process(0.0)

	assert_true(main.hud.rows[champion]["panel"].visible, "the dying champion should still show")
	assert_false(main.hud.rows[next_in_line]["panel"].visible, "the next-strongest living character must wait -- the champion's slot is still reserved during its grace period")

func test_dying_off_the_leaderboard_does_not_start_a_grace_period():
	var n: int = main.npcs.size()
	_rank_npcs_by_index(n)
	main._process(0.0)
	var weakling: NpcAgent = main.npcs[0]  # ranked last, never shown
	assert_false(main.hud.rows[weakling]["panel"].visible, "sanity: should start out hidden")

	weakling._die()

	assert_false(main.hud.dying.has(weakling), "a character that wasn't on the leaderboard shouldn't get a grace period")
	assert_false(main.hud.rows[weakling]["panel"].visible, "should stay hidden, same as before it died")
