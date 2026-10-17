extends GutTest

## Covers who can band together into a party (up to PartyOps.MAX_PARTY_SIZE)
## instead of fighting: Good and Neutral always merge with each other; Good
## and Evil never merge; Evil only merges with other Evil, and only if
## nobody in the combined group is confident it could solo the rest.

var main: Node

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())

func _set_stats(npc: NpcAgent, level: int, hp: int, strength: int, constitution: int) -> void:
	npc.stats.level = level
	npc.stats.hp = hp
	npc.stats.max_hp = hp
	npc.stats.strength = strength
	npc.stats.constitution = constitution
	npc.stats.mp = 0

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
	_set_stats(a, 5, 50, 10, 10)
	_set_stats(b, 5, 50, 10, 10)
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
	_set_stats(a, 5, 50, 10, 10)
	_set_stats(b, 50, 500, 80, 80)
	assert_false(PartyOps.can_form_party_with(a, b))

func test_merge_refused_once_it_would_exceed_the_party_size_cap():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	var extra1: NpcAgent = main.npcs[2]
	var extra2: NpcAgent = main.npcs[3]
	var extra3: NpcAgent = main.npcs[4]
	for n in [a, b, extra1, extra2, extra3]:
		n.stats.alignment = NpcStats.ALIGNMENT_EVIL
		_set_stats(n, 5, 50, 10, 10)

	a.party = [a, extra1, extra2]  # a already leads a party of 3
	for m in a.party:
		m.is_party_leader = (m == a)
	b.party = [b, extra3]  # b already leads a party of 2 -- 3+2=5 > cap of 4
	extra3.party = b.party
	extra3.is_party_leader = false

	assert_false(PartyOps.can_form_party_with(a, b))
	assert_eq(PartyOps.MAX_PARTY_SIZE, 4)

func test_merge_allowed_exactly_at_the_party_size_cap():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	var extra1: NpcAgent = main.npcs[2]
	var extra2: NpcAgent = main.npcs[3]
	for n in [a, b, extra1, extra2]:
		n.stats.alignment = NpcStats.ALIGNMENT_GOOD
		_set_stats(n, 5, 50, 10, 10)

	a.party = [a, extra1, extra2]  # party of 3
	for m in a.party:
		m.is_party_leader = (m == a)
	# b is solo -- 3 + 1 = 4, exactly at the cap, not over it.
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

func test_hud_shows_party_size_once_merged_and_omits_it_for_solo_characters():
	var host: NpcAgent = main.npcs[0]
	var joiner: NpcAgent = main.npcs[1]
	var solo: NpcAgent = main.npcs[2]
	PartyOps.join_party_of(joiner, host)
	main.hud.refresh_npc(host)
	main.hud.refresh_npc(solo)
	assert_string_contains(main.hud.rows[host]["header"].text, "(Party of 2)")
	assert_false(main.hud.rows[solo]["header"].text.contains("(Party of"))
