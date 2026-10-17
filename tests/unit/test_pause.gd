extends GutTest

## Covers the HUD pause/resume button: it pauses the whole SceneTree, while
## itself (and the fog toggle) stay usable so the game can be resumed.

var main: Node

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())

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
