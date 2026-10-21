extends DungeonTest

## Covers gravestones: one marks where each fallen character died, clicking
## it brings up their final HUD panel, and that panel says who or what
## killed them and how.

func before_each():
	load_main()
	# As in a real run, everyone's surroundings are discovered before
	# anyone can die there.
	main._process(0.0)

func after_each():
	get_tree().paused = false

func _click(local_pos: Vector2) -> void:
	main._on_world_clicked(main.npc_container.to_global(local_pos))

func _solo(npc: NpcAgent) -> void:
	npc.party = [npc]
	npc.is_party_leader = true
	npc.party_name = ""
	npc.is_moving = false
	npc.stats.inventory.clear()
	npc.stats.equipped.clear()
	npc.stats.known_spells.clear()
	npc.stats.mp = 0
	main.player_map[npc.cell_pos] = npc

# ============================== The gravestone ============================

func test_a_gravestone_marks_where_they_fell():
	var npc: NpcAgent = main.npcs[0]
	var spot: Vector2 = npc.position
	npc.die()
	assert_true(main.graves.has(npc))
	assert_eq(main.graves[npc].position, spot)
	assert_true(main.graves[npc].is_inside_tree())

func test_the_living_have_no_gravestone():
	assert_true(main.graves.is_empty())

func test_clicking_a_gravestone_brings_up_the_dead_players_hud():
	var npc: NpcAgent = main.npcs[0]
	npc.die()
	main._process(0.0)
	_click(main.graves[npc].position)
	assert_eq(main.hud.inspected, npc)
	assert_true(main.hud.inspector["header"].text.contains("DEAD"))

func test_clicking_a_gravestone_works_while_paused():
	var npc: NpcAgent = main.npcs[0]
	npc.die()
	main._process(0.0)
	main.hud.toolbar.set_paused(true)
	_click(main.graves[npc].position)
	assert_eq(main.hud.inspected, npc)

func test_a_living_player_standing_over_a_gravestone_is_picked_first():
	var fallen: NpcAgent = main.npcs[0]
	var living: NpcAgent = main.npcs[1]
	fallen.die()
	main._process(0.0)
	living.position = main.graves[fallen].position
	_click(main.graves[fallen].position)
	assert_eq(main.hud.inspected, living)

func test_a_selected_gravestone_is_ringed():
	var npc: NpcAgent = main.npcs[0]
	npc.die()
	main._process(0.0)
	_click(main.graves[npc].position)
	assert_eq(main.maze_view.selection_center, main.graves[npc].position)
	assert_gt(main.maze_view.selection_radius, 0.0)

func test_clicking_away_from_a_gravestone_deselects():
	var npc: NpcAgent = main.npcs[0]
	npc.die()
	main._process(0.0)
	_click(main.graves[npc].position)
	_click(Vector2(-1000, -1000))
	assert_null(main.hud.inspected)

func test_gravestones_follow_party_vision():
	var npc: NpcAgent = main.npcs[0]
	var watcher: NpcAgent = main.npcs[main.npcs.size() / 2]  # the far side of the maze
	npc.die()
	main._process(0.0)
	assert_true(main.graves[npc].visible, "everyone's view: wherever's been discovered")
	main.hud.inspect(watcher)
	assert_false(main.graves[npc].visible, "somewhere the selected party's never seen")
	assert_null(main.grave_at(main.npc_container.to_global(main.graves[npc].position)), "and a hidden one can't be clicked")

# ============================ How they died ===============================

func test_hud_shows_who_killed_them_and_how():
	var npc: NpcAgent = main.npcs[0]
	npc.die("Bram (Lv.4 Evil)", "Fireball for 12 damage")
	main.hud.inspect(npc)
	assert_eq(main.hud.inspector["action"].text, "Killed by: Bram (Lv.4 Evil)")
	assert_eq(main.hud.inspector["death"].text, "How: Fireball for 12 damage")
	assert_true(main.hud.inspector["death"].visible)

func test_the_living_show_no_cause_of_death():
	main.hud.inspect(main.npcs[0])
	assert_false(main.hud.inspector["death"].visible)
	assert_true(main.hud.inspector["action"].text.begins_with("Action: "))

