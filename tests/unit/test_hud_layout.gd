extends GutTest

## Covers where the HUD panels go: the leaderboard (the top
## VISIBLE_HUD_COUNT characters) down the right-hand column in rank order,
## and the selected character's panel at the top of the left-hand column
## with the rest of their party listed below it.

var main: Node

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())

func after_each():
	get_tree().paused = false

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

func _visible_in(container: VBoxContainer) -> Array:
	return container.get_children().filter(func(c): return c.visible)

func _panel(npc: NpcAgent) -> PanelContainer:
	return main.hud.rows[npc]["panel"]

## The panels in the left column, in order.
func _selection_panels() -> Array:
	return main.hud.selection_container.get_children()

# ============================== Leaderboard ===============================

func test_the_leaderboard_shows_six():
	assert_eq(Hud.VISIBLE_HUD_COUNT, 6)
	_rank_npcs_by_index(main.npcs.size())
	main._process(0.0)
	assert_eq(_visible_in(main.hud.leaderboard_container).size(), 6)

func test_the_leaderboard_is_only_on_the_right():
	_rank_npcs_by_index(main.npcs.size())
	main._process(0.0)
	for npc in main.hud.rows:
		assert_eq(_panel(npc).get_parent(), main.hud.leaderboard_container)
	assert_eq(_selection_panels().size(), 0, "nothing on the left until someone's selected")

func test_the_leaderboard_runs_top_down_in_rank_order():
	var n: int = main.npcs.size()
	_rank_npcs_by_index(n)
	main._process(0.0)
	var shown := _visible_in(main.hud.leaderboard_container)
	for i in range(6):
		assert_eq(shown[i], _panel(main.npcs[n - 1 - i]), "#%d" % (i + 1))
		assert_eq(shown[i].get_index(), i)

func test_order_is_kept_as_rankings_change():
	var n: int = main.npcs.size()
	_rank_npcs_by_index(n)
	main._process(0.0)
	var underdog: NpcAgent = main.npcs[0]
	underdog.stats.attack_bonus = 1000
	underdog.stats.max_hp = 1000
	main._process(0.0)
	assert_eq(_visible_in(main.hud.leaderboard_container)[0], _panel(underdog), "the new #1 goes to the top")
	assert_eq(_visible_in(main.hud.leaderboard_container).size(), 6)

func test_a_dying_leader_keeps_its_slot_in_the_six():
	var n: int = main.npcs.size()
	_rank_npcs_by_index(n)
	main._process(0.0)
	main.npcs[n - 1]._die()  # kill the current #1
	main._process(0.0)
	assert_eq(_visible_in(main.hud.leaderboard_container).size(), 6, "the grace period still holds its slot")

func test_fewer_than_six_left_shows_them_all():
	var to_kill: Array = []
	for i in range(main.npcs.size()):
		if i >= 4:
			to_kill.append(main.npcs[i])
	for npc in to_kill:
		npc._die()
	main.hud.dying.clear()  # skip the grace period
	_rank_npcs_by_index(4)
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
	follower._die()
	main._process(0.0)
	assert_true(main.hud.party_panels.has(follower), "kept for the death grace period")
	var r: Dictionary = main.hud.party_panels[follower]
	assert_string_contains(r["header"].text, "DEAD")
	assert_eq(r["panel"].modulate, Color(0.5, 0.5, 0.5, 1.0))
	assert_gt(r["flash"].color.a, 0.0, "the death flash plays")

func test_a_fallen_member_drops_off_the_list_after_the_grace_period():
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(follower, leader)
	main.hud.inspect(leader)
	follower._die()
	await wait_seconds(Hud.DEATH_GRACE_SECONDS + 0.2)
	main._process(0.0)
	assert_eq(_selection_panels(), [main.hud.inspector["panel"]])
	assert_false(main.hud.party_panels.has(follower))

func test_a_dead_selection_shows_only_their_own_panel():
	var leader: NpcAgent = main.npcs[0]
	var follower: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(follower, leader)
	main.hud.inspect(leader)
	leader._die()
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
