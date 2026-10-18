extends DungeonTest

## Covers the HUD pause/resume button: it pauses the whole SceneTree, while
## itself (and the fog toggle) stay usable so the game can be resumed.

func before_each():
	load_main()

func after_each():
	# A paused tree would freeze GUT itself for every later test.
	get_tree().paused = false

func test_pause_button_pauses_and_resumes_the_tree():
	main.hud.pause_button.toggled.emit(true)
	assert_true(get_tree().paused)
	assert_eq(main.hud.pause_button.text, "Resume")

	main.hud.pause_button.toggled.emit(false)
	assert_false(get_tree().paused)
	assert_eq(main.hud.pause_button.text, "Pause")

func _press_space() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	get_viewport().push_input(event)
	var release := event.duplicate()
	release.pressed = false
	get_viewport().push_input(release)

func test_spacebar_pauses_and_resumes():
	_press_space()
	assert_true(get_tree().paused, "Space should pause")
	assert_eq(main.hud.pause_button.text, "Resume")

	_press_space()
	assert_false(get_tree().paused, "Space should resume, even though the tree is paused")
	assert_eq(main.hud.pause_button.text, "Pause")

func test_spacebar_still_pauses_after_clicking_the_fog_checkbox():
	# Clicking normally gives a button keyboard focus, and Space would then
	# press *that* button instead -- toggling fog rather than pausing. The
	# toolbar buttons must never take focus for that to be impossible.
	assert_eq(main.hud.fog_toggle.focus_mode, Control.FOCUS_NONE)
	assert_eq(main.hud.pause_button.focus_mode, Control.FOCUS_NONE)
	main.hud.fog_toggle.pressed.emit()  # simulate the click
	_press_space()
	assert_true(get_tree().paused)
	assert_true(main.hud.fog_toggle.button_pressed, "fog should be untouched")

func test_pause_and_fog_controls_stay_processable_while_paused():
	main.hud.set_paused(true)
	assert_true(main.hud.pause_button.can_process(), "the pause button must still work to resume")
	assert_true(main.hud.fog_toggle.can_process())
	assert_false(main.npcs[0].can_process(), "characters should freeze while paused")

func test_toggling_fog_while_paused_updates_chest_visibility_immediately():
	main.hud.set_paused(true)
	main.hud.fog_toggle.button_pressed = false
	for cell in main.chest_map:
		assert_true(main.chest_map[cell].visible, "with fog off every chest should show even though _process isn't running")
