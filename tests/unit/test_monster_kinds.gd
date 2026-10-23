extends DungeonTest

## Covers the kinds of monster (MonsterCatalog): one per level -- 1 to 10
## roaming the maze, an Ogre Warlord leading each mid boss's party of
## three, and the Dragon leading the boss's party of four -- each with its
## own name, colour and shape, on the map and in the battle window.

func before_each():
	load_main()

func _roaming_monsters() -> Array:
	return main.enemy_container.get_children().filter(func(e):
		return e is EnemyAgent and e.alive and e.guarding == "" and not e.is_boss and not e.is_mid_boss)

# ============================== The catalogue =============================

func test_a_kind_for_every_level():
	assert_eq(MonsterCatalog.kinds.size(), 12)
	var names := {}
	var colors := {}
	var shapes := {}
	for kind in MonsterCatalog.kinds:
		names[kind.name] = true
		colors[kind.color] = true
		shapes[[kind.sides, kind.inner, kind.turn, kind.stretch]] = true
	assert_eq(names.size(), 12, "each its own name")
	assert_eq(colors.size(), 12, "and colour")
	assert_eq(shapes.size(), 12, "and shape")

func test_levels_past_the_ends_get_the_nearest_kind():
	assert_eq(MonsterCatalog.for_level(0).name, "Rat")
	assert_eq(MonsterCatalog.for_level(99).name, "Dragon")

func test_names_take_the_right_article():
	assert_eq(MonsterCatalog.for_level(6).called(), "an Orc")
	assert_eq(MonsterCatalog.for_level(8).called(), "a Troll")
	assert_eq(MonsterCatalog.for_level(12).called(true), "the Dragon")

# ================================ The maze ================================

func test_maze_monsters_run_from_level_1_at_the_edge_to_10_by_the_boss_room():
	for start in main.start_cells:
		assert_eq(main.world.enemy_level_for(start), 1, "by start zone %s" % start)
	var outside_boss_room: Vector2i = main.exit_cell + Vector2i(WorldBuilder.BOSS_ROOM_REACH, 0)
	assert_eq(main.world.enemy_level_for(outside_boss_room), MonsterCatalog.MAZE_MAX_LEVEL)
	for monster in _roaming_monsters():
		assert_between(monster.stats.level, 1, MonsterCatalog.MAZE_MAX_LEVEL, monster.kind.name)

func test_every_monster_is_the_kind_for_its_level():
	for monster in main.enemy_container.get_children():
		if monster.kind != MonsterCatalog.orc_chieftain:
			assert_eq(monster.kind, MonsterCatalog.for_level(monster.stats.level))

func test_bar_the_orc_chieftains():
	var chieftains: Array = main.enemy_container.get_children().filter(func(e): return e.kind == MonsterCatalog.orc_chieftain)
	assert_eq(chieftains.size(), WorldBuilder.CHIEFTAIN_COUNT)
	for chieftain in chieftains:
		assert_true(chieftain.is_mid_boss, "each leads a mid boss's party")
		assert_eq(chieftain.stats.level, 6, "an Orc's level, but its own kind")
		assert_eq(chieftain.visual.color, MonsterCatalog.orc_chieftain.color)

func test_its_kind_shows_on_the_map():
	var monster: EnemyAgent = _roaming_monsters()[0]
	assert_eq(monster.visual.color, monster.kind.color)
	var icon := monster.kind.outline()
	assert_eq(monster.visual.polygon.size(), icon.size())
	assert_almost_eq(monster.visual.polygon[0], icon[0] * EnemyAgent.ICON_RADIUS, Vector2.ONE * 0.01)

func test_its_level_reads_on_its_icon_however_dark():
	var dragon := monster_on(main.exit_cell)
	assert_eq(dragon.label.get_theme_color("font_color"), Color.WHITE)
	var skeleton := new_enemy()
	skeleton.setup(clear_cell(), main.CELL_SIZE, 5, main.grid, {}, {}, [])
	assert_eq(skeleton.label.get_theme_color("font_color"), Color.BLACK)

