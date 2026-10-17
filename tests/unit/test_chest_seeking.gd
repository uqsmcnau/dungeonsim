extends GutTest

## Covers chest-seeking around monsters, including a regression test for a
## reported loop: a character would spot a chest, step toward it, find a
## monster in the way and back off, then get pulled straight back toward the
## chest on its next step -- bouncing between the same two cells forever.
## Uses small hand-built mazes so the geometry is exact.

const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")

var main: Node
var npc: NpcAgent

func before_each():
	main = add_child_autofree(load("res://scenes/Main.tscn").instantiate())
	npc = main.npcs[0]
	npc.enemies = {}
	npc.chests = {}
	npc.chest_goal = MazeQuery.NONE
	npc.skipped_chests = {}

## A w x h grid with every wall up.
func _walled_grid(w: int, h: int) -> Array:
	var g: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			row.append(MazeGenerator.WALL_N | MazeGenerator.WALL_E | MazeGenerator.WALL_S | MazeGenerator.WALL_W)
		g.append(row)
	return g

func _open(g: Array, a: Vector2i, b: Vector2i) -> void:
	if b.x > a.x:
		g[a.y][a.x] &= ~MazeGenerator.WALL_E
		g[b.y][b.x] &= ~MazeGenerator.WALL_W
	elif b.x < a.x:
		_open(g, b, a)
	elif b.y > a.y:
		g[a.y][a.x] &= ~MazeGenerator.WALL_S
		g[b.y][b.x] &= ~MazeGenerator.WALL_N
	else:
		_open(g, b, a)

## A dead-straight 1-high corridor: the only way along it is through every cell.
func _corridor(length: int) -> Array:
	var g := _walled_grid(length, 1)
	for x in range(length - 1):
		_open(g, Vector2i(x, 0), Vector2i(x + 1, 0))
	return g

func _place_enemy(cell: Vector2i) -> EnemyAgent:
	var enemy: EnemyAgent = add_child_autofree(ENEMY_SCENE.instantiate())
	enemy.setup(cell, main.CELL_SIZE, 1, npc.grid, npc.enemies, {}, [], false)
	return enemy

func test_routes_around_a_monster_when_another_way_exists():
	# A 3x2 ring with the middle of the top row occupied:
	#   P M C
	#   . . .
	var g := _walled_grid(3, 2)
	_open(g, Vector2i(0, 0), Vector2i(1, 0))
	_open(g, Vector2i(1, 0), Vector2i(2, 0))
	_open(g, Vector2i(0, 0), Vector2i(0, 1))
	_open(g, Vector2i(0, 1), Vector2i(1, 1))
	_open(g, Vector2i(1, 1), Vector2i(2, 1))
	_open(g, Vector2i(2, 1), Vector2i(2, 0))
	npc.grid = g
	npc.cell_pos = Vector2i(0, 0)
	_place_enemy(Vector2i(1, 0))
	npc.chests[Vector2i(2, 0)] = true

	assert_eq(npc._chest_step(), Vector2i(0, 1), "should take the long way round rather than through the monster")

func test_chest_only_reachable_through_a_monster_is_set_aside():
	npc.grid = _corridor(5)
	npc.cell_pos = Vector2i(2, 0)
	_place_enemy(Vector2i(3, 0))
	npc.chests[Vector2i(4, 0)] = true

	assert_eq(npc._chest_step(), npc.cell_pos, "no monster-free route, so no chest step")
	assert_true(npc.skipped_chests.has(Vector2i(4, 0)))

func test_set_aside_chest_does_not_pull_the_character_straight_back():
	# The reported loop: back off one cell, and the old code re-spotted the
	# chest immediately and stepped right back toward the monster.
	npc.grid = _corridor(5)
	npc.cell_pos = Vector2i(2, 0)
	_place_enemy(Vector2i(3, 0))
	npc.chests[Vector2i(4, 0)] = true
	npc._chest_step()

	npc.cell_pos = Vector2i(1, 0)  # backed off
	assert_eq(npc._chest_step(), npc.cell_pos, "should not head back toward the chest yet")
	assert_eq(npc.chest_goal, MazeQuery.NONE)

func test_set_aside_chest_is_tried_again_once_the_skip_runs_out():
	npc.grid = _corridor(5)
	npc.cell_pos = Vector2i(2, 0)
	var enemy := _place_enemy(Vector2i(3, 0))
	npc.chests[Vector2i(4, 0)] = true
	npc._chest_step()

	enemy.defeat()  # the monster in the way is gone
	var step: Vector2i = npc.cell_pos
	for i in range(NpcAgent.CHEST_SKIP_STEPS):
		step = npc._chest_step()
	assert_eq(step, Vector2i(3, 0), "with the way clear again, the chest should be worth going for")

func test_unguarded_chest_is_still_pursued_directly():
	npc.grid = _corridor(5)
	npc.cell_pos = Vector2i(0, 0)
	npc.chests[Vector2i(4, 0)] = true

	assert_eq(npc._chest_step(), Vector2i(1, 0))
	assert_true(npc.skipped_chests.is_empty())
