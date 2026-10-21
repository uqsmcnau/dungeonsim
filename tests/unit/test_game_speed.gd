extends DungeonTest

## Covers the toolbar's game speed button: stepping up through x1, x2, x5
## and x10 on a click and back down on a right-click, running the whole game
## that much faster -- and leaving the engine at normal speed once the game
## is gone.

var hud: Hud

func before_each():
	load_main()
	hud = main.hud

func after_each():
	get_tree().paused = false

func _right_click_speed_button() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	hud.speed_button.gui_input.emit(event)

func test_it_starts_at_normal_speed():
	assert_eq(hud.speed_button.text, "Speed x1")
	assert_eq(Engine.time_scale, 1.0)

func test_clicks_step_up_to_ten_times():
	var seen: Array = []
	for i in range(3):
		hud.speed_button.pressed.emit()
		seen.append(hud.speed_button.text)
		assert_eq(Engine.time_scale, hud.game_speed)
	assert_eq(seen, ["Speed x2", "Speed x5", "Speed x10"])
	assert_eq(Engine.time_scale, 10.0)

func test_no_faster_than_ten():
	for i in range(6):
		hud.speed_button.pressed.emit()
	assert_eq(Engine.time_scale, 10.0)
	assert_eq(hud.speed_button.text, "Speed x10")

func test_a_right_click_slows_it_back_down():
	main.set_game_speed(10.0)
	_right_click_speed_button()
	assert_eq(Engine.time_scale, 5.0)
	assert_eq(hud.speed_button.text, "Speed x5")
	for i in range(5):
		_right_click_speed_button()
	assert_eq(Engine.time_scale, 1.0, "no slower than normal")

func test_it_can_be_changed_while_paused():
	hud.set_paused(true)
	assert_eq(hud.speed_button.process_mode, Node.PROCESS_MODE_ALWAYS)
	hud.speed_button.pressed.emit()
	assert_eq(Engine.time_scale, 2.0)

## Game seconds (by the storm's clock) per real second, over a little under
## half a real second -- long enough for Godot's frame-time smoothing to
## catch up with a change of speed.
func _pace() -> float:
	await wait_frames(5)
	var game_before: float = main.storm.elapsed
	var real_before := Time.get_ticks_usec()
	while Time.get_ticks_usec() - real_before < 400000:
		await wait_frames(1)
	return (main.storm.elapsed - game_before) / ((Time.get_ticks_usec() - real_before) / 1000000.0)

func test_the_game_runs_faster():
	main.set_game_speed(10.0)
	assert_gt(await _pace(), 6.0, "the storm (and everything else) at ten times the pace")
	main.set_game_speed(1.0)
	assert_lt(await _pace(), 1.5)

func test_normal_speed_once_the_game_is_gone():
	main.set_game_speed(10.0)
	main.free()
	assert_eq(Engine.time_scale, 1.0)
