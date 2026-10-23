extends DungeonTest

## Covers what counts as explored: anywhere the party has been or seen (see
## NpcRoutes.explored), pooled across the party -- and, since the exit in
## plain sight would then never be walked onto, heading for it once seen
## and clear (see NpcAgent._exit_step).

var a: NpcAgent
var b: NpcAgent
var players: Dictionary = {}

func before_each():
	load_main()
	a = main.npcs[0]
	b = main.npcs[1]

## A in the middle of a corridor five cells long, at (2, 0), with nothing
## explored but its own cell.
func _mid_corridor() -> Array:
	var g := corridor(5)
	isolate(a, g, Vector2i(2, 0), players)
	return g

# =============================== Seen ======================================

func test_ground_its_seen_counts_as_explored():
	var g := _mid_corridor()
	a.seen_cells[Vector2i(0, 0)] = true
	a.seen_cells[Vector2i(1, 0)] = true
	for i in range(20):
		assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(g, a.cell_pos)), Vector2i(3, 0),
			"not down the end it can already see")

func test_whichever_end_that_is():
	var g := _mid_corridor()
	a.seen_cells[Vector2i(3, 0)] = true
	a.seen_cells[Vector2i(4, 0)] = true
	for i in range(20):
		assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(g, a.cell_pos)), Vector2i(1, 0))

func test_the_frontier_is_the_edge_of_what_its_seen():
	# Its neighbours are both in sight; only past them is anything new.
	var g := _mid_corridor()
	for c in cells_along(0, 3):
		a.seen_cells[c] = true
	assert_eq(NpcRoutes.toward_frontier(a), Vector2i(3, 0), "towards (4, 0), the one cell it hasn't seen")

func test_what_a_party_mate_saw_counts_too():
	var g := _mid_corridor()
	isolate(b, g, Vector2i(0, 0), players)
	b.seen_cells[Vector2i(3, 0)] = true
	b.seen_cells[Vector2i(4, 0)] = true
	PartyOps.pool_seen_cells([a, b])
	for i in range(20):
		assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(g, a.cell_pos)), Vector2i(1, 0),
			"not over ground its party-mate covered before they teamed up")

func test_with_everything_seen_it_walks_what_it_hasnt_been_over():
	# Rather than pace about at random: there may yet be a monster to fight
	# there, or a chest.
	var g := _mid_corridor()
	for c in cells_along(0, 4):
		a.seen_cells[c] = true
	a.visited[Vector2i(3, 0)] = true
	a.visited[Vector2i(4, 0)] = true
	for i in range(20):
		assert_eq(NpcRoutes.explore(a, MazeQuery.open_neighbors(g, a.cell_pos)), Vector2i(1, 0))

# =============================== The exit ==================================

## A at one end of a corridor six cells long, the exit at the other, and
## all of it in sight.
func _exit_in_sight() -> Vector2i:
	var g := corridor(6)
	isolate(a, g, Vector2i(0, 0), players)
	a.exit_cell = Vector2i(5, 0)
	for c in cells_along(0, 5):
		a.seen_cells[c] = true
	return a.exit_cell

func test_it_heads_for_the_exit_once_its_seen_it():
	_exit_in_sight()
	assert_eq(a._exit_step(), Vector2i(1, 0))
	a._take_step()
	assert_eq(a.current_action, "Heading for the exit")

func test_but_not_before():
	var exit := _exit_in_sight()
	a.seen_cells.erase(exit)
	assert_eq(a._exit_step(), a.cell_pos)

func test_nor_while_the_boss_holds_it():
	# That's a fight, not a walk: see test_hunting.gd.
	var exit := _exit_in_sight()
	var boss := new_enemy()
	boss.setup(exit, main.CELL_SIZE, 1, a.grid, a.enemies, {}, [], false)
	assert_eq(a._exit_step(), a.cell_pos)
