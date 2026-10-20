extends DungeonTest

## Covers the battle window (BattleWindow), bottom left: the selected party
## and whoever they're fighting, with every blow of the fight played out in
## turn, Final Fantasy-style -- and the reporting behind it (each action's
## combat_event; see GroupCombat._report).

var bw: BattleWindow
var a: NpcAgent
var b: NpcAgent
var foe: EnemyAgent

func before_each():
	load_main()
	bw = main.hud.battle_window
	a = main.npcs[0]
	b = main.npcs[1]
	foe = main.enemy_map.values()[0]
	foe.stats.hp = 30
	foe.stats.max_hp = 30

## Puts `party` and `foes` in the window directly, as GameManager would.
func _scene(party: Array, foes: Array, status: String = "Exploring", on_the_move: bool = false) -> void:
	bw.show_fight(party, foes, status, on_the_move)

## An event as GroupCombat._report would send it, after `amount` damage
## (or healing) has been dealt -- `extra` overrides any of it.
func _event(actor: Node, target: Node, action: String, amount: int, extra: Dictionary = {}) -> Dictionary:
	var ev := {
		"kind": "action", "actor": actor, "target": target, "action": action,
		"amount": amount, "missed": false, "crit": false,
		"target_hp": maxi(0, target.stats.hp - amount), "target_max_hp": target.stats.max_hp,
		"actor_mp": actor.stats.mp, "killed": false,
	}
	ev.merge(extra, true)
	return ev

func _popup_texts() -> Array:
	return bw.popups.map(func(p): return p["text"])

## Enough HP all round that nobody in `foe`'s pack falls in a turn or two.
func _toughen_pack() -> void:
	for m in foe.living_pack():
		m.stats.hp = 500
		m.stats.max_hp = 500

# ================================ Layout ==================================

func test_the_window_sits_in_the_bottom_left_corner():
	var column: VBoxContainer = main.hud.selection_container
	assert_eq(bw.offset_left, column.offset_left, "lined up with the left column")
	assert_gte(bw.offset_top, column.offset_bottom, "below it")
	assert_almost_eq(bw.offset_bottom, 1060.0, 1.0, "down in the corner")
	assert_lt(bw.offset_right, 480.0, "clear of the maze")

func test_nobody_selected_means_an_empty_field():
	main._process(0.0)
	assert_true(bw.fighters.is_empty())

# ================================ Who's there =============================

func test_the_selected_party_stands_on_the_left():
	PartyOps.join_party_of(b, a)
	main.hud.inspect(a)
	main._process(0.0)
	var party := bw.fighters_on(BattleWindow.Side.PARTY)
	assert_eq(party.map(func(f): return f["name"]), [a.npc_name, b.npc_name])
	assert_true(bw.fighters_on(BattleWindow.Side.FOES).is_empty(), "nobody to fight")
	assert_lt(bw._home_of(party[0]).x, bw.size.x / 2.0)

func test_the_leader_is_front_and_centre_with_the_rest_above_and_below():
	var c: NpcAgent = main.npcs[2]
	_scene([a, b, c], [])
	var leader_at: Vector2 = bw._home_of(bw.fighter_of(a))
	var above: Vector2 = bw._home_of(bw.fighter_of(b))
	var below: Vector2 = bw._home_of(bw.fighter_of(c))
	assert_lt(above.y, leader_at.y)
	assert_gt(below.y, leader_at.y)
	assert_almost_eq(leader_at.y - above.y, below.y - leader_at.y, 0.5, "evenly either side")
	assert_gt(leader_at.x, above.x, "the leader a step in front")

func test_everyone_stands_on_the_floor():
	var party: Array = main.npcs.slice(0, 5)
	_scene(party, [main.npcs[5], main.npcs[6], main.npcs[7]])
	for f in bw.fighters.values():
		var feet := bw._feet_of(f)
		assert_gt(feet, BattleWindow.FLOOR_TOP, "%s's feet below the back wall" % f["name"])
		assert_lte(feet, BattleWindow.FIELD_HEIGHT, "%s's feet above the boxes" % f["name"])

func test_further_back_is_drawn_smaller():
	var party: Array = main.npcs.slice(0, 5)
	_scene(party, [])
	var back: Dictionary = bw.fighter_of(party[3])  # the top spot
	var front: Dictionary = bw.fighter_of(party[4])  # the bottom one
	assert_lt(bw._depth_of(back), bw._depth_of(front))

