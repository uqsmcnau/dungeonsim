extends GutTest

## Covers the "Players left" counter on the top toolbar.

var main: Node

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())

func test_counter_starts_at_full_headcount():
	main._process(0.0)
	var n: int = main.npcs.size()
	assert_eq(main.hud.players_left_label.text, "Players left: %d / %d" % [n, n])

func test_counter_drops_when_a_player_dies():
	var n: int = main.npcs.size()
	main.npcs[0].die()
	main._process(0.0)
	assert_eq(main.hud.players_left_label.text, "Players left: %d / %d" % [n - 1, n])

func test_counter_reaches_zero_when_everyone_has_fallen():
	var n: int = main.npcs.size()
	# Copy first -- each death erases itself from main.npcs.
	for npc in main.npcs.duplicate():
		npc.die()
	main._process(0.0)
	assert_eq(main.hud.players_left_label.text, "Players left: 0 / %d" % n)
