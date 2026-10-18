extends DungeonTest

## Covers randomly generated, alignment-flavoured party names (PartyNames)
## and how they're handed out when parties form and merge.

const SAMPLES := 300
const FILLER := ["The", "of", "the"]

func before_each():
	load_main()

func _all_words(alignment: String) -> Dictionary:
	var result: Dictionary = {}
	for list in PartyNames.WORDS[alignment].values():
		for w in list:
			result[w] = true
	return result

func _uses_only_words_from(party_name: String, alignment: String) -> bool:
	var allowed := _all_words(alignment)
	for w in party_name.split(" "):
		if not FILLER.has(w) and not allowed.has(w):
			return false
	return true

# ============================== Generator =================================

func test_names_only_use_their_own_alignments_words():
	for alignment in PartyNames.WORDS:
		for i in range(SAMPLES):
			var party_name := PartyNames.generate(alignment)
			assert_true(_uses_only_words_from(party_name, alignment), "%s name '%s' strayed outside its word lists" % [alignment, party_name])
			if not _uses_only_words_from(party_name, alignment):
				return

func test_evil_names_never_borrow_good_only_words():
	var evil := _all_words(NpcStats.ALIGNMENT_EVIL)
	var good_only: Array = _all_words(NpcStats.ALIGNMENT_GOOD).keys().filter(func(w): return not evil.has(w))
	for i in range(SAMPLES):
		var party_name := PartyNames.generate(NpcStats.ALIGNMENT_EVIL)
		for w in party_name.split(" "):
			assert_false(good_only.has(w), "an Evil party shouldn't be called '%s'" % party_name)

func test_every_template_turns_up():
	var seen := {"of the": false, "The X Group": false, "The X Object Group": false}
	for i in range(SAMPLES):
		var party_name := PartyNames.generate(NpcStats.ALIGNMENT_NEUTRAL)
		if party_name.contains(" of the "):
			seen["of the"] = true
		elif party_name.split(" ").size() == 3:
			seen["The X Group"] = true
		elif party_name.split(" ").size() == 4:
			seen["The X Object Group"] = true
	for template in seen:
		assert_true(seen[template], "template '%s' never came up in %d names" % [template, SAMPLES])

func test_names_vary():
	var names: Dictionary = {}
	for i in range(50):
		names[PartyNames.generate(NpcStats.ALIGNMENT_GOOD)] = true
	assert_gt(names.size(), 30, "50 names should be mostly distinct")

func test_silly_names_turn_up():
	var silly := ["Fluffy", "Teapot", "Huggers", "Soggy", "Turnip", "Committee", "Grumpy", "Spork", "Goons"]
	var found := false
	for i in range(SAMPLES):
		for alignment in PartyNames.WORDS:
			for w in PartyNames.generate(alignment).split(" "):
				found = found or silly.has(w)
	assert_true(found, "in %d names of each alignment, not one silly word" % SAMPLES)

func test_every_word_is_a_single_word():
	# Combining names relies on taking them apart word by word.
	for alignment in PartyNames.WORDS:
		for list in PartyNames.WORDS[alignment].values():
			for w in list:
				assert_false(w.contains(" "), "'%s' should be one word" % w)

# ============================== Combining =================================

func test_every_generated_name_can_be_taken_apart():
	for alignment in PartyNames.WORDS:
		for i in range(SAMPLES):
			var party_name := PartyNames.generate(alignment)
			var parts := PartyNames.parse(party_name)
			assert_false(parts.is_empty(), "couldn't parse '%s'" % party_name)
			if parts.is_empty():
				return
			assert_eq(PartyNames._format(parts["group"], parts["descriptor"], parts["object"], parts["of_the"]), party_name, "and put back together")

func test_combining_takes_the_hosts_group_and_a_word_of_the_joiners():
	assert_eq(PartyNames.combine("Order of the Silver Ring", "The Crimson Vanguard"), "Order of the Crimson Ring")
	assert_eq(PartyNames.combine("The Silver Vanguard", "Cabal of the Skull"), "The Silver Skull Vanguard")
	assert_eq(PartyNames.combine("The Iron Lantern Company", "The Soggy Turnip Committee"), "The Soggy Lantern Company")
	assert_eq(PartyNames.combine("Order of the Ring", "Cabal of the Skull"), "Order of the Skull")
	assert_eq(PartyNames.combine("The Silver Vanguard", "The Crimson Cabal"), "The Crimson Vanguard")

func test_combining_avoids_just_keeping_the_hosts_name():
	# They share "Silver" -- the joiner's object brings something new instead.
	assert_eq(PartyNames.combine("Order of the Silver Ring", "The Silver Skull Cabal"), "Order of the Silver Skull")

func test_combined_names_can_be_combined_again():
	var once := PartyNames.combine("Order of the Silver Ring", "The Crimson Vanguard")
	assert_eq(PartyNames.combine(once, "The Fluffy Muffin Squad"), "Order of the Fluffy Ring")

func test_names_that_dont_fit_the_templates_cant_be_combined():
	assert_eq(PartyNames.combine("The Old Guard", "Bob's Mates"), "")
	assert_eq(PartyNames.combine("Bob's Mates", "The Crimson Vanguard"), "")
	assert_eq(PartyNames.combine("Order of the Very Shiny Ring", "The Crimson Vanguard"), "")

# ============================ Forming parties =============================

