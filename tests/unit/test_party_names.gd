extends GutTest

## Covers randomly generated, alignment-flavoured party names (PartyNames)
## and how they're handed out when parties form and merge.

const SAMPLES := 300
const FILLER := ["The", "of", "the"]

var main: Node

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())

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

func test_merging_two_named_parties_keeps_the_hosts_name():
	var host: NpcAgent = main.npcs[0]
	var host_mate: NpcAgent = main.npcs[1]
	var joiner: NpcAgent = main.npcs[2]
	var joiner_mate: NpcAgent = main.npcs[3]
	for npc in [host, host_mate, joiner, joiner_mate]:
		npc.stats.alignment = NpcStats.ALIGNMENT_GOOD
	PartyOps.join_party_of(host_mate, host)
	PartyOps.join_party_of(joiner_mate, joiner)
	var host_name := host.party_name
	assert_ne(joiner.party_name, "", "sanity: the joining party has a name of its own")

	PartyOps.join_party_of(joiner, host)

	for npc in [host, host_mate, joiner, joiner_mate]:
		assert_eq(npc.party_name, host_name, "%s should go by the host's party name" % npc.npc_name)

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
