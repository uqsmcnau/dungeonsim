extends DungeonTest

## Covers moving about the maze (MapCamera): zooming with the wheel and the
## keys, dragging it around, putting it back -- and clicks still landing on
## whatever's under the cursor, but not when the mouse was dragging.

var cam: MapCamera
## The view the game starts with (see MapCamera.frame).
var start_zoom: float
var start_position: Vector2

func before_each():
	load_main()
	cam = main.camera
	start_zoom = cam.zoom.x
	start_position = cam.position

func after_each():
	get_tree().paused = false

## Somewhere in the middle of the map area, clear of the HUD.
const MIDDLE := Vector2(960, 540)

func _button(index: MouseButton, pressed: bool, at: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = at
	get_viewport().push_input(event)

func _drag(index: MouseButton, from: Vector2, to: Vector2, steps: int = 4) -> void:
	_button(index, true, from)
	var at := from
	for i in range(1, steps + 1):
		var next := from.lerp(to, float(i) / steps)
		var motion := InputEventMouseMotion.new()
		motion.position = next
		motion.relative = next - at
		get_viewport().push_input(motion)
		at = next
	_button(index, false, to)

func _click(at: Vector2) -> void:
	_button(MOUSE_BUTTON_LEFT, true, at)
	_button(MOUSE_BUTTON_LEFT, false, at)

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		get_viewport().push_input(event)

func _on_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos

func _npc_in_the_middle() -> NpcAgent:
	# Someone well inside the map area, wherever they started.
	var npc: NpcAgent = main.npcs[0]
	npc.position = main.npc_container.to_local(MIDDLE)
	return npc

# =============================== The view =================================

func test_the_maze_is_seen_between_the_hud_columns():
	var area: Rect2 = main.hud.map_area()
	assert_eq(area.position, Vector2(470, 48))
	assert_eq(area.end.x, 1456.0)

func test_the_view_starts_on_the_whole_maze():
	var area: Rect2 = main.hud.map_area()
	var on_screen := Rect2(_on_screen(cam.maze_rect.position), cam.maze_rect.size * cam.zoom.x)
	assert_true(area.grow(0.5).encloses(on_screen), "all of it, border and all")
	assert_almost_eq(on_screen.get_center(), area.get_center(), Vector2.ONE * 0.5, "in the middle")
	assert_almost_eq(maxf(on_screen.size.x / area.size.x, on_screen.size.y / area.size.y), 1.0, 0.001,
		"as big as fits")

# ================================= Zoom ===================================

func test_the_wheel_zooms_in_towards_the_cursor():
	var at := MIDDLE + Vector2(120, -80)
	var under := cam.screen_to_world(at)
	_button(MOUSE_BUTTON_WHEEL_UP, true, at)
	assert_gt(cam.zoom.x, start_zoom)
	assert_almost_eq(cam.screen_to_world(at), under, Vector2.ONE * 0.01, "what was under the cursor still is")

func test_the_wheel_zooms_out_too():
	_button(MOUSE_BUTTON_WHEEL_DOWN, true, MIDDLE)
	assert_lt(cam.zoom.x, start_zoom)

func test_zoom_stays_within_limits():
	for i in range(40):
		_button(MOUSE_BUTTON_WHEEL_UP, true, MIDDLE)
	assert_almost_eq(cam.zoom.x, MapCamera.MAX_ZOOM, 0.001)
	for i in range(80):
		_button(MOUSE_BUTTON_WHEEL_DOWN, true, MIDDLE)
	assert_almost_eq(cam.zoom.x, MapCamera.MIN_ZOOM, 0.001)

func test_plus_and_minus_zoom_too():
	_key(KEY_EQUAL)
	assert_gt(cam.zoom.x, start_zoom)
	_key(KEY_MINUS)
	_key(KEY_MINUS)
	assert_lt(cam.zoom.x, start_zoom)

func test_home_puts_the_view_back():
	cam.zoom_at(MIDDLE, 2.0)
	cam.pan_by(Vector2(200, -100))
	_key(KEY_HOME)
	assert_eq(cam.zoom.x, start_zoom)
	assert_eq(cam.position, start_position)

# ================================ Moving ==================================

func test_dragging_moves_the_maze_with_the_mouse():
	var under := cam.screen_to_world(MIDDLE)
	_drag(MOUSE_BUTTON_LEFT, MIDDLE, MIDDLE + Vector2(60, 40))
	assert_almost_eq(cam.screen_to_world(MIDDLE + Vector2(60, 40)), under, Vector2.ONE * 0.01)

func test_a_middle_button_drag_moves_it_from_the_first_pixel():
	_drag(MOUSE_BUTTON_MIDDLE, MIDDLE, MIDDLE + Vector2(3, 0), 1)
	assert_almost_eq(cam.position.x - start_position.x, -3.0 / start_zoom, 0.01)

## Holds `code` down (or lets it go) as far as Input.is_key_pressed knows.
func _hold_key(code: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func test_the_keyboard_moves_it():
	_hold_key(KEY_D, true)
	cam._process(0.5)
	_hold_key(KEY_D, false)
	assert_almost_eq(cam.position.x - start_position.x, MapCamera.KEY_PAN_SPEED * 0.5 / start_zoom, 0.01, "the view moves right")

func test_the_keys_move_it_at_the_same_pace_whatever_the_game_speed():
	_hold_key(KEY_D, true)
	Engine.time_scale = 10.0
	cam._process(0.5 * 10.0)  # half a real second, at x10
	Engine.time_scale = 1.0
	_hold_key(KEY_D, false)
	assert_almost_eq(cam.position.x - start_position.x, MapCamera.KEY_PAN_SPEED * 0.5 / start_zoom, 0.01)

func test_the_maze_cant_be_lost_off_screen():
	var area: Rect2 = main.hud.map_area()
	for push in [Vector2(-100000, 0), Vector2(100000, 0), Vector2(0, -100000), Vector2(0, 100000)]:
		cam.pan_by(push)
		var seen := Rect2(cam.screen_to_world(area.position), area.size / cam.zoom.x)
		var overlap := seen.intersection(cam.maze_rect)
		assert_gte(minf(overlap.size.x, overlap.size.y), MapCamera.KEEP_IN_VIEW - 0.01, "pushed %s" % push)

func test_it_all_works_while_paused():
	get_tree().paused = true
	_button(MOUSE_BUTTON_WHEEL_UP, true, MIDDLE)
	assert_gt(cam.zoom.x, start_zoom)

# ================================ Clicking ================================

func test_a_click_still_picks_whoever_it_lands_on():
	var npc := _npc_in_the_middle()
	_click(_on_screen(npc.global_position))
	assert_eq(main.hud.inspected, npc)

func test_clicks_land_true_when_zoomed_in_and_moved():
	var npc := _npc_in_the_middle()
	cam.zoom_at(MIDDLE + Vector2(-200, 100), 2.5)
	cam.pan_by(Vector2(-150, 60))
	_click(_on_screen(npc.global_position))
	assert_eq(main.hud.inspected, npc)

func test_dragging_from_a_character_doesnt_pick_them():
	var npc := _npc_in_the_middle()
	var at := _on_screen(npc.global_position)
	_drag(MOUSE_BUTTON_LEFT, at, at + Vector2(80, 0))
	assert_null(main.hud.inspected)
	assert_ne(cam.position, start_position, "it moved the view instead")
