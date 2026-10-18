class_name DungeonTest
extends GutTest

## Shared groundwork for DungeonSim's tests: extend this instead of GutTest.
## Lives outside tests/unit so GUT doesn't collect it as a test script.

const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")

## The full game scene, for tests that need the generated maze or the whole
## roster (see load_main). Freed after each test.
var main: Node

## Instantiates the whole game -- maze, characters, monsters, HUD -- as
## `main`. Usually called from before_each.
func load_main() -> Node:
	main = add_child_autofree(MAIN_SCENE.instantiate())
	return main

## A fresh monster, not yet set up (call setup() on it), freed after the test.
func new_enemy() -> EnemyAgent:
	return add_child_autofree(ENEMY_SCENE.instantiate())

## A cell outside every safe zone with no monster or chest already on it --
## a quiet place to stage something. (Unrestricted alone isn't enough: a
## monster or chest there would short-circuit the code under test.)
func clear_cell() -> Vector2i:
	for c in main.world.unrestricted_cells():
		if not main.enemy_map.has(c) and not main.chest_map.has(c):
			return c
	return Vector2i(-1, -1)

## Sets the stats a fight hinges on. Keep deltas moderate (e.g. one side
## about 2x the other): with wildly lopsided stats the weaker side flees on
## turn one, before the thing under test ever happens.
func set_stats(npc: NpcAgent, level: int, hp: int, strength: int, constitution: int, dexterity: int = 10) -> void:
	npc.stats.level = level
	npc.stats.hp = hp
	npc.stats.max_hp = hp
	npc.stats.strength = strength
	npc.stats.constitution = constitution
	npc.stats.dexterity = dexterity
	npc.stats.mp = 0

## Ranks main.npcs[0..count-1] by index for the leaderboard -- npcs[count-1]
## strongest -- and everyone else below them all.
func rank_npcs_by_index(count: int) -> void:
	for i in range(main.npcs.size()):
		var npc: NpcAgent = main.npcs[i]
		npc.stats.strength = 1
		npc.stats.constitution = 1
		npc.stats.attack_bonus = 0
		npc.stats.defense_bonus = 0
		npc.stats.max_hp = 1
	for i in range(count):
		var npc: NpcAgent = main.npcs[i]
		npc.stats.attack_bonus = i * 10
		npc.stats.max_hp = 10 + i * 10

## Left-clicks `npc`'s icon on the map, as the spectator would.
func click_on(npc: NpcAgent) -> void:
	main._on_world_clicked(npc.global_position)

# =========================== Hand-built mazes =============================

## A w x h maze with every wall up; knock passages through with open_between.
static func walled_grid(w: int, h: int) -> Array:
	var g: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			row.append(MazeGenerator.WALL_N | MazeGenerator.WALL_E | MazeGenerator.WALL_S | MazeGenerator.WALL_W)
		g.append(row)
	return g

## Opens the passage between two neighbouring cells, from both sides.
static func open_between(g: Array, a: Vector2i, b: Vector2i) -> void:
	if b.x > a.x:
		g[a.y][a.x] &= ~MazeGenerator.WALL_E
		g[b.y][b.x] &= ~MazeGenerator.WALL_W
	elif b.x < a.x:
		open_between(g, b, a)
	elif b.y > a.y:
		g[a.y][a.x] &= ~MazeGenerator.WALL_S
		g[b.y][b.x] &= ~MazeGenerator.WALL_N
	else:
		open_between(g, b, a)

## A single row of `length` cells, open end to end.
static func corridor(length: int) -> Array:
	var g := walled_grid(length, 1)
	for x in range(length - 1):
		open_between(g, Vector2i(x, 0), Vector2i(x + 1, 0))
	return g

## 3x2 ring: straight along the top, or the long way round the bottom.
static func ring_maze() -> Array:
	var g := walled_grid(3, 2)
	open_between(g, Vector2i(0, 0), Vector2i(1, 0))
	open_between(g, Vector2i(1, 0), Vector2i(2, 0))
	open_between(g, Vector2i(0, 0), Vector2i(0, 1))
	open_between(g, Vector2i(0, 1), Vector2i(1, 1))
	open_between(g, Vector2i(1, 1), Vector2i(2, 1))
	open_between(g, Vector2i(2, 1), Vector2i(2, 0))
	return g
