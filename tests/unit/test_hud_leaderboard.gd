extends DungeonTest

## Covers the HUD leaderboard: only the top Hud.VISIBLE_HUD_COUNT living
## characters by combat power get their panel shown, and the set updates
## live as combat power and death change who qualifies. A death that was
## on the leaderboard gets a grace period before its panel actually
## disappears -- see test_death_grace_period.gd for that behavior in detail.

func before_each():
	load_main()

func test_only_the_top_ranked_panels_are_visible():
	rank_npcs_by_index(main.npcs.size())
	main._process(0.0)

	var visible_count := 0
	for npc in main.hud.rows:
		if main.hud.rows[npc]["panel"].visible:
			visible_count += 1
	assert_eq(visible_count, Hud.VISIBLE_HUD_COUNT)

func test_the_strongest_characters_specifically_are_the_ones_shown():
	var n: int = main.npcs.size()
	rank_npcs_by_index(n)
	main._process(0.0)

	# npcs[n-1] down to npcs[n-4] are the strongest four.
	for i in range(n - Hud.VISIBLE_HUD_COUNT, n):
		assert_true(main.hud.rows[main.npcs[i]]["panel"].visible, "npc %d should be in the top %d" % [i, Hud.VISIBLE_HUD_COUNT])
	for i in range(0, n - Hud.VISIBLE_HUD_COUNT):
		assert_false(main.hud.rows[main.npcs[i]]["panel"].visible, "npc %d should be ranked out of the top %d" % [i, Hud.VISIBLE_HUD_COUNT])

func test_header_shows_rank_one_for_the_strongest_character():
	var n: int = main.npcs.size()
	rank_npcs_by_index(n)
	main._process(0.0)
	var strongest: NpcAgent = main.npcs[n - 1]
	assert_string_contains(main.hud.rows[strongest]["header"].text, "#1 ")

func test_a_death_off_the_leaderboard_stays_hidden():
	var n: int = main.npcs.size()
	rank_npcs_by_index(n)
	main._process(0.0)
	var weakling: NpcAgent = main.npcs[0]  # ranked last, never shown
	assert_false(main.hud.rows[weakling]["panel"].visible, "sanity: should start out hidden")

	weakling.die()
	main._process(0.0)

	assert_false(main.hud.rows[weakling]["panel"].visible,
		"a death that was never on the leaderboard should just stay hidden, same as before it died")

func test_a_lower_ranked_character_is_not_promoted_while_the_dead_ones_slot_is_still_reserved():
	# A death that was on the leaderboard keeps occupying its slot for its
	# grace period (see test_death_grace_period.gd) -- so killing the
	# current #1 must NOT immediately promote the next-strongest living
	# character. That only happens once the dead one's slot actually frees
	# up, covered by test_a_lower_ranked_character_is_promoted_once_the_dead_ones_slot_frees_up.
	var n: int = main.npcs.size()
	rank_npcs_by_index(n)
	main._process(0.0)
	var just_outside: NpcAgent = main.npcs[n - 1 - Hud.VISIBLE_HUD_COUNT]
	assert_false(main.hud.rows[just_outside]["panel"].visible, "sanity: should start out of the top %d" % Hud.VISIBLE_HUD_COUNT)

	main.npcs[n - 1].die()  # remove the current #1
	main._process(0.0)

	assert_false(main.hud.rows[just_outside]["panel"].visible,
		"should stay hidden -- the dead #1 is still reserving its slot during its grace period")

func test_a_lower_ranked_character_is_promoted_once_the_dead_ones_slot_frees_up():
	var n: int = main.npcs.size()
	rank_npcs_by_index(n)
	main._process(0.0)
	var just_outside: NpcAgent = main.npcs[n - 1 - Hud.VISIBLE_HUD_COUNT]
	var champion: NpcAgent = main.npcs[n - 1]
	champion.die()
	main._process(0.0)
	assert_false(main.hud.rows[just_outside]["panel"].visible, "sanity: still reserved right after death")

	# Simulate the grace period actually ending (see test_death_grace_period.gd
	# for why the real timer isn't exercised directly here).
	main.hud.dying.erase(champion)
	main._process(0.0)

	assert_true(main.hud.rows[just_outside]["panel"].visible,
		"once the dead #1's slot is actually freed, the next-strongest living character should be promoted into it")
