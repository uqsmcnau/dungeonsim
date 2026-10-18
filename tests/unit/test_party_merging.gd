extends DungeonTest

## Covers who can band together into a party (up to PartyOps.MAX_PARTY_SIZE)
## instead of fighting: Good and Neutral always merge with each other; Good
## and Evil never merge; Evil only merges with other Evil, and only if
## nobody in the combined group is confident it could solo the rest.

func before_each():
	load_main()

func test_good_can_always_party_with_good():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	a.stats.alignment = NpcStats.ALIGNMENT_GOOD
	b.stats.alignment = NpcStats.ALIGNMENT_GOOD
	assert_true(PartyOps.can_form_party_with(a, b))

func test_good_can_always_party_with_neutral():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	a.stats.alignment = NpcStats.ALIGNMENT_GOOD
	b.stats.alignment = NpcStats.ALIGNMENT_NEUTRAL
	assert_true(PartyOps.can_form_party_with(a, b))

func test_neutral_can_always_party_with_neutral():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	a.stats.alignment = NpcStats.ALIGNMENT_NEUTRAL
	b.stats.alignment = NpcStats.ALIGNMENT_NEUTRAL
	assert_true(PartyOps.can_form_party_with(a, b))

func test_good_never_parties_with_evil():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	a.stats.alignment = NpcStats.ALIGNMENT_GOOD
	b.stats.alignment = NpcStats.ALIGNMENT_EVIL
	assert_false(PartyOps.can_form_party_with(a, b))

func test_neutral_never_parties_with_evil():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	a.stats.alignment = NpcStats.ALIGNMENT_NEUTRAL
	b.stats.alignment = NpcStats.ALIGNMENT_EVIL
	assert_false(PartyOps.can_form_party_with(a, b))

func test_evenly_matched_evil_characters_can_party_up():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	a.stats.alignment = NpcStats.ALIGNMENT_EVIL
	b.stats.alignment = NpcStats.ALIGNMENT_EVIL
	set_stats(a, 5, 50, 10, 10)
	set_stats(b, 5, 50, 10, 10)
	# Identical stats come out just barely above a 50/50 win chance (the
	# damage formula gives the attacker a slightly higher bonus than the
	# defender's counter), which is exactly why the confidence bar is well
	# above 0.5 -- otherwise this exact case would wrongly refuse to merge.
	assert_true(PartyOps.can_form_party_with(a, b))

func test_dominant_evil_character_refuses_to_party_with_someone_it_could_solo():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	a.stats.alignment = NpcStats.ALIGNMENT_EVIL
	b.stats.alignment = NpcStats.ALIGNMENT_EVIL
	set_stats(a, 5, 50, 10, 10)
	set_stats(b, 50, 500, 80, 80)
	assert_false(PartyOps.can_form_party_with(a, b))

func test_merge_refused_once_it_would_exceed_the_party_size_cap():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	var extra1: NpcAgent = main.npcs[2]
	var extra2: NpcAgent = main.npcs[3]
	var extra3: NpcAgent = main.npcs[4]
	var extra4: NpcAgent = main.npcs[5]
	for n in [a, b, extra1, extra2, extra3, extra4]:
		n.stats.alignment = NpcStats.ALIGNMENT_EVIL
		set_stats(n, 5, 50, 10, 10)

	a.party = [a, extra1, extra2, extra4]  # a already leads a party of 4
	for m in a.party:
		m.is_party_leader = (m == a)
	b.party = [b, extra3]  # b already leads a party of 2 -- 4+2=6 > cap of 5
	extra3.party = b.party
	extra3.is_party_leader = false

	assert_false(PartyOps.can_form_party_with(a, b))
	assert_eq(PartyOps.MAX_PARTY_SIZE, 5)

func test_merge_allowed_exactly_at_the_party_size_cap():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	var extra1: NpcAgent = main.npcs[2]
	var extra2: NpcAgent = main.npcs[3]
	var extra3: NpcAgent = main.npcs[4]
	for n in [a, b, extra1, extra2, extra3]:
		n.stats.alignment = NpcStats.ALIGNMENT_GOOD
		set_stats(n, 5, 50, 10, 10)

	a.party = [a, extra1, extra2, extra3]  # party of 4
	for m in a.party:
		m.is_party_leader = (m == a)
	# b is solo -- 4 + 1 = 5, exactly at the cap, not over it.
	assert_true(PartyOps.can_form_party_with(a, b))

func test_join_party_of_merges_arrays_and_demotes_the_joiner():
	var host: NpcAgent = main.npcs[0]
	var joiner: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(joiner, host)

	assert_false(joiner.is_party_leader, "the joiner should no longer lead its own party")
	assert_eq(joiner.party, host.party, "the joiner's party should now be the same shared array as the host's")
	assert_eq(host.party.size(), 2, "the host's party should have grown to include the joiner")
	assert_true(host.is_party_leader, "the host should remain the leader")

func test_living_party_reflects_all_living_members():
	var host: NpcAgent = main.npcs[0]
	var joiner: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(joiner, host)
	assert_eq(host.living_party().size(), 2)

func test_hud_shows_party_name_and_size_once_merged_and_omits_it_for_solo_characters():
	var host: NpcAgent = main.npcs[0]
	var joiner: NpcAgent = main.npcs[1]
	var solo: NpcAgent = main.npcs[2]
	PartyOps.join_party_of(joiner, host)
	main.hud.refresh_npc(host)
	main.hud.refresh_npc(joiner)
	main.hud.refresh_npc(solo)
	var expected := "Party: %s (2)" % host.party_name
	assert_eq(main.hud.rows[host]["party"].text, expected)
	assert_true(main.hud.rows[host]["party"].visible)
	assert_eq(main.hud.rows[joiner]["party"].text, expected, "every member's panel shows the same party")
	assert_false(main.hud.rows[solo]["party"].visible, "no party line for someone on their own")
