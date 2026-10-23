extends DungeonTest

## Covers tools/balance.gd's reading of how characters died: it sorts them
## by the very text their gravestones show (NpcAgent.killed_by), so if that
## text changes, the report would quietly count deaths in the wrong place.

const BALANCE := preload("res://tools/balance.gd")

func before_each():
	load_main()

func test_every_kind_of_killer_is_told_apart():
	var boss: EnemyAgent = monster_on(main.exit_cell)
	assert_eq(BALANCE.killer_kind(boss.killer_description()), "the Dragon's party")
	assert_eq(BALANCE.killer_kind(boss.pack[1].killer_description()), "the Dragon's party")
	for cell in main.mid_boss_cells:
		var mid_boss := monster_on(cell)
		var expected := "Ogre Warlords' parties" if mid_boss.kind.name == "Ogre Warlord" else "Orc Chieftains' parties"
		assert_eq(BALANCE.killer_kind(mid_boss.killer_description()), expected)
		assert_eq(BALANCE.killer_kind(mid_boss.pack[1].killer_description()), expected)
	var monster := new_enemy()
	monster.setup(clear_cell(), main.CELL_SIZE, 3, main.grid, {}, {}, [])
	assert_eq(BALANCE.killer_kind(monster.killer_description()), "maze monsters")
	var player: NpcAgent = main.npcs[0]
	assert_eq(BALANCE.killer_kind(player.killer_description()), "other players")
	PartyOps.join_party_of(main.npcs[1], player)
	assert_eq(BALANCE.killer_kind(player.killer_description()), "other players", "one of a party, too")
	assert_eq(BALANCE.killer_kind("the storm"), "the storm")