# ============================== Boss parties ==============================

## The mid bosses (both tiers) whose leader is `kind_name`.
func _mid_bosses(kind_name: String) -> Array:
	return main.mid_boss_cells.map(func(c): return monster_on(c)).filter(func(b): return b.kind.name == kind_name)

func test_each_ogre_warlord_leads_a_party_of_three_near_the_middle():
	var warlords := _mid_bosses("Ogre Warlord")
	assert_eq(warlords.size(), WorldBuilder.WARLORD_COUNT)
	for warlord in warlords:
		assert_true(warlord.is_mid_boss)
		assert_eq(warlord.stats.level, 11)
		assert_eq(warlord.pack.size(), 3)
		for guard in warlord.pack.slice(1):
			assert_eq(guard.stats.level, 8)
			assert_eq(guard.kind.name, "Troll")
		for member in warlord.pack:
			assert_false(member.wanders, "the party stays in its room")
		assert_between(from_middle(warlord.cell_pos), WorldBuilder.WARLORD_REACH.x - 1.0, WorldBuilder.WARLORD_REACH.y + 1.0)

func test_each_orc_chieftain_leads_a_weaker_party_of_three_near_the_edge():
	var chieftains := _mid_bosses("Orc Chieftain")
	assert_eq(chieftains.size(), WorldBuilder.CHIEFTAIN_COUNT)
	var nearest := INF
	for chieftain in chieftains:
		assert_eq(chieftain.pack.size(), 3)
		for guard in chieftain.pack.slice(1):
			assert_eq(guard.stats.level, 3)
			assert_eq(guard.kind.name, "Bat")
			assert_eq(guard.killer_description(), "a Bat (Lv.3), guarding an Orc Chieftain")
		for member in chieftain.pack:
			assert_false(member.wanders)
		assert_between(from_middle(chieftain.cell_pos), WorldBuilder.CHIEFTAIN_REACH.x - 1.0, WorldBuilder.CHIEFTAIN_REACH.y + 1.0)
		nearest = minf(nearest, from_middle(chieftain.cell_pos))
	for warlord in _mid_bosses("Ogre Warlord"):
		assert_lt(from_middle(warlord.cell_pos), nearest, "every Ogre Warlord nearer the middle than any Orc Chieftain")

func test_the_boss_leads_a_party_of_four():
	var boss := monster_on(main.exit_cell)
	assert_true(boss.is_boss)
	assert_eq(boss.kind.name, "Dragon")
	assert_eq(boss.stats.level, 12)
	assert_eq(boss.pack.size(), 4)
	for guard in boss.pack.slice(1):
		assert_eq(guard.stats.level, 10)
		assert_eq(guard.kind.name, "Wyvern")
		assert_false(guard.is_boss, "only the Dragon itself")
	for member in boss.pack:
		assert_false(member.wanders)

func test_a_guard_left_leading_still_holds_the_room():
	var boss := monster_on(main.exit_cell)
	var guard: EnemyAgent = boss.pack[1]
	boss.defeat()
	assert_eq(monster_on(main.exit_cell), guard, "the exit's still blocked")
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

# ============================ In the battle window ========================

func test_monsters_go_by_their_kind_in_battle():
	var boss := monster_on(main.exit_cell)
	var bw: BattleWindow = main.hud.battle_window
	bw.show_fight([main.npcs[0]], boss.living_pack(), "Fighting")
	var names := bw.fighters_on(BattleWindow.Side.FOES).map(func(f): return f.name)
	names.sort()
	assert_eq(names, ["Dragon", "Wyvern", "Wyvern", "Wyvern"])

func test_the_boss_stands_at_the_back_behind_its_guards():
	var boss := monster_on(main.exit_cell)
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