func test_the_game_lists_the_leader_first_even_with_a_follower_selected():
	PartyOps.join_party_of(b, a)
	main.hud.inspect(b)
	main._process(0.0)
	assert_eq(bw.fighter_of(a)["slot"], 0, "the leader takes the centre")

func test_a_new_leader_steps_up_to_the_centre():
	# The old leader falls; whoever takes over swaps spots with them.
	var c: NpcAgent = main.npcs[2]
	_scene([a, b, c], [foe])
	var b_spot: int = bw.fighter_of(b)["slot"]
	bw.play(_event(foe, a, "attack", a.stats.hp, {"killed": true}))
	bw.advance(0.01)
	_scene([b, c], [foe])
	assert_eq(bw.fighter_of(b)["slot"], 0)
	assert_eq(bw.fighter_of(a)["slot"], b_spot, "the fallen one lies where b stood")

func test_a_monster_pack_they_fight_appears_opposite():
	main.hud.inspect(a)
	a.in_pack_combat = true
	foe.in_combat = true
	foe.fighting_party = a.party
	main._process(0.0)
	var foes := bw.fighters_on(BattleWindow.Side.FOES)
	assert_eq(foes.size(), foe.living_pack().size())
	assert_gt(bw._home_of(foes[0]).x, bw.size.x / 2.0)
	assert_eq(foes[0]["kind"], "boss" if foe.is_boss else ("mini_boss" if foe.is_mini_boss else "monster"))

func test_a_rival_party_appears_opposite_in_a_player_fight():
	var c: NpcAgent = main.npcs[2]
	PartyOps.join_party_of(c, b)
	main.hud.inspect(a)
	a.in_pvp_combat = true
	a.pvp_foes = b.party
	main._process(0.0)
	assert_eq(bw.fighters_on(BattleWindow.Side.FOES).map(func(f): return f["name"]), [b.npc_name, c.npc_name])

func test_selecting_someone_else_starts_the_scene_over():
	_scene([a], [foe])
	_scene([b], [])
	assert_true(bw.fighter_of(a).is_empty())
	assert_false(bw.fighter_of(b).is_empty())
	assert_eq(bw.fighter_of(b)["enter"], 0.0, "there at once rather than walking in")

func test_someone_joining_walks_in():
	_scene([a], [])
	_scene([a, b], [])
	assert_gt(bw.fighter_of(b)["enter"], 0.0)

func test_hp_follows_their_stats_between_fights():
	_scene([a], [])
	a.stats.hp = 7
	_scene([a], [])
	assert_eq(bw.fighter_of(a)["hp"], 7)

func test_they_face_each_other():
	_scene([a], [b])
	assert_gt(bw._facing_of(bw.fighter_of(a)), 0.0, "the party faces right")
	assert_lt(bw._facing_of(bw.fighter_of(b)), 0.0, "their foes left")

# ================================== Gear ==================================

func _wearing(items: Array) -> NpcStats:
	var stats := NpcStats.new()
	for item in items:
		stats.acquire_item(item)
	return stats

func test_nothing_worn_is_a_bare_fisted_tunic():
	assert_eq(BattleWindow.look_of(NpcStats.new()), {
		"weapon": "", "off_hand": "", "armor": "",
		"helmet": false, "boots": false, "amulet": false, "ring": false,
	})

func test_everything_worn_shows():
	var look := BattleWindow.look_of(_wearing(["Iron Sword", "Shield", "Leather Armor", "Helmet", "Leather Boots", "Sage's Amulet", "Silver Ring"]))
	assert_eq(look["weapon"], "iron_sword")
	assert_eq(look["off_hand"], "shield")
	assert_eq(look["armor"], "leather")
	for part in ["helmet", "boots", "amulet", "ring"]:
		assert_true(look[part], part)

func test_silver_gear_looks_the_part():
	var look := BattleWindow.look_of(_wearing(["Steel Sword", "Silver Shield", "Chainmail"]))
	assert_eq(look["weapon"], "steel_sword")
	assert_eq(look["off_hand"], "silver_shield")
	assert_eq(look["armor"], "chainmail")

