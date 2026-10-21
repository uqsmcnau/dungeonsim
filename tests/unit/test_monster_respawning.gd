extends DungeonTest

## Covers monster respawning: each area of the maze slowly gets back
## monsters it has lost -- one encounter per RESPAWN_SECONDS, never past
## the number it started with, and only out of every player's sight and
## well away from all of them.

func before_each():
	load_main()

func after_each():
	get_tree().paused = false

## The area with the most monsters, not counting the center's (the boss
## room's), whose corner of the maze is easy to keep everyone away from.
func _busiest_area() -> Vector2i:
	var best := Vector2i(-1, -1)
	var center_area: Vector2i = main.respawner.area_of(main.exit_cell)
	for area in main.respawner.area_capacity:
		if area == center_area:
			continue
		if best == Vector2i(-1, -1) or main.respawner.area_capacity[area] > main.respawner.area_capacity[best]:
			best = area
	return best

## Moves every player to the corner of the maze furthest from `area`, so
## none of them can see into it or is anywhere near.
func _park_players_far_from(area: Vector2i) -> void:
	var middle: int = main.MAZE_WIDTH / MonsterRespawner.AREA_SIZE / 2
	var corner := Vector2i(
		main.MAZE_WIDTH - 1 if area.x < middle else 0,
		main.MAZE_HEIGHT - 1 if area.y < middle else 0)
	main.player_map.clear()
	for npc in main.npcs:
		npc.cell_pos = corner
		npc.look_around()

## The cell in the middle of `area`.
func _middle_of(area: Vector2i) -> Vector2i:
	var half := MonsterRespawner.AREA_SIZE / 2
	return area * MonsterRespawner.AREA_SIZE + Vector2i(half, half)

func _monsters_in(area: Vector2i) -> Array:
	var result: Array = []
	for enemy in main.enemy_container.get_children():
		if not (enemy is EnemyAgent and enemy.alive) or enemy.is_boss or enemy.is_mini_boss:
			continue
		if main.respawner.area_of(enemy.home_cell) == area:
			result.append(enemy)
	return result

func _kill(monsters: Array) -> void:
	for m in monsters:
		m.defeat()

func _population(area: Vector2i) -> int:
	return int(main.respawner.area_populations().get(area, 0))

# ============================== Capacity ==================================

func test_each_area_remembers_how_many_monsters_it_started_with():
	var total := 0
	for area in main.respawner.area_capacity:
		assert_eq(main.respawner.area_capacity[area], _monsters_in(area).size())
		total += main.respawner.area_capacity[area]
	assert_gt(total, 0)

func test_bosses_and_mini_bosses_dont_count():
	var regular := 0
	for enemy in main.enemy_container.get_children():
		if enemy is EnemyAgent and not enemy.is_boss and not enemy.is_mini_boss:
			regular += 1
	var total := 0
	for area in main.respawner.area_capacity:
		total += main.respawner.area_capacity[area]
	assert_eq(total, regular)

func test_a_full_area_gets_nothing_more():
	var area := _busiest_area()
	_park_players_far_from(area)
	for i in range(10):
		main.respawner.tick_respawns(MonsterRespawner.RESPAWN_SECONDS)
	assert_eq(_population(area), main.respawner.area_capacity[area])

# ============================== Respawning ================================

func test_lost_monsters_come_back_once_their_time_is_up():
	var area := _busiest_area()
	_park_players_far_from(area)
	_kill(_monsters_in(area))
	main.respawner.tick_respawns(MonsterRespawner.RESPAWN_SECONDS - 1.0)
	assert_eq(_population(area), 0, "not yet")
	main.respawner.tick_respawns(1.0)
	assert_gt(_population(area), 0)

func test_an_area_is_restored_slowly_one_encounter_at_a_time():
	var area := _busiest_area()
	_park_players_far_from(area)
	_kill(_monsters_in(area))
	main.respawner.tick_respawns(MonsterRespawner.RESPAWN_SECONDS)
	var after_one: int = _population(area)
	assert_between(after_one, 1, 3, "one lone monster or one pack")
	main.respawner.tick_respawns(MonsterRespawner.RESPAWN_SECONDS / 2.0)
	assert_eq(_population(area), after_one, "nothing more until the next interval")

func test_an_area_never_goes_over_its_original_population():
	var area := _busiest_area()
	assert_gte(main.respawner.area_capacity[area], 2, "sanity: room for a pack")
	_park_players_far_from(area)
	_kill(_monsters_in(area))
	for i in range(60):
		main.respawner.tick_respawns(MonsterRespawner.RESPAWN_SECONDS)
		assert_lte(_population(area), main.respawner.area_capacity[area])
	assert_eq(_population(area), main.respawner.area_capacity[area], "and is fully restored in the end")

