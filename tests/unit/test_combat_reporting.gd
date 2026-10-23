extends DungeonTest

## Covers the reporting behind the battle window: what each action in a
## fight did (CombatActions.apply, CombatEvent), and who's fighting whom.

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

## Enough HP all round that nobody in `foe`'s pack falls in a turn or two.
func _toughen_pack() -> void:
	for m in foe.living_pack():
		m.stats.hp = 500
		m.stats.max_hp = 500

# =============================== Reporting ================================

func test_an_action_says_what_it_did():
	set_stats(a, 3, 30, 6, 4)
	var target := NpcStats.new()
	target.hp = 50
	target.max_hp = 50
	var result: Dictionary = CombatActions.apply(a.stats, CombatRules.ATTACK, target)
	assert_eq(result["missed"], result["amount"] == 0)
	assert_eq(target.hp, 50 - result["amount"])
	a.stats.hp = 10
	a.stats.inventory["Health Potion"] = 1
	result = CombatActions.apply(a.stats, CombatRules.POTION, target)
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
		assert_eq(ev.kind, CombatEvent.Kind.ACTION)
		assert_true(ev.actor in [a, b] or ev.actor in foe.living_pack())

func test_a_heal_is_on_the_healer_whoever_they_face():
	var ev := CombatEvent.of_action(a, foe, CombatRules.POTION, 8)
	assert_eq(ev.target, a)
	assert_eq(ev.target_id, a.get_instance_id())
	assert_true(ev.is_heal())

func test_an_event_says_where_things_stand_after_it():
	foe.stats.hp = 0
	var ev := CombatEvent.of_action(a, foe, CombatRules.FIREBALL, 12)
	assert_true(ev.killed)
	assert_eq(ev.target_hp, 0)
	assert_eq(ev.actor_mp, a.stats.mp)

func test_spells_and_heals_are_told_apart():
	assert_true(CombatRules.is_heal(CombatRules.POTION))
	assert_false(CombatRules.is_heal(CombatRules.SPARK))
	assert_true(CombatRules.is_offensive_spell(CombatRules.FIREBALL))
	assert_false(CombatRules.is_offensive_spell(CombatRules.ATTACK))
	assert_eq(CombatActions.killing_blow(a.stats, CombatRules.SPARK, 4), "Spark for 4 damage")

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
	fast_forward()
	PartyOps.join_party_of(b, a)
	for m in [a, b]:
		set_stats(m, 5, 80, 6, 6)
	_toughen_pack()
	hold_everyone_else([a, b] + foe.living_pack())
	main.hud.inspect(a)
	GroupCombat.engage_pack(a, foe.cell_pos, foe)
	await wait_seconds(GroupCombat.TURN_SECONDS + 0.8)
	assert_gt(bw.actions_played, 0, "the first turn's blows have been played")
	assert_false(bw.fighters_on(BattleWindow.Side.FOES).is_empty())
