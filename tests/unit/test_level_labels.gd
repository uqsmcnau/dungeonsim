extends DungeonTest

## Covers the "Name Lv.N" tag above each character on the map staying in
## step with their level -- in particular for party followers, who level up
## from their share of a kill's xp but never run the leader-side code that
## used to be the only thing refreshing the tag.

func before_each():
	load_main()

func _party_of_two() -> Array:
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	leader.party = [leader, follower]
	leader.is_party_leader = true
	follower.party = leader.party
	follower.is_party_leader = false
	for m in leader.party:
		m.stats.xp = 0
		m.stats.xp_to_next = 5
		m.reset_label()
	return leader.party

func test_follower_tag_shows_its_new_level_after_a_shared_kill():
	var members := _party_of_two()
	var follower: NpcAgent = members[1]
	members[0].share_xp_with_party(10)  # 5 each: enough for both to level

	assert_eq(follower.stats.level, 2, "sanity: the follower levelled up")
	assert_eq(follower.name_label.text, "%s Lv.2" % follower.npc_name)

func test_leader_tag_shows_its_new_level_too():
	var members := _party_of_two()
	var leader: NpcAgent = members[0]
	leader.share_xp_with_party(10)
	assert_eq(leader.name_label.text, "%s Lv.2" % leader.npc_name)

func test_a_busy_label_is_left_alone_until_it_reverts():
	var members := _party_of_two()
	var leader: NpcAgent = members[0]
	leader.show_label("%s ⚔ Lv.3" % leader.npc_name)  # mid-fight: Lv here is the *enemy's*
	leader.share_xp_with_party(10)
	assert_eq(leader.name_label.text, "%s ⚔ Lv.3" % leader.npc_name, "don't clobber the fight display")
	leader.reset_label()  # e.g. the fight ends
	assert_eq(leader.name_label.text, "%s Lv.2" % leader.npc_name, "the new level shows once it reverts")

func test_level_up_does_not_reset_the_characters_action():
	var members := _party_of_two()
	var follower: NpcAgent = members[1]
	follower.current_action = "Fighting a level 3 enemy"
	members[0].share_xp_with_party(10)
	assert_eq(follower.current_action, "Fighting a level 3 enemy")
