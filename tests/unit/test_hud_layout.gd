extends DungeonTest

## Covers where the HUD panels go: the leaderboard (the top
## VISIBLE_HUD_COUNT characters) down the right-hand column in rank order,
## and the selected character's panel at the top of the left-hand column
## with the rest of their party listed below it.

func before_each():
	load_main()

func after_each():
	get_tree().paused = false

func _visible_in(container: VBoxContainer) -> Array:
	return container.get_children().filter(func(c): return c.visible)

func _panel(npc: NpcAgent) -> PanelContainer:
	return main.hud.rows[npc]["panel"]

## The panels in the left column, in order.
func _selection_panels() -> Array:
	return main.hud.selection_container.get_children()

# ============================== Leaderboard ===============================

func test_the_leaderboard_shows_ten():
	assert_eq(Hud.VISIBLE_HUD_COUNT, 10)
	rank_npcs_by_index(main.npcs.size())
	main._process(0.0)
	assert_eq(_visible_in(main.hud.leaderboard_container).size(), 10)

func test_the_leaderboard_is_only_on_the_right():
	rank_npcs_by_index(main.npcs.size())
	main._process(0.0)
	for npc in main.hud.rows:
		assert_eq(_panel(npc).get_parent(), main.hud.leaderboard_container)
	assert_eq(_selection_panels().size(), 0, "nothing on the left until someone's selected")

func test_the_leaderboard_runs_top_down_in_rank_order():
	var n: int = main.npcs.size()
	rank_npcs_by_index(n)
	main._process(0.0)
	var shown := _visible_in(main.hud.leaderboard_container)
	for i in range(10):
		assert_eq(shown[i], _panel(main.npcs[n - 1 - i]), "#%d" % (i + 1))
		assert_eq(shown[i].get_index(), i)

func test_order_is_kept_as_rankings_change():
	var n: int = main.npcs.size()
	rank_npcs_by_index(n)
	main._process(0.0)
	var underdog: NpcAgent = main.npcs[0]
	underdog.stats.attack_bonus = 1000
	underdog.stats.max_hp = 1000
	main._process(0.0)
	assert_eq(_visible_in(main.hud.leaderboard_container)[0], _panel(underdog), "the new #1 goes to the top")
	assert_eq(_visible_in(main.hud.leaderboard_container).size(), 10)

func test_a_panel_is_up_to_date_the_moment_it_joins_the_ten():
	var n: int = main.npcs.size()
	rank_npcs_by_index(n)
	main._process(0.0)
	var underdog: NpcAgent = main.npcs[0]
	underdog.stats.hp = 7
	main._process(0.0)  # still off the board
	underdog.stats.attack_bonus = 1000
	underdog.stats.max_hp = 1000
	main._process(0.0)
	assert_eq(main.hud.rows[underdog]["hp_text"].text, "HP 7/1000")

func test_a_dying_leader_keeps_its_slot_in_the_ten():
	var n: int = main.npcs.size()
	rank_npcs_by_index(n)
	main._process(0.0)
	main.npcs[n - 1].die()  # kill the current #1
	main._process(0.0)
	assert_eq(_visible_in(main.hud.leaderboard_container).size(), 10, "the grace period still holds its slot")

func test_leaderboard_panels_leave_out_gear():
	main._process(0.0)
	for npc in main.hud.rows:
		var r: Dictionary = main.hud.rows[npc]
		assert_null(r["gear"], "%s's leaderboard panel" % npc.npc_name)
		assert_false(_text_in(r["panel"]).contains("Hands:"))
	assert_string_contains(_text_in(_panel(main.npcs[0])), "STR ", "the rest is still there")

func test_the_selected_characters_panel_still_shows_gear():
	var leader: NpcAgent = main.npcs[0]
	main.hud.inspect(leader)
	var r: Dictionary = main.hud.inspector
	assert_not_null(r["gear"])
	var text := _text_in(r["panel"])
	for label in ["Hands:", "Armor:", "Helmet:", "Feet:", "Accessories:", "Potions:", "Spells:"]:
		assert_string_contains(text, label)

func test_the_rest_of_their_party_get_compact_panels():
	# Leaving room for the battle window below.
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(follower, leader)
	main.hud.inspect(leader)
	var r: Dictionary = main.hud.party_panels[follower]
	assert_null(r["gear"])
	assert_string_contains(_text_in(r["panel"]), "STR ", "the rest is still there")

func test_a_full_party_fits_above_the_battle_window():
	var leader: NpcAgent = main.npcs[0]
	for i in range(1, 5):
		PartyOps.join_party_of(main.npcs[i], leader)
		main.npcs[i].stats.inventory["Health Potion"] = 2
	main.hud.inspect(leader)
	var column: VBoxContainer = main.hud.selection_container
	assert_lte(column.get_combined_minimum_size().y, column.offset_bottom - column.offset_top, "five panels down the column")
	assert_lte(column.offset_bottom, main.hud.battle_window.offset_top, "and none of it behind the window")

func test_ten_leaderboard_panels_fit_down_the_column():
	rank_npcs_by_index(main.npcs.size())
	main._process(0.0)
	var column: VBoxContainer = main.hud.leaderboard_container
	var height := column.offset_bottom - column.offset_top
	assert_lte(column.get_combined_minimum_size().y, height)

## Every label's text in a panel, joined up.
func _text_in(node: Node) -> String:
	var parts: Array = []
	if node is Label:
		parts.append(node.text)
	for child in node.get_children():
		parts.append(_text_in(child))
	return " ".join(parts)

