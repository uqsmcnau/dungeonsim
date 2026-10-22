extends DungeonTest

## Covers Follow Mode: the toolbar toggle that keeps the selected party in
## the middle of the view as it moves about -- gliding over to whoever's
## picked, staying on them through zooming, and switching itself off the
## moment the spectator moves the view by hand.

var cam: MapCamera
var npc: NpcAgent

func before_each():
	load_main()
	cam = main.camera
	npc = main.npcs[0]
	cam.zoom_at(Vector2(960, 540), 3.0)  # in close, with room to move about

func after_each():
	get_tree().paused = false

## Where the middle of the view area is looking, in world space.
func _looking_at() -> Vector2:
	return cam.screen_to_world(main.hud.map_area().get_center())

## Lets the camera settle -- several real seconds' worth in one go.
func _settle() -> void:
	cam._process(5.0 * Engine.time_scale)

func _on(target: NpcAgent) -> bool:
	return _looking_at().distance_to(target.global_position) < 1.0

func test_its_off_to_start_with():
	assert_false(main.follow_mode)
	assert_false(main.hud.toolbar.follow_toggle.button_pressed)
	assert_false(cam.following)

func test_the_toggle_turns_it_on_and_off():
	main.hud.toolbar.follow_toggle.button_pressed = true
	assert_true(main.follow_mode)
	assert_true(cam.following)
	main.hud.toolbar.follow_toggle.button_pressed = false
	assert_false(cam.following)

func test_it_glides_over_to_whoever_is_selected():
	main.set_follow_mode(true)
	click_on(npc)
	cam._process(0.05)
	assert_false(_on(npc), "glides rather than jumping")
	_settle()
	assert_true(_on(npc), "%s in the middle of the view" % npc.npc_name)

func test_and_keeps_up_as_they_move():
	main.set_follow_mode(true)
	click_on(npc)
	_settle()
	npc.position += Vector2(3, 2) * main.CELL_SIZE
	main._sync_selection_highlight()
	_settle()
	assert_true(_on(npc))

func test_it_follows_the_party_leader():
	var follower: NpcAgent = main.npcs[1]
	PartyOps.join_party_of(follower, npc)
	main.set_follow_mode(true)
	main.hud.inspect(follower)
	_settle()
	assert_true(_on(npc), "the middle of the party, where its ring is")

func test_it_follows_a_fallen_character_to_their_grave():
	main.set_follow_mode(true)
	click_on(npc)
	npc.die("a test", "Tested")
	main._sync_selection_highlight()
	_settle()
	assert_lt(_looking_at().distance_to(main.graves[npc].global_position), 1.0)

func test_with_nobody_selected_the_view_stays_put():
	main.set_follow_mode(true)
	var before := cam.position
	_settle()
	assert_eq(cam.position, before)

func test_off_the_view_doesnt_follow():
	click_on(npc)
	var before := cam.position
	_settle()
	assert_eq(cam.position, before)

func test_zooming_keeps_them_in_the_middle():
	main.set_follow_mode(true)
	click_on(npc)
	_settle()
	cam.zoom_at(Vector2(500, 900), MapCamera.ZOOM_STEP)  # the cursor well off to one side
	assert_true(_on(npc), "zoomed about them, not the cursor")
	assert_true(cam.following)

func test_dragging_the_view_turns_it_off():
	main.set_follow_mode(true)
	click_on(npc)
	_settle()
	cam.pan_by(Vector2(40, 0))
	assert_false(main.follow_mode)
	assert_false(cam.following)
	assert_false(main.hud.toolbar.follow_toggle.button_pressed, "the toggle unticks to match")
	var before := cam.position
	_settle()
	assert_eq(cam.position, before, "and the view stays where it was put")

func test_home_turns_it_off_too():
	main.set_follow_mode(true)
	var home := InputEventKey.new()
	home.keycode = KEY_HOME
	home.pressed = true
	cam._unhandled_input(home)
	assert_false(main.follow_mode)

func test_it_works_while_paused():
	main.hud.toolbar.set_paused(true)
	main.hud.toolbar.follow_toggle.button_pressed = true
	click_on(npc)
	_settle()
	assert_true(_on(npc))

func test_it_keeps_pace_at_any_game_speed():
	main.set_follow_mode(true)
	click_on(npc)
	var start := cam.position
	cam._process(0.1)
	var at_normal_speed := cam.position - start
	cam.position = start
	Engine.time_scale = 10.0
	cam._process(0.1 * 10.0)  # the same tenth of a real second, at x10
	Engine.time_scale = 1.0
	assert_almost_eq(cam.position - start, at_normal_speed, Vector2.ONE * 0.01)
