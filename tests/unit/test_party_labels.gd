extends DungeonTest

## Covers the labels above characters on the map once they team up: one
## label for the whole party, showing the party's name, rather than every
## member's own name and level.

func before_each():
	load_main()

func _party_of(size: int) -> Array:
	var leader: NpcAgent = main.npcs[0]
	for i in range(1, size):
		PartyOps.join_party_of(main.npcs[i], leader)
	leader.reset_label()  # as when the "grew to N!" message times out
	return leader.party

func _showing(members: Array) -> Array:
	return members.filter(func(m): return m.name_label.visible)

func test_a_lone_character_shows_their_own_name_and_level():
	var npc: NpcAgent = main.npcs[0]
	assert_true(npc.name_label.visible)
	assert_eq(npc.name_label.text, "%s Lv.%d" % [npc.npc_name, npc.stats.level])

func test_a_party_shows_one_label_with_its_name():
	var members := _party_of(3)
	var leader: NpcAgent = members[0]
	assert_eq(_showing(members), [leader], "only the leader's label shows")
	assert_eq(leader.name_label.text, leader.party_name)

func test_no_member_shows_their_own_name():
	var members := _party_of(3)
	for m in _showing(members):
		for other in members:
			assert_false(m.name_label.text.contains(other.npc_name), "%s's name is on the map" % other.npc_name)

func test_followers_stay_hidden_frame_after_frame():
	var members := _party_of(2)
	for m in members:
		m._process(0.0)
	assert_false(members[1].name_label.visible)
	assert_true(members[0].name_label.visible)

func test_growing_announces_the_party_by_name():
	var leader: NpcAgent = main.npcs[0]
	PartyOps.join_party_of(main.npcs[1], leader)
	assert_eq(leader.name_label.text, "%s grew to 2!" % leader.party_name)

func test_the_party_label_sits_clear_of_the_members_icons():
	var solo_y: float = main.npcs[5].name_label.position.y
	var members := _party_of(2)
	assert_lt(members[0].name_label.position.y, solo_y, "raised above where a lone character's sits")

func test_fights_are_labelled_with_the_party_name():
	var members := _party_of(2)
	var leader: NpcAgent = members[0]
	var rival: NpcAgent = main.npcs[5]
	assert_eq(leader.map_name(), leader.party_name)
	assert_eq(rival.map_name(), rival.npc_name, "a loner goes by their own name")
	for m in members + [rival]:
		m.stats.hp = 500
		m.stats.max_hp = 500
	GroupCombat.run_pvp_turn(leader.party, rival.party, leader.cell_pos, rival.cell_pos)
	assert_eq(leader.name_label.text, "%s ⚔ vs %s" % [leader.party_name, rival.npc_name])
	assert_eq(rival.name_label.text, "%s ⚔ vs %s" % [rival.npc_name, leader.party_name])

func test_a_promoted_leader_takes_over_the_party_label():
	var members := _party_of(3)
	var leader: NpcAgent = members[0]
	var next: NpcAgent = members[1]
	var label_text: String = leader.name_label.text
	leader.die()
	assert_true(next.name_label.visible)
	assert_eq(next.name_label.text, label_text)

func test_the_last_survivor_gets_their_own_name_back():
	var members := _party_of(2)
	var leader: NpcAgent = members[0]
	var survivor: NpcAgent = members[1]
	leader.die()
	survivor._process(0.0)
	assert_true(survivor.name_label.visible)
	assert_eq(survivor.name_label.text, "%s Lv.%d" % [survivor.npc_name, survivor.stats.level])
	assert_eq(survivor.name_label.position.y, main.npcs[5].name_label.position.y, "back down to where a lone character's sits")

func test_a_busy_label_isnt_cut_short_by_the_party_changing():
	var leader: NpcAgent = main.npcs[0]
	var fight_text := "%s ⚔ Lv.3" % leader.npc_name
	leader.show_label(fight_text)  # mid-fight
	PartyOps.join_party_of(main.npcs[1], leader)
	leader.show_label(fight_text)  # the fight's next turn
	main.npcs[1].die()
	assert_eq(leader.name_label.text, fight_text)
	leader.reset_label()  # the fight ends
	assert_eq(leader.name_label.text, "%s Lv.%d" % [leader.npc_name, leader.stats.level], "and then it picks up the change")

func test_a_passing_message_goes_back_to_rest_on_its_own():
	var leader: NpcAgent = main.npcs[0]
	PartyOps.join_party_of(main.npcs[1], leader)
	assert_string_contains(leader.name_label.text, "grew to 2!")
	leader._process(MapLabel.MESSAGE_SECONDS / 2.0)
	assert_string_contains(leader.name_label.text, "grew to 2!", "not yet")
	leader._process(MapLabel.MESSAGE_SECONDS / 2.0)
	assert_eq(leader.name_label.text, leader.party_name)

func test_a_passing_message_waits_while_paused():
	var leader: NpcAgent = main.npcs[0]
	PartyOps.join_party_of(main.npcs[1], leader)
	main.hud.toolbar.set_paused(true)
	await get_tree().create_timer(MapLabel.MESSAGE_SECONDS + 0.3, true).timeout
	main.hud.toolbar.set_paused(false)
	assert_string_contains(leader.name_label.text, "grew to 2!")

func test_a_new_leader_finishes_a_message_the_fallen_one_was_showing():
	# Regression: the countdown used to be a timer bound to the old leader,
	# so a message it was showing when it fell stuck on the new leader.
	var members := _party_of(3)
	var leader: NpcAgent = members[0]
	var next: NpcAgent = members[1]
	leader.show_label("%s found Helmet!" % leader.party_name, MapLabel.MESSAGE_SECONDS)
	leader.die()
	assert_eq(next.name_label.text, "%s found Helmet!" % next.party_name, "carried over")
	next._process(MapLabel.MESSAGE_SECONDS)
	assert_eq(next.name_label.text, next.party_name, "and put back on time")

func test_a_fight_isnt_cut_short_by_a_message_running_out():
	var leader: NpcAgent = main.npcs[0]
	leader.show_label("%s found Helmet!" % leader.npc_name, MapLabel.MESSAGE_SECONDS)
	leader.show_label("%s ⚔ Lv.3" % leader.npc_name)  # a fight starts
	leader._process(MapLabel.MESSAGE_SECONDS * 2)
	assert_eq(leader.name_label.text, "%s ⚔ Lv.3" % leader.npc_name)