func test_one_missing_monster_comes_back_alone_not_as_a_pack():
	var area := _busiest_area()
	_park_players_far_from(area)
	_kill([_monsters_in(area)[0]])
	for i in range(5):
		main.respawner.tick_respawns(MonsterRespawner.RESPAWN_SECONDS)
	assert_eq(_population(area), main.respawner.area_capacity[area])

func test_respawned_monsters_are_as_strong_as_the_area_calls_for():
	var area := _busiest_area()
	_park_players_far_from(area)
	_kill(_monsters_in(area))
	main.respawner.tick_respawns(MonsterRespawner.RESPAWN_SECONDS)
	for m in _monsters_in(area):
		var level: int = main.world.enemy_level_for(m.home_cell)
		if m.pack.size() > 1:
			level = max(1, int(round(level * WorldBuilder.PACK_LEVEL_SCALE)))
		assert_eq(m.stats.level, level)

func test_respawning_is_checked_once_a_second_without_losing_time():
	var area := _busiest_area()
	_park_players_far_from(area)
	_kill(_monsters_in(area))
	main._process(MonsterRespawner.RESPAWN_SECONDS - 0.5)
	main._process(0.4)  # not yet a second since the last check
	assert_eq(_population(area), 0)
	main._process(0.6)  # the check now counts both frames' time
	assert_gt(_population(area), 0)

func test_respawning_stops_while_paused():
	var area := _busiest_area()
	_park_players_far_from(area)
	_kill(_monsters_in(area))
	main.hud.toolbar.set_paused(true)
	await get_tree().create_timer(0.3, true).timeout
	assert_eq(_population(area), 0)

# ======================== Out of the players' sight =======================

func test_no_respawn_where_a_player_could_see_it_happen():
	var area := _busiest_area()
	_park_players_far_from(area)
	_kill(_monsters_in(area))
	# One player stands in the middle of the area: nowhere in it is far enough away.
	var watcher: NpcAgent = main.npcs[0]
	watcher.cell_pos = _middle_of(area)
	watcher.look_around()
	assert_eq(main.respawner.hidden_spawn_cell(area), MazeQuery.NONE)
	for i in range(5):
		main.respawner.tick_respawns(MonsterRespawner.RESPAWN_SECONDS)
	assert_eq(_population(area), 0)

func test_respawn_waits_for_the_player_to_leave():
	var area := _busiest_area()
	_park_players_far_from(area)
	_kill(_monsters_in(area))
	var watcher: NpcAgent = main.npcs[0]
	var parked: Vector2i = watcher.cell_pos
	watcher.cell_pos = _middle_of(area)
	watcher.look_around()
	main.respawner.tick_respawns(MonsterRespawner.RESPAWN_SECONDS)
	assert_eq(_population(area), 0)
	watcher.cell_pos = parked
	watcher.look_around()
	main.respawner.tick_respawns(MonsterRespawner.RESPAWN_RETRY_SECONDS)
	assert_gt(_population(area), 0, "tries again shortly after, not a whole interval later")

func test_spawn_cells_are_hidden_far_from_players_and_free():
	var area := _busiest_area()
	_park_players_far_from(area)
	# A player just beside the area rules out its near side, not all of it.
	var watcher: NpcAgent = main.npcs[0]
	var side_x: int = area.x * MonsterRespawner.AREA_SIZE - 3 if area.x > 0 else (area.x + 1) * MonsterRespawner.AREA_SIZE + 2
	watcher.cell_pos = Vector2i(side_x, area.y * MonsterRespawner.AREA_SIZE + MonsterRespawner.AREA_SIZE / 2)
	watcher.look_around()
	var found := 0
	for i in range(30):
		var c: Vector2i = main.respawner.hidden_spawn_cell(area)
		if c == MazeQuery.NONE:
			continue
		found += 1
		assert_eq(main.respawner.area_of(c), area)
		assert_false(watcher.sight_cells.has(c), "out of sight")
		var distance: int = max(abs(c.x - watcher.cell_pos.x), abs(c.y - watcher.cell_pos.y))
		assert_gte(distance, MonsterRespawner.RESPAWN_MIN_PLAYER_DISTANCE, "and well away")
		assert_false(main.restricted_cells.has(c) or main.enemy_map.has(c) or main.chest_map.has(c))
	assert_gt(found, 0, "sanity: the far side of the area is still fair game")

func test_respawned_monsters_stay_hidden_in_the_fog():
	var area := _busiest_area()
	_park_players_far_from(area)
	_kill(_monsters_in(area))
	main._process(MonsterRespawner.RESPAWN_SECONDS)
	var respawned := _monsters_in(area)
	assert_gt(respawned.size(), 0)
	for m in respawned:
		assert_false(m.visible, "nobody can see it")