func test_a_tome_is_held_in_the_off_hand():
	assert_eq(BattleWindow.look_of(_wearing(["Arcane Tome"]))["off_hand"], "tome")
	assert_eq(BattleWindow.look_of(_wearing(["Arcane Tome"]))["weapon"], "", "no sword: it's held out in front instead")

func test_two_swords_carry_both():
	var look := BattleWindow.look_of(_wearing(["Iron Sword", "Steel Sword"]))
	assert_eq(look["weapon"], "steel_sword", "the better one in front")
	assert_eq(look["off_hand"], "iron_sword")

func test_new_gear_shows_on_their_figure():
	a.stats.equipped.clear()
	_scene([a], [])
	assert_false(bw.fighter_of(a)["look"]["helmet"])
	a.stats.acquire_item("Helmet")
	_scene([a], [])
	assert_true(bw.fighter_of(a)["look"]["helmet"])

func test_a_rival_players_gear_shows_too():
	b.stats.equipped.clear()
	b.stats.acquire_item("Steel Sword")
	_scene([a], [b])
	assert_eq(bw.fighter_of(b)["look"]["weapon"], "steel_sword")

# ================================ Walking =================================

func test_on_the_move_they_walk_and_the_scenery_scrolls_past():
	_scene([a, b], [], "Exploring", true)
	bw.advance(0.1)
	assert_true(bw.walking)
	assert_gt(bw._walk_phase, 0.0)

func test_they_keep_walking_between_steps():
	# A step ends a frame or two before the next begins.
	_scene([a], [], "Exploring", true)
	bw.advance(0.05)
	_scene([a], [], "Exploring", false)
	bw.advance(0.05)
	assert_true(bw.walking)

func test_once_they_stop_so_does_the_scenery():
	_scene([a], [], "Resting", true)
	bw.advance(0.1)
	_scene([a], [], "Resting", false)
	bw.advance(BattleWindow.WALK_HOLD_SECONDS)
	assert_false(bw.walking)
	var phase := bw._walk_phase
	bw.advance(0.5)
	assert_eq(bw._walk_phase, phase)

func test_nobody_walks_mid_fight():
	_scene([a], [foe], "Fighting", true)
	bw.advance(0.1)
	assert_false(bw.walking)

func test_the_game_says_when_the_party_is_stepping():
	main.hud.inspect(a)
	a.slide_to(a.position + Vector2(20, 0), 0.5)
	main._process(0.0)
	bw.advance(0.01)
	assert_true(bw.walking)

# =============================== Playing out ==============================

func test_a_blow_is_played_out_when_its_turn_comes():
	_scene([a], [foe])
	bw.play(_event(a, foe, "attack", 7))
	assert_eq(bw.fighter_of(foe)["hp"], 30, "not before it's played")
	bw.advance(0.01)
	assert_eq(bw.fighter_of(foe)["hp"], 23, "HP drops as it lands")
	assert_has(_popup_texts(), "7")
	assert_gt(bw.fighter_of(a)["lunge"], 0.0, "the attacker steps forward")

func test_hp_waits_for_the_blow_to_be_played():
	# The game deals the damage at once; the window shows it as it lands.
	_scene([a], [foe])
	bw.play(_event(a, foe, "attack", 7))
	foe.stats.hp = 23
	_scene([a], [foe])
	assert_eq(bw.fighter_of(foe)["hp"], 30)

func test_blows_are_played_one_after_another():
	_scene([a], [foe])
	for i in range(3):
		bw.play(_event(a, foe, "attack", 1))
	bw.advance(0.01)
	assert_eq(bw.actions_played, 1)
	bw.advance(BattleWindow.ACTION_GAP)
	assert_eq(bw.actions_played, 2)
	bw.advance(BattleWindow.ACTION_GAP)
	assert_eq(bw.actions_played, 3)

func test_misses_crits_and_heals_read_differently():
	_scene([a], [foe])
	bw.play(_event(a, foe, "attack", 0, {"missed": true}))
	bw.play(_event(foe, a, "attack", 9, {"crit": true}))
	bw.play(_event(a, a, "recover", 5))
	for i in range(3):
		bw.advance(BattleWindow.ACTION_GAP)
	assert_eq(_popup_texts(), ["Miss", "9!", "+5"])

func test_spells_are_announced():
	_scene([a], [foe])
	bw.play(_event(a, foe, "fireball", 12))
	bw.advance(0.01)
	assert_eq(bw.caption, "Fireball")
	bw.advance(BattleWindow.CAPTION_SECONDS)
	assert_eq(bw.caption, "", "and the caption clears")

