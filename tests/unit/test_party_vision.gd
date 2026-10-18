extends GutTest

## Covers each character's own map of what it has seen (NpcAgent.seen_cells),
## how party members pool those maps, and Party Vision: the fog showing only
## the selected party's knowledge, toggled from the toolbar.

const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")

var main: Node
var a: NpcAgent
var b: NpcAgent

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())
	# Two characters from opposite sides of the maze (start cells are spread
	# evenly around the border), so neither has seen anything the other has.
	a = main.npcs[0]
	b = main.npcs[main.npcs.size() / 2]
	main._process(0.0)

func after_each():
	get_tree().paused = false

func _select(npc: NpcAgent) -> void:
	main._on_world_clicked(npc.global_position)

## The nearest cell `npc` can walk to that shows it something it hasn't
## seen yet, or NONE. Not always a neighbor: a start room can be closed in
## enough that every step within it shows nothing new.
func _cell_with_new_view(npc: NpcAgent) -> Vector2i:
	var reached: Dictionary = {npc.cell_pos: true}
	var queue: Array = [npc.cell_pos]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for n in MazeQuery.open_neighbors(main.grid, cur):
			if reached.has(n):
				continue
			reached[n] = true
			for c in MazeQuery.visible_cells(main.grid, n, NpcAgent.SIGHT_RANGE):
				if not npc.seen_cells.has(c):
					return n
			queue.append(n)
	return MazeQuery.NONE

## A cell `knower` has seen but `other` hasn't.
func _known_only_to(knower: NpcAgent, other: NpcAgent) -> Vector2i:
	for c in knower.seen_cells:
		if not other.seen_cells.has(c) and not main.maze_view.permanent_cells.has(c):
			return c
	return MazeQuery.NONE

func _has_all(map: Dictionary, cells: Dictionary) -> bool:
	for c in cells:
		if not map.has(c):
			return false
	return true

# ============================ Each character's map ========================

func test_a_character_starts_out_knowing_what_it_can_see():
	assert_true(a.seen_cells.has(a.cell_pos))
	assert_true(_has_all(a.seen_cells, MazeQuery.visible_cells(main.grid, a.cell_pos, NpcAgent.SIGHT_RANGE)))

func test_moving_adds_to_the_map_and_keeps_what_was_seen_before():
	var before: Dictionary = a.seen_cells.duplicate()
	var next := _cell_with_new_view(a)
	assert_ne(next, MazeQuery.NONE, "sanity: some neighbor should show something new")
	a.unregister()
	a.cell_pos = next
	main._process(0.0)
	assert_gt(a.seen_cells.size(), before.size(), "new sights get added")
	assert_true(_has_all(a.seen_cells, before), "and nothing seen before is forgotten")

func test_characters_dont_know_what_others_have_seen():
	assert_ne(_known_only_to(b, a), MazeQuery.NONE)

# ============================ Pooling in a party ==========================

func test_joining_a_party_pools_everything_both_had_seen():
	var a_before: Dictionary = a.seen_cells.duplicate()
	var b_before: Dictionary = b.seen_cells.duplicate()
	PartyOps.join_party_of(b, a)
	for member in [a, b]:
		assert_true(_has_all(member.seen_cells, a_before), "%s knows what %s saw before they met" % [member.npc_name, a.npc_name])
		assert_true(_has_all(member.seen_cells, b_before), "%s knows what %s saw before they met" % [member.npc_name, b.npc_name])

func test_a_whole_party_joining_pools_every_members_map():
	var c: NpcAgent = main.npcs[main.npcs.size() / 4]
	PartyOps.join_party_of(c, b)  # b and c form a party first...
	var c_before: Dictionary = c.seen_cells.duplicate()
	PartyOps.join_party_of(b, a)  # ...then that party joins a
	assert_true(_has_all(a.seen_cells, c_before), "the host learns what the follower of the joining party saw")

func test_what_one_member_sees_is_shared_with_the_rest():
	PartyOps.join_party_of(b, a)
	var next := _cell_with_new_view(a)
	assert_ne(next, MazeQuery.NONE)
	a.unregister()
	a.cell_pos = next
	a._on_enter_cell()
	assert_true(_has_all(b.seen_cells, a.sight_cells), "the follower's map picks up what the leader sees")

