extends GutTest

## Covers that PvP combat can never be started in a safe room (a start
## zone, shop, mini boss room, or the boss room -- game_manager's existing
## `restricted_cells`), from both places a fight can be triggered: moving
## toward an opponent (_attempt_move) and finding one already on your own
## cell (the idle safety net in _process).

var main: Node

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())

func _stack_odds(strong: NpcAgent, weak: NpcAgent) -> void:
	strong.stats.hp = 500
	strong.stats.max_hp = 500
	strong.stats.strength = 80
	strong.stats.constitution = 80
	strong.stats.level = 50
	weak.stats.hp = 10
	weak.stats.max_hp = 10
	weak.stats.strength = 3
	weak.stats.constitution = 3
	weak.stats.level = 1

func _clear_cell() -> Vector2i:
	for c in main._unrestricted_cells():
		if not main.enemy_map.has(c) and not main.chest_map.has(c):
			return c
	return Vector2i(-1, -1)

func test_safe_cells_are_wired_to_the_shared_restricted_cells():
	var a: NpcAgent = main.npcs[0]
	assert_eq(a.safe_cells, main.restricted_cells)
	assert_true(a.safe_cells.has(main.start_cells[0]), "a start zone should actually be in safe_cells")

func test_attempt_move_refuses_to_start_pvp_in_a_safe_room():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	_stack_odds(a, b)
	a.stats.alignment = NpcStats.ALIGNMENT_EVIL
	b.stats.alignment = NpcStats.ALIGNMENT_GOOD

	var safe_cell: Vector2i = main.start_cells[0]
	main.player_map[safe_cell] = b
	b.cell_pos = safe_cell
	a.in_pvp_combat = false

	a._attempt_move(safe_cell)

	assert_false(a.in_pvp_combat)
	assert_false(b.in_pvp_combat)

func test_attempt_move_does_start_pvp_for_the_same_matchup_outside_a_safe_room():
	var a: NpcAgent = main.npcs[0]
	var b: NpcAgent = main.npcs[1]
	a.party = [a]
	a.is_party_leader = true
	b.party = [b]
	b.is_party_leader = true
	a.stats.alignment = NpcStats.ALIGNMENT_EVIL
	b.stats.alignment = NpcStats.ALIGNMENT_GOOD
	# Favored but not absurdly so -- strong enough to win, not so lopsided
	# that b's flee check fires before swinging once.
	a.stats.level = 5
	a.stats.hp = 100
	a.stats.max_hp = 100
	a.stats.strength = 20
	a.stats.constitution = 10
	b.stats.level = 1
	b.stats.hp = 40
	b.stats.max_hp = 40
	b.stats.strength = 5
	b.stats.constitution = 10

	var unsafe_cell: Vector2i = _clear_cell()
	main.player_map[unsafe_cell] = b
	b.cell_pos = unsafe_cell
	a.in_pvp_combat = false
	b.in_pvp_combat = false

	a._attempt_move(unsafe_cell)

	assert_true(a.in_pvp_combat and b.in_pvp_combat)

func test_idle_safety_net_refuses_to_start_pvp_in_a_safe_room():
	var c: NpcAgent = main.npcs[2]
	var d: NpcAgent = main.npcs[3]
	_stack_odds(c, d)
	c.stats.alignment = NpcStats.ALIGNMENT_EVIL
	d.stats.alignment = NpcStats.ALIGNMENT_GOOD

	var safe_cell: Vector2i = main.start_cells[0]
	c.cell_pos = safe_cell
	d.cell_pos = safe_cell  # simulate d having wandered onto c's cell
	main.player_map[safe_cell] = d  # what c's _has_live_player(cell_pos) should find -- not itself
	c.in_pvp_combat = false
	d.in_pvp_combat = false

	c._process(0.0)

	assert_false(c.in_pvp_combat)
	assert_false(d.in_pvp_combat)