func test_leaderboard_panel_shows_it_too():
	var npc: NpcAgent = main.npcs[0]
	npc.die("the Boss (Lv.12)", "A hit for 30 damage")
	assert_eq(main.hud.rows[npc]["action"].text, "Killed by: the Boss (Lv.12)")
	assert_eq(main.hud.rows[npc]["death"].text, "How: A hit for 30 damage")

func test_killed_by_a_monster_is_recorded():
	var player: NpcAgent = main.npcs[0]
	_solo(player)
	player.stats.hp = 1
	player.stats.max_hp = 1
	player.stats.dexterity = 1
	var cell := clear_cell()
	var monster := new_enemy()
	monster.setup(cell, main.CELL_SIZE, 4, main.grid, main.enemy_map, {}, [])
	monster.stats.hp = 100000
	monster.in_combat = true
	player.in_pack_combat = true
	player.is_moving = true
	for i in range(100):
		if player.dead:
			break
		player.stats.hp = 1  # in case it drank a potion or recovered
		GroupCombat.resolve_pack_turn([player], cell, player.enemies)
	assert_true(player.dead, "sanity: a 1 HP player should fall to a level 4 monster eventually")
	assert_eq(player.killed_by, "a level 4 monster")
	assert_true(player.death_method.ends_with(" damage"), player.death_method)
	assert_true(player.death_method.begins_with("A hit for ") or player.death_method.begins_with("A critical hit for "), player.death_method)

func test_killed_by_another_player_is_recorded():
	var killer: NpcAgent = main.npcs[0]
	var victim: NpcAgent = main.npcs[1]
	_solo(killer)
	_solo(victim)
	killer.stats.level = 5
	killer.stats.strength = 20
	killer.stats.dexterity = 20
	killer.stats.acquire_item("Iron Sword")
	victim.stats.hp = 1
	victim.stats.max_hp = 1
	for i in range(100):
		if victim.dead:
			break
		victim.stats.hp = 1
		GroupCombat.resolve_pvp_turn(killer.party, victim.party, killer.cell_pos, victim.cell_pos)
	assert_true(victim.dead)
	assert_eq(victim.killed_by, "%s (Lv.5 %s)" % [killer.npc_name, killer.stats.alignment])
	assert_true(victim.death_method.begins_with("Iron Sword for "), victim.death_method)

func test_killer_description_names_their_party():
	var npc: NpcAgent = main.npcs[0]
	PartyOps.join_party_of(main.npcs[1], npc)
	assert_true(npc.killer_description().ends_with(" of %s" % npc.party_name))

func test_killing_blows_name_the_spell_or_weapon():
	var npc: NpcAgent = main.npcs[0]
	npc.stats.equipped.clear()
	assert_eq(npc.killing_blow(CombatRules.FIREBALL, 12), "Fireball for 12 damage")
	assert_eq(npc.killing_blow(CombatRules.SPARK, 5), "Spark for 5 damage")
	assert_eq(npc.killing_blow(CombatRules.ATTACK, 3), "Bare hands for 3 damage")
	npc.stats.acquire_item("Shield")
	assert_eq(npc.killing_blow(CombatRules.ATTACK, 3), "Bare hands for 3 damage", "a shield isn't a weapon")
	npc.stats.acquire_item("Iron Sword")
	assert_eq(npc.killing_blow(CombatRules.ATTACK, 6), "Iron Sword for 6 damage")

func test_monster_killer_descriptions():
	var monster := new_enemy()
	monster.setup(clear_cell(), main.CELL_SIZE, 3, main.grid, {}, {}, [])
	assert_eq(monster.killer_description(), "a level 3 monster")
	monster.is_mini_boss = true
	assert_eq(monster.killer_description(), "a Mini Boss (Lv.3)")
	monster.is_boss = true
	assert_eq(monster.killer_description(), "the Boss (Lv.3)")

func test_pack_monster_killer_description():
	var cell := clear_cell()
	var a := new_enemy()
	var b := new_enemy()
	a.setup(cell, main.CELL_SIZE, 2, main.grid, {}, {}, [])
	b.setup(cell, main.CELL_SIZE, 2, main.grid, {}, {}, [])
	EnemyAgent.form_pack([a, b])
	assert_eq(b.killer_description(), "a level 2 monster (one of a pack of 2)")

func test_the_real_boss_is_marked_as_the_boss():
	var boss: EnemyAgent = main.enemy_map[main.exit_cell]
	assert_true(boss.is_boss)