func test_the_pooled_map_is_kept_after_a_member_dies():
	var a_before: Dictionary = a.seen_cells.duplicate()
	# a joins b and falls before ever getting there -- so b can't simply be
	# seeing a's old surroundings for itself.
	PartyOps.join_party_of(a, b)
	a.die()
	main._process(0.0)
	assert_true(_has_all(b.seen_cells, a_before), "the survivor keeps the fallen member's map")

func test_the_pooled_map_is_kept_by_each_member_separately():
	PartyOps.join_party_of(b, a)
	assert_false(is_same(a.seen_cells, b.seen_cells), "a copy each, not one shared dict that'd go with the party")

# ============================ Party Vision fog ============================

func test_party_vision_is_on_by_default():
	assert_true(main.party_vision)
	assert_true(main.hud.party_vision_toggle.button_pressed)

func test_party_vision_hides_what_only_others_have_seen():
	var elsewhere := _known_only_to(b, a)
	_select(a)
	assert_false(main.maze_view.is_discovered(elsewhere), "b's discoveries aren't shown while a is selected")
	assert_false(main.maze_view.is_currently_visible(b.cell_pos), "nor what b can see right now")
	assert_true(main.maze_view.is_currently_visible(a.cell_pos))

func test_party_vision_shows_everything_the_party_has_explored():
	var a_saw := _known_only_to(a, b)
	PartyOps.join_party_of(b, a)
	_select(b)
	assert_true(main.maze_view.is_discovered(a_saw), "b's party knows what a saw before they met")
	assert_true(main.maze_view.is_currently_visible(a.cell_pos))

func test_party_vision_keeps_a_fallen_members_discoveries():
	var a_saw := _known_only_to(a, b)
	PartyOps.join_party_of(a, b)
	a.die()
	_select(b)
	main._process(0.0)
	assert_true(main.maze_view.is_discovered(a_saw))

func test_deselecting_shows_everyones_view_again():
	var elsewhere := _known_only_to(b, a)
	_select(a)
	main._on_world_clicked(Vector2(-1000, -1000))
	assert_true(main.maze_view.is_discovered(elsewhere))

func test_switching_party_vision_off_shows_everyones_view_even_while_paused():
	var elsewhere := _known_only_to(b, a)
	_select(a)
	main.hud.set_paused(true)
	main.hud.party_vision_toggle.button_pressed = false
	assert_false(main.party_vision)
	assert_true(main.maze_view.is_discovered(elsewhere))
	main.hud.party_vision_toggle.button_pressed = true
	assert_false(main.maze_view.is_discovered(elsewhere), "and back on again")

func test_selecting_while_paused_applies_party_vision_straight_away():
	var elsewhere := _known_only_to(b, a)
	main.hud.set_paused(true)
	_select(a)
	assert_false(main.maze_view.is_discovered(elsewhere))

func test_no_party_vision_for_a_dead_selection():
	var elsewhere := _known_only_to(b, a)
	_select(a)
	a.die()
	main._process(0.0)
	assert_true(main.maze_view.is_discovered(elsewhere))

func test_fog_off_still_shows_everything():
	var elsewhere := _known_only_to(b, a)
	_select(a)
	main.hud.fog_toggle.button_pressed = false
	assert_true(main.maze_view.is_discovered(elsewhere))
	assert_true(main.maze_view.is_currently_visible(b.cell_pos))

func test_the_boss_room_still_shows_under_party_vision():
	_select(a)
	assert_true(main.maze_view.is_discovered(main.exit_cell))
	assert_true(main.maze_view.is_currently_visible(main.exit_cell))

func test_monsters_only_the_selected_party_cant_see_are_hidden():
	var enemy: EnemyAgent = add_child_autofree(ENEMY_SCENE.instantiate())
	enemy.setup(b.cell_pos, main.CELL_SIZE, 1, main.grid, main.enemy_map, {}, [])
	main._process(0.0)
	assert_true(enemy.visible, "sanity: b can see it")
	_select(a)
	assert_false(enemy.visible, "but a's party can't")
