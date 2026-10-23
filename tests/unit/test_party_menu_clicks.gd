extends DungeonTest

## Covers selecting a party-mate of the selected character by clicking
## them: their name in the battle window's party menu (see
## BattleWindow.member_clicked, BattlePainter.party_row_at) or their panel
## below the selected one's in the left column -- just as clicking them on
## the map or the leaderboard does.

var a: NpcAgent
var b: NpcAgent

func before_each():
	load_main()
	a = main.npcs[0]
	b = main.npcs[1]
	hold_everyone_else([a, b])
	PartyOps.join_party_of(b, a)
	main.hud.inspect(a)
	await get_tree().process_frame

func after_each():
	get_tree().paused = false
	await get_tree().process_frame  # panels a click discarded are freed at the frame's end

## Where on screen line `row` of the party menu is (0 for the first): on the
## name, a little way in from the box's left edge.
func _menu_line(row: int) -> Vector2:
	var bw: BattleWindow = main.hud.battle_window
	var baseline := BattleWindow.FIELD_HEIGHT + 4.0 + BattlePainter.PARTY_FIRST_ROW + row * BattlePainter.MENU_ROW
	return bw.get_global_rect().position + Vector2(30.0, baseline - 5.0)

# ============================= Battle window ==============================

func test_the_party_menu_lists_the_leader_then_the_rest():
	var party: Array = main.hud.battle_window.fighters_on(BattleWindow.Side.PARTY)
	assert_eq(party.map(func(f): return f.id), [a.get_instance_id(), b.get_instance_id()], "sanity")

func test_clicking_a_name_in_the_party_menu_selects_them():
	click_screen_at(_menu_line(1))
	assert_eq(main.hud.inspected, b, "as clicking them on the map does")

func test_and_back_again():
	click_screen_at(_menu_line(1))
	assert_eq(main.hud.inspected, b, "sanity")
	await get_tree().process_frame
	click_screen_at(_menu_line(0))
	assert_eq(main.hud.inspected, a)

func test_it_works_while_paused_too():
	get_tree().paused = true
	click_screen_at(_menu_line(1))
	assert_eq(main.hud.inspected, b)

func test_a_click_below_the_names_selects_nobody_new():
	click_screen_at(_menu_line(3))
	assert_eq(main.hud.inspected, a)

func test_only_the_names_count():
	var bw: BattleWindow = main.hud.battle_window
	var line_y := _menu_line(1).y - bw.get_global_rect().position.y
	assert_eq(BattlePainter.party_row_at(bw.size, Vector2(30.0, line_y), 2), 1, "sanity: B's name")
	assert_eq(BattlePainter.party_row_at(bw.size, Vector2(30.0, 40.0), 2), -1, "the field above")
	assert_eq(BattlePainter.party_row_at(bw.size, Vector2(bw.size.x - 20.0, line_y), 2), -1, "the foes' box")

# ============================== Left column ===============================

func test_clicking_a_party_mates_panel_selects_them():
	var panel: PanelContainer = main.hud.party_panels[b]["panel"]
	click_screen_at(panel.get_global_rect().get_center())
	assert_eq(main.hud.inspected, b)
