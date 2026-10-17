extends GutTest

## Covers parties seeking each other out: two parties in line of sight that
## both want to team up head toward each other (ahead of shops, chests and
## exploring), and one stuck in a fight gets walked over to instead. Uses
## small hand-built mazes, with the two characters isolated on their own
## maps so the rest of the running simulation can't interfere.

const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")

var main: Node
var a: NpcAgent
var b: NpcAgent
var players: Dictionary = {}

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())
	a = main.npcs[0]
	b = main.npcs[1]
	players = {}
	var enemies: Dictionary = {}
	for npc in [a, b]:
		main.player_map.erase(npc.cell_pos)
		npc.players = players
		npc.enemies = enemies
		npc.chests = {}
		npc.shops = {}
		npc.known_shops = {}
		npc.visited = {}
		npc.party = [npc]
		npc.is_party_leader = true
		npc.finished = false
		npc.is_moving = false
		npc.stats.alignment = NpcStats.ALIGNMENT_GOOD
		npc.stats.inventory.clear()

func _walled_grid(w: int, h: int) -> Array:
	var g: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			row.append(MazeGenerator.WALL_N | MazeGenerator.WALL_E | MazeGenerator.WALL_S | MazeGenerator.WALL_W)
		g.append(row)
	return g

func _open(g: Array, p: Vector2i, q: Vector2i) -> void:
	if q.x > p.x:
		g[p.y][p.x] &= ~MazeGenerator.WALL_E
		g[q.y][q.x] &= ~MazeGenerator.WALL_W
	elif q.x < p.x:
		_open(g, q, p)
	elif q.y > p.y:
		g[p.y][p.x] &= ~MazeGenerator.WALL_S
		g[q.y][q.x] &= ~MazeGenerator.WALL_N
	else:
		_open(g, q, p)

func _corridor(length: int) -> Array:
	var g := _walled_grid(length, 1)
	for x in range(length - 1):
		_open(g, Vector2i(x, 0), Vector2i(x + 1, 0))
	return g

## A 3x2 ring: the top row is a straight line of sight from (0,0) to
## (2,0), and the bottom row is the long way round.
func _ring() -> Array:
	var g := _walled_grid(3, 2)
	_open(g, Vector2i(0, 0), Vector2i(1, 0))
	_open(g, Vector2i(1, 0), Vector2i(2, 0))
	_open(g, Vector2i(0, 0), Vector2i(0, 1))
	_open(g, Vector2i(0, 1), Vector2i(1, 1))
	_open(g, Vector2i(1, 1), Vector2i(2, 1))
	_open(g, Vector2i(2, 1), Vector2i(2, 0))
	return g

func _place(npc: NpcAgent, cell: Vector2i, g: Array) -> void:
	npc.grid = g
	npc.cell_pos = cell
	npc.position = Vector2((cell.x + 0.5) * main.CELL_SIZE, (cell.y + 0.5) * main.CELL_SIZE)
	npc.visited[cell] = true
	players[cell] = npc

func test_two_willing_parties_in_sight_head_toward_each_other():
	var g := _corridor(5)
	_place(a, Vector2i(0, 0), g)
	_place(b, Vector2i(4, 0), g)

	assert_eq(a._party_up_step(), Vector2i(1, 0))
	assert_eq(b._party_up_step(), Vector2i(3, 0), "both sides close the gap")

func test_teaming_up_takes_priority_over_a_chest():
	# Chest one way, a willing party the other.
	var g := _corridor(7)
	_place(a, Vector2i(3, 0), g)
	_place(b, Vector2i(6, 0), g)
	a.chests[Vector2i(0, 0)] = true

	a._take_step()
	assert_eq(a.current_action, "Heading to join %s" % b.npc_name)

func test_teaming_up_takes_priority_over_exploring_a_side_branch():
	# A T-junction: an unexplored branch right next to `a` going one way,
	# the other party down the corridor the other way.
	var t := _walled_grid(5, 2)
	for x in range(4):
		_open(t, Vector2i(x, 0), Vector2i(x + 1, 0))
	_open(t, Vector2i(0, 0), Vector2i(0, 1))
	_place(a, Vector2i(0, 0), t)
	_place(b, Vector2i(4, 0), t)

	assert_eq(a._party_up_step(), Vector2i(1, 0), "toward the other party, not into the unexplored branch")