func test_forming_a_party_names_it_after_the_hosts_alignment():
	var host: NpcAgent = main.npcs[0]
	var joiner: NpcAgent = main.npcs[1]
	host.stats.alignment = NpcStats.ALIGNMENT_EVIL
	joiner.stats.alignment = NpcStats.ALIGNMENT_EVIL
	PartyOps.join_party_of(joiner, host)

	assert_ne(host.party_name, "")
	assert_true(_uses_only_words_from(host.party_name, NpcStats.ALIGNMENT_EVIL), "'%s' should be an Evil-flavoured name" % host.party_name)
	assert_eq(joiner.party_name, host.party_name, "every member shares the name")


func _two_named_parties(alignment: String = NpcStats.ALIGNMENT_GOOD) -> Array:
	var host: NpcAgent = main.npcs[0]
	var host_mate: NpcAgent = main.npcs[1]
	var joiner: NpcAgent = main.npcs[2]
	var joiner_mate: NpcAgent = main.npcs[3]
	for npc in [host, host_mate, joiner, joiner_mate]:
		npc.stats.alignment = alignment
	PartyOps.join_party_of(host_mate, host)
	PartyOps.join_party_of(joiner_mate, joiner)
	return [host, host_mate, joiner, joiner_mate]

func test_merging_two_named_parties_combines_their_names():
	var four := _two_named_parties()
	var host: NpcAgent = four[0]
	var joiner: NpcAgent = four[2]
	host.party_name = "Order of the Silver Ring"
	joiner.party_name = "The Crimson Vanguard"

	PartyOps.join_party_of(joiner, host)

	for npc in four:
		assert_eq(npc.party_name, "Order of the Crimson Ring", "%s should go by the combined name" % npc.npc_name)

func test_generated_party_names_always_combine_with_a_word_from_each():
	var four := _two_named_parties()
	var host: NpcAgent = four[0]
	var joiner: NpcAgent = four[2]
	var host_name := host.party_name
	var joiner_name := joiner.party_name

	PartyOps.join_party_of(joiner, host)

	var words := host.party_name.split(" ")
	assert_true(words.has(PartyNames.parse(host_name)["group"]), "'%s' keeps the host's group (from '%s')" % [host.party_name, host_name])
	var parts := PartyNames.parse(joiner_name)
	assert_true(words.has(parts["descriptor"]) or words.has(parts["object"]), "'%s' has a word of '%s'" % [host.party_name, joiner_name])

func test_names_that_cant_be_combined_keep_the_hosts():
	var four := _two_named_parties()
	var host: NpcAgent = four[0]
	var joiner: NpcAgent = four[2]
	host.party_name = "Order of the Silver Ring"
	joiner.party_name = "Bob's Mates"

	PartyOps.join_party_of(joiner, host)

	assert_eq(host.party_name, "Order of the Silver Ring")
	assert_eq(joiner.party_name, "Order of the Silver Ring")

func test_single_player_joining_an_existing_party_keeps_the_partys_name():
	var host: NpcAgent = main.npcs[0]
	var host_mate: NpcAgent = main.npcs[1]
	var loner: NpcAgent = main.npcs[2]
	PartyOps.join_party_of(host_mate, host)
	var party_name := host.party_name

	PartyOps.join_party_of(loner, host)

	assert_eq(host.party_name, party_name)
	assert_eq(loner.party_name, party_name)

func test_existing_party_joining_a_single_player_keeps_the_partys_name():
	# The other way round: the lone player hosts (stays leader), but one
	# player tagging along shouldn't rename an established party.
	var loner: NpcAgent = main.npcs[0]
	var leader: NpcAgent = main.npcs[1]
	var mate: NpcAgent = main.npcs[2]
	for npc in [loner, leader, mate]:
		npc.stats.alignment = NpcStats.ALIGNMENT_GOOD
	PartyOps.join_party_of(mate, leader)
	var party_name := leader.party_name

	PartyOps.join_party_of(leader, loner)

	assert_true(loner.is_party_leader, "sanity: the loner hosted the merge")
	for npc in [loner, leader, mate]:
		assert_eq(npc.party_name, party_name, "%s should go by the existing party's name" % npc.npc_name)

func test_existing_party_joining_a_lone_survivor_keeps_its_own_name():
	# The survivor still has its old (fallen) party's name, but it's a single
	# player now -- the established party's name should win.
	var survivor: NpcAgent = main.npcs[0]
	var fallen: NpcAgent = main.npcs[1]
	var leader: NpcAgent = main.npcs[2]
	var mate: NpcAgent = main.npcs[3]
	for npc in [survivor, fallen, leader, mate]:
		npc.stats.alignment = NpcStats.ALIGNMENT_GOOD
	PartyOps.join_party_of(fallen, survivor)
	fallen.die()
	survivor.party_name = "The Old Guard"  # fixed, so it can't randomly match
	PartyOps.join_party_of(mate, leader)
	var party_name := leader.party_name

	PartyOps.join_party_of(leader, survivor)

	assert_eq(survivor.party_name, party_name)

func test_name_survives_the_leader_falling():
	var host: NpcAgent = main.npcs[0]
	var joiner: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(joiner, host)
	var party_name := host.party_name
	host.die()

	assert_true(joiner.is_party_leader, "sanity: the joiner takes over")
	assert_eq(joiner.party_name, party_name)

func test_lone_survivor_carries_the_name_into_a_new_party():
	var host: NpcAgent = main.npcs[0]
	var fallen: NpcAgent = main.npcs[1]
	var newcomer: NpcAgent = main.npcs[2]
	PartyOps.join_party_of(fallen, host)
	var party_name := host.party_name
	fallen.die()
	PartyOps.join_party_of(newcomer, host)

	assert_eq(host.party_name, party_name, "no new name for a party that already had one")
	assert_eq(newcomer.party_name, party_name)
