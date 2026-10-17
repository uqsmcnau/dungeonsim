extends GutTest

## Covers that the two HUD columns always split the currently-visible
## leaderboard panels as evenly as possible (5/5 in the normal 10-visible
## case), regardless of which specific characters happen to be shown or
## which column they originally registered into.

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

func _visible_count_in(container: VBoxContainer) -> int:
	var count := 0
	for child in container.get_children():
		if child.visible:
			count += 1
	return count

func test_ten_visible_panels_split_exactly_five_and_five():
	_rank_npcs_by_index(main.npcs.size())
	main._process(0.0)

	assert_eq(_visible_count_in(main.hud.left_container), 5)
	assert_eq(_visible_count_in(main.hud.right_container), 5)

func test_balance_is_maintained_even_though_every_panel_started_in_the_left_column():
	# register_npc always parents new panels to the left column initially --
	# confirm the very first leaderboard update actually redistributes them
	# rather than leaving them all piled up on one side.
	for npc in main.hud.rows:
		assert_eq(main.hud.rows[npc]["panel"].get_parent(), main.hud.left_container, "sanity: every panel should start in the left column")

	_rank_npcs_by_index(main.npcs.size())
	main._process(0.0)

	assert_eq(_visible_count_in(main.hud.left_container), 5)
	assert_eq(_visible_count_in(main.hud.right_container), 5)

func test_balance_is_restored_after_a_leaderboard_death_changes_who_is_shown():
	var n: int = main.npcs.size()
	_rank_npcs_by_index(n)
	main._process(0.0)
	main.npcs[n - 1]._die()  # kill the current #1
	main._process(0.0)

	# The champion lingers (death grace period) and the slot stays reserved
	# (see test_death_grace_period.gd), so there are still exactly 10 shown.
	assert_eq(_visible_count_in(main.hud.left_container), 5)
	assert_eq(_visible_count_in(main.hud.right_container), 5)

func test_columns_stay_as_balanced_as_possible_with_fewer_than_ten_shown():
	# Only 7 characters total, all distinctly ranked -- every one of them
	# ends up "visible" since there are fewer than VISIBLE_HUD_COUNT (10) of
	# them, and an odd total can't split perfectly evenly.
	# Collect references before killing anything -- main.npcs shifts as each
	# death removes an element, so indexing into it mid-loop would skip or
	# double up on survivors.
	var to_kill: Array = []
	for i in range(main.npcs.size()):
		if i >= 7:
			to_kill.append(main.npcs[i])
	for npc in to_kill:
		npc._die()
	_rank_npcs_by_index(7)
	main._process(0.0)

	var left: int = _visible_count_in(main.hud.left_container)
	var right: int = _visible_count_in(main.hud.right_container)
	assert_eq(left + right, 7)
	assert_lte(abs(left - right), 1, "the two columns should differ by at most one panel")
