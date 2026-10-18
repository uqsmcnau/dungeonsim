extends GutTest

## Covers the map highlight on the selected character's party: a ring
## around all of its members' icons that follows them, and clicking
## anywhere else on the map to deselect.

var main: Node

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())

func after_each():
	get_tree().paused = false

func _select(npc: NpcAgent) -> void:
	main._on_world_clicked(npc.global_position)

func _party_of(size: int) -> Array:
	var leader: NpcAgent = main.npcs[0]
	for i in range(1, size):
		PartyOps.join_party_of(main.npcs[i], leader)
	# Skip the walk-over: put everyone straight at their offset spots.
	for m in leader.party:
		m.position = leader.position + m.party_offset
	return leader.party

func test_selecting_a_character_rings_them():
	var npc: NpcAgent = main.npcs[0]
	_select(npc)
	assert_eq(main.maze_view.selection_center, npc.position)
	assert_gt(main.maze_view.selection_radius, 8.0, "wide enough to clear the 16px icon")

func test_ring_takes_in_the_whole_party():
	var members := _party_of(3)
	_select(members[0])
	var ring_radius: float = main.maze_view.selection_radius
	for m in members:
		var reach: float = m.position.distance_to(main.maze_view.selection_center) + 8.0  # + half the icon
		assert_lte(reach, ring_radius, "%s's icon should sit inside the ring" % m.npc_name)

func test_selecting_a_follower_rings_the_party_around_its_leader():
	var members := _party_of(2)
	_select(members[1])
	assert_eq(main.maze_view.selection_center, members[0].position)

func test_party_ring_is_bigger_than_a_solo_ring():
	_select(main.npcs[5])
	var solo_radius: float = main.maze_view.selection_radius
	var members := _party_of(3)
	_select(members[0])
	assert_gt(main.maze_view.selection_radius, solo_radius)

func test_ring_follows_the_party_as_it_moves():
	var members := _party_of(2)
	_select(members[0])
	for m in members:
		m.position += Vector2(40, 0)
	main._process(0.0)
	assert_eq(main.maze_view.selection_center, members[0].position)

func test_clicking_anywhere_else_on_the_map_deselects():
	_select(main.npcs[0])
	main._on_world_clicked(Vector2(-1000, -1000))
	assert_null(main.hud.inspected)
	assert_eq(main.maze_view.selection_radius, 0.0, "the ring goes too")

func test_closing_the_panel_clears_the_ring_even_while_paused():
	_select(main.npcs[0])
	main.hud.set_paused(true)
	main.hud.inspector["close_button"].pressed.emit()
	assert_eq(main.maze_view.selection_radius, 0.0)

func test_selecting_while_paused_rings_them_straight_away():
	main.hud.set_paused(true)
	_select(main.npcs[0])
	assert_gt(main.maze_view.selection_radius, 0.0)

func test_ring_moves_to_their_gravestone_once_the_selected_character_dies():
	var npc: NpcAgent = main.npcs[0]
	_select(npc)
	npc._die()
	main._process(0.0)
	assert_eq(main.hud.inspected, npc, "sanity: their panel stays open, greyed out")
	assert_eq(main.maze_view.selection_center, main.graves[npc].position)
	assert_eq(main.maze_view.selection_radius, main.GRAVE_RING_RADIUS)