func test_numbers_on_the_same_target_stack_rather_than_overlap():
	_scene([a, b], [foe])
	bw.play(_event(a, foe, "attack", 3))
	bw.play(_event(b, foe, "attack", 4))
	bw.advance(0.01)
	bw.advance(BattleWindow.MIN_ACTION_GAP)
	bw.advance(BattleWindow.ACTION_GAP)
	assert_eq(bw.popups.size(), 2)
	assert_ne(bw.popups[0]["pos"], bw.popups[1]["pos"])

func test_blows_in_other_fights_are_ignored():
	_scene([a], [])
	var c: NpcAgent = main.npcs[2]
	bw.play(_event(b, c, "attack", 3))
	bw.advance(0.01)
	assert_eq(bw.actions_played, 0)

# ============================== How it ends ===============================

func test_a_slain_monster_dissolves_and_its_the_partys_victory():
	_scene([a], [foe])
	bw.play(_event(a, foe, "attack", 30, {"killed": true}))
	bw.advance(0.01)
	assert_gte(bw.fighter_of(foe)["dissolve"], 0.0)
	_scene([a], [])  # the game's done with it
	assert_eq(bw.fighter_of(foe)["leave"], -1.0, "it doesn't walk off as well")
	bw.advance(BattleWindow.DISSOLVE_SECONDS + 0.5)
	assert_true(bw.fighter_of(foe).is_empty(), "gone once dissolved")
	assert_eq(bw.banner, "Victory!")
	assert_gt(bw.fighter_of(a)["hop"], 0.0, "and a hop for joy")

func test_foes_who_go_unbeaten_walk_off_without_a_victory():
	_scene([a], [foe])
	_scene([a], [])
	assert_gt(bw.fighter_of(foe)["leave"], 0.0)
	bw.advance(BattleWindow.LEAVE_SECONDS + 0.1)
	assert_true(bw.fighter_of(foe).is_empty())
	assert_eq(bw.banner, "")

func test_a_fleeing_party_has_escaped():
	_scene([a], [foe])
	bw.play({"kind": "escape", "actor": a})
	bw.advance(0.01)
	assert_eq(bw.banner, "Escaped!")
	assert_gt(bw.fighter_of(a)["run"], 0.0)
	_scene([a], [])
	bw.advance(BattleWindow.LEAVE_SECONDS + 0.1)
	assert_ne(bw.banner, "Victory!")

func test_a_fallen_party_member_lies_there_until_after_the_fight():
	_scene([a, b], [foe])
	bw.play(_event(foe, b, "attack", b.stats.hp, {"killed": true}))
	bw.advance(0.01)
	assert_true(bw.fighter_of(b)["ko"])
	_scene([a], [foe])  # b's no longer one of the living
	assert_false(bw.fighter_of(b).is_empty(), "still lying there mid-fight")
	assert_eq(bw.fighters_on(BattleWindow.Side.PARTY).size(), 2)
	bw.play(_event(a, foe, "attack", 30, {"killed": true}))
	bw.advance(BattleWindow.ACTION_GAP)
	_scene([a], [])
	bw.advance(BattleWindow.DISSOLVE_SECONDS + 0.5)
	assert_false(bw.fighter_of(b).is_empty(), "for a moment after it")
	bw.advance(BattleWindow.FALLEN_LINGER_SECONDS + 0.1)
	assert_true(bw.fighter_of(b).is_empty())

func test_a_fallen_rival_lies_down_rather_than_dissolving():
	_scene([a], [b])
	bw.play(_event(a, b, "attack", b.stats.hp, {"killed": true}))
	bw.advance(0.01)
	assert_true(bw.fighter_of(b)["ko"])
	assert_lt(bw.fighter_of(b)["dissolve"], 0.0)

func test_fighters_keep_their_spot_when_one_falls():
	var c: NpcAgent = main.npcs[2]
	_scene([a], [b, c])
	var spot: Vector2 = bw._home_of(bw.fighter_of(c))
	bw.play(_event(a, b, "attack", b.stats.hp, {"killed": true}))
	bw.advance(0.01)
	_scene([a], [c])
	assert_eq(bw._home_of(bw.fighter_of(c)), spot)

