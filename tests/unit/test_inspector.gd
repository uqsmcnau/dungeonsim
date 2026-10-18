extends DungeonTest

## Covers clicking a character's icon in the maze to open their inspector
## panel at the top of the left column, separate from the leaderboard.

func before_each():
	load_main()

func after_each():
	get_tree().paused = false

func _click_at_world(world_pos: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = get_viewport().get_canvas_transform() * world_pos
	get_viewport().push_input(event)

func test_npc_at_finds_the_character_under_the_click():
	var npc: NpcAgent = main.npcs[0]
	assert_eq(main.npc_at(npc.global_position), npc)
	assert_eq(main.npc_at(npc.global_position + Vector2(6, -6)), npc, "anywhere on the 16px icon should count")

func test_npc_at_returns_null_on_empty_space():
	assert_null(main.npc_at(Vector2(-1000, -1000)))

func test_npc_at_prefers_the_nearest_of_overlapping_party_members():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	b.global_position = a.global_position + Vector2(10, 10)
	assert_eq(main.npc_at(a.global_position + Vector2(2, 2)), a)
	assert_eq(main.npc_at(b.global_position - Vector2(2, 2)), b)

func test_npc_at_ignores_dead_characters():
	var npc: NpcAgent = main.npcs[0]
	var pos: Vector2 = npc.global_position
	npc.die()
	assert_null(main.npc_at(pos))

func test_real_mouse_click_on_an_icon_opens_the_inspector():
	# Pushed through the viewport, so this also proves the full-screen HUD
	# Control doesn't swallow clicks meant for the maze. The headless test
	# window is only 64x64, so stretch the HUD to the real 1920x1080 it
	# covers in-game -- otherwise the click lands outside it either way.
	main.hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	main.hud.size = Vector2(1920, 1080)
	var npc: NpcAgent = main.npcs[0]
	_click_at_world(npc.global_position)
	assert_eq(main.hud.inspected, npc)

func test_inspector_shows_the_character_at_the_top_left():
	var npc: NpcAgent = main.npcs[0]
	main._on_world_clicked(npc.global_position)
	var panel: PanelContainer = main.hud.inspector["panel"]
	assert_eq(panel.get_parent(), main.hud.selection_container, "the left column, separate from the leaderboard")
	assert_eq(panel.get_index(), 0, "at the top")
	assert_string_contains(main.hud.inspector["header"].text, npc.npc_name)

func test_clicking_another_character_switches_the_inspector():
	main._on_world_clicked(main.npcs[0].global_position)
	var npc: NpcAgent = main.npcs[1]
	main._on_world_clicked(npc.global_position)
	assert_eq(main.hud.inspected, npc)
	assert_string_contains(main.hud.inspector["header"].text, npc.npc_name)

func test_clicking_empty_space_closes_the_inspector():
	main._on_world_clicked(main.npcs[0].global_position)
	main._on_world_clicked(Vector2(-1000, -1000))
	assert_null(main.hud.inspected)
	assert_true(main.hud.inspector.is_empty())

func test_close_button_closes_the_inspector():
	main._on_world_clicked(main.npcs[0].global_position)
	main.hud.inspector["close_button"].pressed.emit()
	assert_null(main.hud.inspected)

func test_inspector_tracks_live_stats():
	var npc: NpcAgent = main.npcs[0]
	main._on_world_clicked(npc.global_position)
	npc.stats.gold = 4321
	main._process(0.0)
	assert_string_contains(main.hud.inspector["header"].text, "4321g")

func test_inspector_works_for_characters_off_the_leaderboard():
	main._process(0.0)
	var off_board: NpcAgent = null
	for npc in main.npcs:
		if int(main.hud.rows[npc]["rank"]) == 0:
			off_board = npc
			break
	assert_not_null(off_board, "sanity: with 20 players only 10 are on the leaderboard")
	main._on_world_clicked(off_board.global_position)
	assert_eq(main.hud.inspected, off_board)

func test_inspected_character_stays_shown_after_dying():
	var npc: NpcAgent = main.npcs[0]
	main._on_world_clicked(npc.global_position)
	npc.die()
	main._process(0.0)
	assert_eq(main.hud.inspected, npc)
	assert_string_contains(main.hud.inspector["header"].text, "DEAD")

func test_inspecting_while_paused_shows_current_stats():
	var npc: NpcAgent = main.npcs[0]
	main.hud.set_paused(true)
	npc.stats.gold = 777
	main._on_world_clicked(npc.global_position)
	assert_string_contains(main.hud.inspector["header"].text, "777g", "should refresh immediately, since _process isn't running while paused")
	assert_true(main.get_node("ClickPicker").can_process(), "clicks must still be picked up while paused")
	assert_true(main.hud.inspector["close_button"].can_process())
