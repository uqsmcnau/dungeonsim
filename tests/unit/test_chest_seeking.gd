extends DungeonTest

## Covers chest-seeking around monsters, including a regression test for a
## reported loop: a character would spot a chest, step toward it, find a
## monster in the way and back off, then get pulled straight back toward the
## chest on its next step -- bouncing between the same two cells forever.
## Uses small hand-built mazes so the geometry is exact.

var npc: NpcAgent

func before_each():
	load_main()
	npc = main.npcs[0]
	npc.enemies = {}
	npc.chests = {}
	npc.chest_goal = MazeQuery.NONE
	npc.skipped_chests = {}

func _place_enemy(cell: Vector2i) -> EnemyAgent:
	var enemy := new_enemy()
	enemy.setup(cell, main.CELL_SIZE, 1, npc.grid, npc.enemies, {}, [], false)
	return enemy

func test_routes_around_a_monster_when_another_way_exists():
	# A 3x2 ring with the middle of the top row occupied:
	#   P M C
	#   . . .
	var g := walled_grid(3, 2)
	open_between(g, Vector2i(0, 0), Vector2i(1, 0))
	open_between(g, Vector2i(1, 0), Vector2i(2, 0))
	open_between(g, Vector2i(0, 0), Vector2i(0, 1))
	open_between(g, Vector2i(0, 1), Vector2i(1, 1))
	open_between(g, Vector2i(1, 1), Vector2i(2, 1))
	open_between(g, Vector2i(2, 1), Vector2i(2, 0))
	npc.grid = g
	npc.cell_pos = Vector2i(0, 0)
	_place_enemy(Vector2i(1, 0))
	npc.chests[Vector2i(2, 0)] = true

	assert_eq(npc._chest_step(), Vector2i(0, 1), "should take the long way round rather than through the monster")

func test_chest_only_reachable_through_a_monster_is_set_aside():
	npc.grid = corridor(5)
	npc.cell_pos = Vector2i(2, 0)
	_place_enemy(Vector2i(3, 0))
	npc.chests[Vector2i(4, 0)] = true

	assert_eq(npc._chest_step(), npc.cell_pos, "no monster-free route, so no chest step")
	assert_true(npc.skipped_chests.has(Vector2i(4, 0)))

func test_set_aside_chest_does_not_pull_the_character_straight_back():
	# The reported loop: back off one cell, and the old code re-spotted the
	# chest immediately and stepped right back toward the monster.
	npc.grid = corridor(5)
	npc.cell_pos = Vector2i(2, 0)
	_place_enemy(Vector2i(3, 0))
	npc.chests[Vector2i(4, 0)] = true
	npc._chest_step()

	npc.cell_pos = Vector2i(1, 0)  # backed off
	assert_eq(npc._chest_step(), npc.cell_pos, "should not head back toward the chest yet")
	assert_eq(npc.chest_goal, MazeQuery.NONE)

func test_set_aside_chest_is_tried_again_once_the_skip_runs_out():
	npc.grid = corridor(5)
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
	npc.grid = corridor(5)
	npc.cell_pos = Vector2i(0, 0)
	npc.chests[Vector2i(4, 0)] = true

	assert_eq(npc._chest_step(), Vector2i(1, 0))
	assert_true(npc.skipped_chests.is_empty())