func test_fewer_than_six_left_shows_them_all():
	var to_kill: Array = []
	for i in range(main.npcs.size()):
		if i >= 4:
			to_kill.append(main.npcs[i])
	for npc in to_kill:
		npc.die()
	main.hud.dying.clear()  # skip the grace period
	rank_npcs_by_index(4)
	main._process(0.0)
	assert_eq(_visible_in(main.hud.leaderboard_container).size(), 4)

# ========================== The selected party ============================

func test_the_selected_character_is_at_the_top_left():
	var npc: NpcAgent = main.npcs[3]
	main.hud.inspect(npc)
	assert_eq(_selection_panels(), [main.hud.inspector["panel"]])

func test_their_party_is_listed_below_them():
	var leader: NpcAgent = main.npcs[0]
	PartyOps.join_party_of(main.npcs[1], leader)
	PartyOps.join_party_of(main.npcs[2], leader)
	main.hud.inspect(leader)
	var panels := _selection_panels()
	assert_eq(panels.size(), 3)
	assert_eq(panels[0], main.hud.inspector["panel"])
	assert_eq(panels[1], main.hud.party_panels[main.npcs[1]]["panel"])
	assert_eq(panels[2], main.hud.party_panels[main.npcs[2]]["panel"])
	assert_string_contains(main.hud.party_panels[main.npcs[2]]["header"].text, main.npcs[2].npc_name)

func test_selecting_a_follower_puts_them_first_and_the_leader_below():
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(follower, leader)
	main.hud.inspect(follower)
	var panels := _selection_panels()
	assert_eq(panels[0], main.hud.inspector["panel"])
	assert_string_contains(main.hud.inspector["header"].text, follower.npc_name)
	assert_eq(panels[1], main.hud.party_panels[leader]["panel"])

func test_party_panels_track_live_stats():
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(follower, leader)
	main.hud.inspect(leader)
	follower.stats.hp = 3
	main._process(0.0)
	assert_string_contains(main.hud.party_panels[follower]["hp_text"].text, "HP 3/")

func test_someone_joining_is_added_to_the_list():
	var leader: NpcAgent = main.npcs[0]
	main.hud.inspect(leader)
	assert_eq(_selection_panels().size(), 1)
	PartyOps.join_party_of(main.npcs[1], leader)
	main._process(0.0)
	assert_eq(_selection_panels().size(), 2)

func test_a_fallen_member_stays_listed_greyed_out_for_a_moment():
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(follower, leader)
	main.hud.inspect(leader)
	follower.die()
	main._process(0.0)
	assert_true(main.hud.party_panels.has(follower), "kept for the death grace period")
	var r: Dictionary = main.hud.party_panels[follower]
	assert_string_contains(r["header"].text, "DEAD")
	assert_eq(r["panel"].modulate, Color(0.5, 0.5, 0.5, 1.0))
	assert_gt(r["flash"].color.a, 0.0, "the death flash plays")

func test_a_fallen_member_drops_off_the_list_after_the_grace_period():
	fast_forward()
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(follower, leader)
	main.hud.inspect(leader)
	follower.die()
	await wait_seconds(Hud.DEATH_GRACE_SECONDS + 0.2)
	main._process(0.0)
	assert_eq(_selection_panels(), [main.hud.inspector["panel"]])
	assert_false(main.hud.party_panels.has(follower))

func test_a_dead_selection_shows_only_their_own_panel():
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(follower, leader)
	main.hud.inspect(leader)
	leader.die()
	main._process(0.0)
	assert_eq(_selection_panels(), [main.hud.inspector["panel"]])

func test_switching_selection_replaces_the_whole_list():
	var leader: NpcAgent = main.npcs[0]
	PartyOps.join_party_of(main.npcs[1], leader)
	main.hud.inspect(leader)
	main.hud.inspect(main.npcs[5])
	assert_eq(_selection_panels(), [main.hud.inspector["panel"]])
	assert_true(main.hud.party_panels.is_empty())

func test_deselecting_clears_the_left_column_even_while_paused():
	var leader: NpcAgent = main.npcs[0]
	PartyOps.join_party_of(main.npcs[1], leader)
	main.hud.inspect(leader)
	main.hud.set_paused(true)
	main.hud.inspector["close_button"].pressed.emit()
	assert_eq(_selection_panels().size(), 0)

func test_discarded_panels_are_freed_not_leaked():
	# Panels leave the column at once (so the next selection lays out
	# cleanly) and are freed at the end of the frame -- GUT's orphan count,
	# taken straight after a test, sees them in between.
	var leader: NpcAgent = main.npcs[0]
	PartyOps.join_party_of(main.npcs[1], leader)
	main.hud.inspect(leader)
	var panels := _selection_panels()
	main.hud.close_inspector()
	await get_tree().process_frame
	for p in panels:
		assert_false(is_instance_valid(p))

func test_selecting_while_paused_lists_the_party_straight_away():
	var leader: NpcAgent = main.npcs[0]
	PartyOps.join_party_of(main.npcs[1], leader)
	main.hud.set_paused(true)
	main.hud.inspect(leader)
	assert_eq(_selection_panels().size(), 2)

func test_a_level_up_flashes_a_party_members_panel_too():
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(follower, leader)
	main.hud.inspect(leader)
	main.hud.flash_level_up(follower)
	assert_gt(main.hud.party_panels[follower]["flash"].color.a, 0.0)