func test_the_selected_character_fallen_stays_in_view():
	# GameManager keeps listing them, fallen -- so they stay lying there
	# rather than being cleared away with the rest of the fallen.
	_scene([a], [foe])
	bw.play(_event(foe, a, "attack", a.stats.hp, {"killed": true}))
	bw.advance(0.01)
	a.die()
	_scene([a], [])
	bw.advance(BattleWindow.LEAVE_SECONDS + 0.1)
	assert_eq(bw.banner, "Defeated...")
	bw.advance(BattleWindow.FALLEN_LINGER_SECONDS + 0.5)
	_scene([a], [])
	assert_true(bw.fighter_of(a)["ko"])
	assert_eq(bw.fighter_of(a)["enter"], 0.0, "lying there, not walking back in")

func test_it_pauses_with_the_game():
	get_tree().paused = true
	assert_false(bw.can_process())
	get_tree().paused = false

# =============================== Reporting ================================

func test_an_action_says_what_it_did():
	set_stats(a, 3, 30, 6, 4)
	var target := NpcStats.new()
	target.hp = 50
	target.max_hp = 50
	var result: Dictionary = a.apply_combat_action("attack", target)
	assert_eq(result["missed"], result["amount"] == 0)
	assert_eq(target.hp, 50 - result["amount"])
	a.stats.hp = 10
	a.stats.mp = 20
	result = a.apply_combat_action("recover", target)
	assert_eq(result["amount"], a.stats.hp - 10, "the HP healed")

func test_a_pack_fight_turn_reports_every_action():
	PartyOps.join_party_of(b, a)
	for m in [a, b]:
		set_stats(m, 5, 80, 6, 6)
		m.in_pack_combat = true
		m.is_moving = true
	_toughen_pack()
	foe.in_combat = true
	foe.fighting_party = a.party
	var events: Array = []
	for m in [a, b]:
		m.combat_event.connect(func(ev): events.append(ev))
	GroupCombat.resolve_pack_turn(a.party, foe.cell_pos, main.enemy_map)
	assert_eq(events.size(), 2 + foe.living_pack().size(), "one per party member, one per monster")
	for ev in events:
		assert_eq(ev["kind"], "action")
		assert_true(ev["actor"] in [a, b] or ev["actor"] in foe.living_pack())

func test_a_heal_is_reported_on_the_healer():
	PartyOps.join_party_of(b, a)
	set_stats(a, 5, 80, 6, 6)
	a.stats.hp = 10  # low enough to heal rather than attack
	a.stats.mp = 50
	var events: Array = []
	a.combat_event.connect(func(ev): events.append(ev))
	GroupCombat._report(a, a, foe, "recover", {"amount": 8, "missed": false})
	assert_eq(events[0]["target"], a)

func test_who_theyre_fighting_can_be_looked_up():
	assert_eq(GroupCombat.opponents_of(a, main.enemy_map), [], "nobody, between fights")
	a.in_pack_combat = true
	foe.in_combat = true
	foe.fighting_party = a.party
	assert_eq(GroupCombat.opponents_of(a, main.enemy_map), foe.living_pack())
	a.in_pack_combat = false
	GroupCombat.engage_players(a, b.cell_pos, b)
	assert_eq(GroupCombat.opponents_of(a, main.enemy_map), [b])
	assert_eq(GroupCombat.opponents_of(b, main.enemy_map), [a])
	GroupCombat.release_pvp(a.party, b.party)
	assert_eq(GroupCombat.opponents_of(a, main.enemy_map), [])

func test_joining_a_player_fight_takes_on_the_same_foes():
	var c: NpcAgent = main.npcs[2]
	GroupCombat.engage_players(a, b.cell_pos, b)
	PartyOps.join_party_of(c, a)
	assert_eq(GroupCombat.opponents_of(c, main.enemy_map), [b])

func test_the_selected_partys_fight_plays_out_in_the_window():
	PartyOps.join_party_of(b, a)
	for m in [a, b]:
		set_stats(m, 5, 80, 6, 6)
	_toughen_pack()
	main.hud.inspect(a)
	GroupCombat.engage_pack(a, foe.cell_pos, foe)
	await wait_seconds(GroupCombat.TURN_SECONDS + 0.8)
	assert_gt(bw.actions_played, 0, "the first turn's blows have been played")
	assert_false(bw.fighters_on(BattleWindow.Side.FOES).is_empty())
