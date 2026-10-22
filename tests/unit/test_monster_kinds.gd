extends DungeonTest

## Covers the kinds of monster (MonsterCatalog): one per level -- 1 to 10
## roaming the maze, an Ogre Warlord leading each mini boss's party of
## three, and the Dragon leading the boss's party of four -- each with its
## own name, colour and shape, on the map and in the battle window.

func before_each():
	load_main()

## The monster leading the party on `cell`.
func _party_on(cell: Vector2i) -> EnemyAgent:
	return main.enemy_map[cell]

func _roaming_monsters() -> Array:
	return main.enemy_container.get_children().filter(func(e):
		return e is EnemyAgent and e.alive and e.guarding == "" and not e.is_boss and not e.is_mini_boss)

# ============================== The catalogue =============================

func test_a_kind_for_every_level():
	assert_eq(MonsterCatalog.KINDS.size(), 12)
	var names := {}
	var colors := {}
	var shapes := {}
	for kind in MonsterCatalog.KINDS:
		names[kind["name"]] = true
		colors[kind["color"]] = true
		shapes[[kind["sides"], kind["inner"], kind["turn"], kind["stretch"]]] = true
	assert_eq(names.size(), 12, "each its own name")
	assert_eq(colors.size(), 12, "and colour")
	assert_eq(shapes.size(), 12, "and shape")

func test_levels_past_the_ends_get_the_nearest_kind():
	assert_eq(MonsterCatalog.for_level(0)["name"], "Rat")
	assert_eq(MonsterCatalog.for_level(99)["name"], "Dragon")

func test_names_take_the_right_article():
	assert_eq(MonsterCatalog.called(MonsterCatalog.for_level(6)), "an Orc")
	assert_eq(MonsterCatalog.called(MonsterCatalog.for_level(8)), "a Troll")
	assert_eq(MonsterCatalog.called(MonsterCatalog.for_level(12), true), "the Dragon")

# ================================ The maze ================================

func test_maze_monsters_run_from_level_1_at_the_edge_to_10_by_the_boss_room():
	for start in main.start_cells:
		assert_eq(main.world.enemy_level_for(start), 1, "by start zone %s" % start)
	var outside_boss_room: Vector2i = main.exit_cell + Vector2i(WorldBuilder.BOSS_ROOM_REACH, 0)
	assert_eq(main.world.enemy_level_for(outside_boss_room), MonsterCatalog.MAZE_MAX_LEVEL)
	for monster in _roaming_monsters():
		assert_between(monster.stats.level, 1, MonsterCatalog.MAZE_MAX_LEVEL, monster.kind["name"])

func test_every_monster_is_the_kind_for_its_level():
	for monster in main.enemy_container.get_children():
		assert_eq(monster.kind, MonsterCatalog.for_level(monster.stats.level))

func test_its_kind_shows_on_the_map():
	var monster: EnemyAgent = _roaming_monsters()[0]
	assert_eq(monster.visual.color, monster.kind["color"])
	var icon := MonsterCatalog.outline(monster.kind)
	assert_eq(monster.visual.polygon.size(), icon.size())
	assert_almost_eq(monster.visual.polygon[0], icon[0] * EnemyAgent.ICON_RADIUS, Vector2.ONE * 0.01)

func test_its_level_reads_on_its_icon_however_dark():
	var dragon := _party_on(main.exit_cell)
	assert_eq(dragon.label.get_theme_color("font_color"), Color.WHITE)
	var skeleton := new_enemy()
	skeleton.setup(clear_cell(), main.CELL_SIZE, 5, main.grid, {}, {}, [])
	assert_eq(skeleton.label.get_theme_color("font_color"), Color.BLACK)

# ============================== Boss parties ==============================

func test_each_mini_boss_leads_a_party_of_three():
	assert_eq(main.mini_boss_cells.size(), WorldBuilder.MINI_BOSS_COUNT)
	for cell in main.mini_boss_cells:
		var mini_boss := _party_on(cell)
		assert_true(mini_boss.is_mini_boss)
		assert_eq(mini_boss.kind["name"], "Ogre Warlord")
		assert_eq(mini_boss.stats.level, 11)
		assert_eq(mini_boss.pack.size(), 3)
		for guard in mini_boss.pack.slice(1):
			assert_eq(guard.stats.level, 8)
			assert_eq(guard.kind["name"], "Troll")
		for member in mini_boss.pack:
			assert_false(member.wanders, "the party stays in its room")

func test_the_boss_leads_a_party_of_four():
	var boss := _party_on(main.exit_cell)
	assert_true(boss.is_boss)
	assert_eq(boss.kind["name"], "Dragon")
	assert_eq(boss.stats.level, 12)
	assert_eq(boss.pack.size(), 4)
	for guard in boss.pack.slice(1):
		assert_eq(guard.stats.level, 10)
		assert_eq(guard.kind["name"], "Wyvern")
		assert_false(guard.is_boss, "only the Dragon itself")
	for member in boss.pack:
		assert_false(member.wanders)

func test_a_guard_left_leading_still_holds_the_room():
	var boss := _party_on(main.exit_cell)
	var guard: EnemyAgent = boss.pack[1]
	boss.defeat()
	assert_eq(_party_on(main.exit_cell), guard, "the exit's still blocked")
	assert_true(guard.is_pack_leader)
	assert_false(guard.wanders, "but it never comes out")

func test_a_pack_follower_left_leading_roams_as_usual():
	var cell := clear_cell()
	var leader := new_enemy()
	var follower := new_enemy()
	leader.setup(cell, main.CELL_SIZE, 2, main.grid, main.enemy_map, {}, [])
	follower.setup(cell, main.CELL_SIZE, 2, main.grid, main.enemy_map, {}, [])
	EnemyAgent.form_pack([leader, follower])
	assert_false(follower.wanders, "sanity: tagging along")
	leader.defeat()
	assert_true(follower.wanders)

func test_the_mini_boss_still_drops_a_silver_chest():
	var cell: Vector2i = main.mini_boss_cells[0]
	_party_on(cell).defeat()
	assert_true(main.chest_map.has(cell))

# ============================ In the battle window ========================

func test_monsters_go_by_their_kind_in_battle():
	var boss := _party_on(main.exit_cell)
	var bw: BattleWindow = main.hud.battle_window
	bw.show_fight([main.npcs[0]], boss.living_pack(), "Fighting")
	var names := bw.fighters_on(BattleWindow.Side.FOES).map(func(f): return f.name)
	names.sort()
	assert_eq(names, ["Dragon", "Wyvern", "Wyvern", "Wyvern"])

func test_the_boss_stands_at_the_back_behind_its_guards():
	var boss := _party_on(main.exit_cell)
	var bw: BattleWindow = main.hud.battle_window
	bw.show_fight([main.npcs[0]], boss.living_pack(), "Fighting")
	var dragon_x := 0.0
	var guards_x: Array = []
	for f in bw.fighters_on(BattleWindow.Side.FOES):
		if f.kind == "boss":
			dragon_x = bw._home_of(f).x
		else:
			guards_x.append(bw._home_of(f).x)
	assert_eq(guards_x.size(), 3)
	for x in guards_x:
		assert_lt(x + 30.0, dragon_x, "a guard well in front of the Dragon")