func test_routes_around_a_monster_between_them():
	var g := _ring()
	_place(a, Vector2i(0, 0), g)
	_place(b, Vector2i(2, 0), g)
	var enemy: EnemyAgent = add_child_autofree(ENEMY_SCENE.instantiate())
	enemy.setup(Vector2i(1, 0), main.CELL_SIZE, 1, g, a.enemies, {}, [], false)

	assert_eq(a._party_up_step(), Vector2i(0, 1), "the long way round, not through the monster")

func test_ignores_parties_out_of_line_of_sight():
	var g := _ring()
	g[0][1] |= MazeGenerator.WALL_E  # wall off the straight line between them
	g[0][2] |= MazeGenerator.WALL_W
	_place(a, Vector2i(0, 0), g)
	_place(b, Vector2i(2, 0), g)

	assert_eq(a._party_up_step(), a.cell_pos)

func test_ignores_parties_that_could_not_merge():
	var g := _corridor(5)
	_place(a, Vector2i(0, 0), g)
	_place(b, Vector2i(4, 0), g)
	b.stats.alignment = NpcStats.ALIGNMENT_EVIL

	assert_eq(a._party_up_step(), a.cell_pos, "Good and Evil never band together")

func test_does_not_approach_when_either_side_would_rather_fight():
	var g := _corridor(5)
	_place(a, Vector2i(0, 0), g)
	_place(b, Vector2i(4, 0), g)
	a.stats.alignment = NpcStats.ALIGNMENT_EVIL
	b.stats.alignment = NpcStats.ALIGNMENT_EVIL
	b.stats.strength += 10  # b fancies its chances against a

	assert_true(b._decide_pvp_fight(a), "sanity: b would attack a on contact")
	assert_false(a._wants_to_party_with(b), "a would be walking into a fight, not a team-up")
	assert_false(b._wants_to_party_with(a))

func test_ignores_finished_characters():
	var g := _corridor(5)
	_place(a, Vector2i(0, 0), g)
	_place(b, Vector2i(4, 0), g)
	b.finished = true

	assert_eq(a._party_up_step(), a.cell_pos)

func test_heads_toward_a_party_stuck_in_a_fight():
	var g := _corridor(5)
	_place(a, Vector2i(0, 0), g)
	_place(b, Vector2i(4, 0), g)
	b.in_pack_combat = true
	b.is_moving = true

	assert_eq(a._party_up_step(), Vector2i(1, 0), "b can't come to a, so a goes to b")

func test_two_parties_in_sight_actually_meet_and_merge():
	var g := _corridor(6)
	_place(a, Vector2i(0, 0), g)
	_place(b, Vector2i(5, 0), g)
	await wait_seconds(3.0)

	assert_same(a.party, b.party, "they should have met and merged into one party")

func test_walks_over_and_joins_a_party_stuck_in_a_fight():
	var g := _corridor(5)
	_place(a, Vector2i(0, 0), g)
	_place(b, Vector2i(4, 0), g)
	b.in_pack_combat = true
	b.is_moving = true
	await wait_seconds(3.0)

	assert_true(b.party.has(a), "a should have walked over and joined b's fight")
	assert_true(b.is_party_leader, "the fighter stays in charge of its fight")
	assert_true(a.in_pack_combat)

func test_merging_on_a_shared_cell_leaves_the_host_registered():
	# Both stepped onto the same cell at once: whoever arrived last
	# overwrote the other's registration. Merging used to erase that
	# entry and leave nobody registered there at all.
	var g := _corridor(3)
	_place(a, Vector2i(1, 0), g)
	_place(b, Vector2i(1, 0), g)  # b's registration overwrites a's
	PartyOps.join_party_of(b, a)

	assert_eq(players.get(Vector2i(1, 0)), a)
