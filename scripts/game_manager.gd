class_name GameManager
extends Node2D

const MAZE_WIDTH := 48
const MAZE_HEIGHT := 48
const CELL_SIZE := 20.0
const NPC_COUNT := 12
const ENEMY_DENSITY := 0.06
const EXTRA_CHEST_DENSITY := 0.012
const SHOP_COLUMNS := 2
const SHOP_ROWS := 2
const EXTRA_CONNECTION_CHANCE := 0.15
const LEVEL_CURVE_EXPONENT := 1.5
const BOSS_LEVEL := 12
const BOSS_SCALE := 1.5
const NPC_SCENE: PackedScene = preload("res://scenes/NPC.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const CHEST_SCENE: PackedScene = preload("res://scenes/Chest.tscn")

var npc_colors := [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW,
	Color.ORANGE, Color.PURPLE, Color.CYAN, Color.MAGENTA,
	Color.LIME, Color.PINK, Color.TEAL, Color.GOLD,
]
var npc_names := [
	"Aria", "Bram", "Cass", "Dorn", "Eska", "Finn",
	"Gale", "Hesk", "Iris", "Jace", "Kael", "Lyra",
]

var npcs: Array = []
var winner: NpcAgent = null
var grid: Array = []
var start_cells: Array = []
var exit_cell: Vector2i
var enemy_map: Dictionary = {}
var chest_map: Dictionary = {}
## Centers of the shops, in list form (for drawing) and lookup form.
var shop_cells: Array = []
var shop_map: Dictionary = {}
## Starting safe zones, shop zones and the boss room: no enemies spawn or
## wander here, and no random chests are placed here.
var restricted_cells: Dictionary = {}

@onready var maze_view: MazeView = $World/MazeView
@onready var npc_container: Node2D = $World/NPCs
@onready var enemy_container: Node2D = $World/Enemies
@onready var chest_container: Node2D = $World/Chests
@onready var hud: Hud = $HUD/Control

func _ready() -> void:
	randomize()
	var generator := MazeGenerator.new()
	exit_cell = Vector2i(MAZE_WIDTH / 2, MAZE_HEIGHT / 2)
	grid = generator.generate(MAZE_WIDTH, MAZE_HEIGHT, EXTRA_CONNECTION_CHANCE)
	generator.carve_boss_room(grid, exit_cell, MAZE_WIDTH, MAZE_HEIGHT)
	start_cells = _start_positions(MAZE_WIDTH, MAZE_HEIGHT, NPC_COUNT)
	for s in start_cells:
		generator.open_room(grid, s, MAZE_WIDTH, MAZE_HEIGHT)
	_build_restricted_cells()
	_place_shops(generator)
	maze_view.set_maze(grid, CELL_SIZE, start_cells, exit_cell, shop_cells)
	_spawn_enemies()
	_spawn_boss()
	_spawn_chests()
	_spawn_npcs()

func _process(_delta: float) -> void:
	hud.update_positions(npcs)

## Walks the border of the maze and picks `count` evenly spaced cells along
## it, so however many NPCs there are, each begins from a distinct point
## spread around the perimeter, all racing inward to the center.
func _start_positions(width: int, height: int, count: int) -> Array:
	var border: Array = []
	for x in range(width):
		border.append(Vector2i(x, 0))
	for y in range(1, height):
		border.append(Vector2i(width - 1, y))
	for x in range(width - 2, -1, -1):
		border.append(Vector2i(x, height - 1))
	for y in range(height - 2, 0, -1):
		border.append(Vector2i(0, y))

	var result: Array = []
	var step: float = float(border.size()) / float(count)
	for i in range(count):
		var idx: int = int(round(i * step)) % border.size()
		result.append(border[idx])
	return result

func _build_restricted_cells() -> void:
	for s in start_cells:
		_restrict_zone(s)
	_restrict_zone(exit_cell)

## Marks the 3x3 block around `center` (clipped to the maze) as restricted.
func _restrict_zone(center: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := Vector2i(center.x + dx, center.y + dy)
			if c.x >= 0 and c.x < MAZE_WIDTH and c.y >= 0 and c.y < MAZE_HEIGHT:
				restricted_cells[c] = true

func _zone_is_free(center: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if restricted_cells.has(Vector2i(center.x + dx, center.y + dy)):
				return false
	return true

## Puts one shop in each region of a grid laid over the maze, so they're
## spread out rather than clumped. Each shop sits at the middle of its own
## 3x3 safe zone, opened up inside and off-limits to enemies.
func _place_shops(generator: MazeGenerator) -> void:
	var margin := 4
	var region_w: int = (MAZE_WIDTH - 2 * margin) / SHOP_COLUMNS
	var region_h: int = (MAZE_HEIGHT - 2 * margin) / SHOP_ROWS
	for row in range(SHOP_ROWS):
		for col in range(SHOP_COLUMNS):
			for attempt in range(40):
				var center := Vector2i(
					margin + col * region_w + randi() % region_w,
					margin + row * region_h + randi() % region_h)
				if not _zone_is_free(center):
					continue
				generator.open_room(grid, center, MAZE_WIDTH, MAZE_HEIGHT)
				_restrict_zone(center)
				shop_cells.append(center)
				shop_map[center] = true
				break

## Scatters enemies across the maze (never in a restricted zone), making them
## stronger the closer their cell is to the center.
func _spawn_enemies() -> void:
	var open_cells: Array = _unrestricted_cells()

	var center := Vector2i(MAZE_WIDTH / 2, MAZE_HEIGHT / 2)
	var max_distance: int = max(center.x, MAZE_WIDTH - center.x) + max(center.y, MAZE_HEIGHT - center.y)
	var count: int = int(MAZE_WIDTH * MAZE_HEIGHT * ENEMY_DENSITY)

	for i in range(min(count, open_cells.size())):
		var cell: Vector2i = open_cells[i]
		var distance: int = abs(cell.x - center.x) + abs(cell.y - center.y)
		var closeness: float = 1.0 - float(distance) / float(max(max_distance, 1))
		# Raising to a power > 1 keeps closeness (and thus level) low across
		# most of the outer maze near the start points, only ramping up
		# sharply in the last stretch approaching the boss room.
		closeness = pow(clampf(closeness, 0.0, 1.0), LEVEL_CURVE_EXPONENT)
		var level: int = 1 + int(round(closeness * 5.0))
		var enemy: EnemyAgent = ENEMY_SCENE.instantiate()
		enemy_container.add_child(enemy)
		enemy.setup(cell, CELL_SIZE, level, grid, enemy_map, restricted_cells, npcs)

## A single stationary, much stronger enemy guards the exit cell. Since a
## live enemy always blocks its cell until defeated, nobody can set foot on
## the goal until the boss falls — and the NPC that lands the winning blow
## is the same one whose move immediately after that carries it onto the
## goal, so the boss-slayer is guaranteed to be first through.
func _spawn_boss() -> void:
	var boss: EnemyAgent = ENEMY_SCENE.instantiate()
	enemy_container.add_child(boss)
	boss.setup(exit_cell, CELL_SIZE, BOSS_LEVEL, grid, enemy_map, {}, npcs, false)
	boss.visual.color = Color(0.55, 0.02, 0.05, 1.0)
	boss.scale = Vector2(BOSS_SCALE, BOSS_SCALE)

func _unrestricted_cells() -> Array:
	var cells: Array = []
	for y in range(MAZE_HEIGHT):
		for x in range(MAZE_WIDTH):
			var c := Vector2i(x, y)
			if not restricted_cells.has(c):
				cells.append(c)
	cells.shuffle()
	return cells

## Drops one equipment chest into each starting safe zone (on a random cell
## other than the exact spawn point, so it's something to walk over and pick
## up rather than an instant freebie), then scatters more at random through
## the rest of the dungeon for characters to spot and detour to.
func _spawn_chests() -> void:
	for s in start_cells:
		_place_chest(_pick_chest_cell(s))

	var extra: int = int(MAZE_WIDTH * MAZE_HEIGHT * EXTRA_CHEST_DENSITY)
	for c in _unrestricted_cells():
		if extra <= 0:
			break
		if enemy_map.has(c) or chest_map.has(c):
			continue
		_place_chest(c)
		extra -= 1

func _place_chest(cell: Vector2i) -> void:
	var chest: ChestAgent = CHEST_SCENE.instantiate()
	chest_container.add_child(chest)
	chest.setup(cell, CELL_SIZE)
	chest_map[cell] = chest

func _pick_chest_cell(start: Vector2i) -> Vector2i:
	var candidates: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var c := Vector2i(start.x + dx, start.y + dy)
			if c.x >= 0 and c.x < MAZE_WIDTH and c.y >= 0 and c.y < MAZE_HEIGHT:
				candidates.append(c)
	if candidates.is_empty():
		return start
	return candidates[randi() % candidates.size()]

func _spawn_npcs() -> void:
	for i in range(NPC_COUNT):
		var npc: NpcAgent = NPC_SCENE.instantiate()
		npc_container.add_child(npc)
		var color: Color = npc_colors[i % npc_colors.size()]
		var display_name: String = npc_names[i % npc_names.size()]
		var start_cell: Vector2i = start_cells[i]
		npc.setup(start_cell, exit_cell, grid, CELL_SIZE, color, display_name, enemy_map, chest_map, shop_map)
		npc.reached_exit.connect(_on_npc_reached_exit)
		npc.leveled_up.connect(_on_npc_leveled_up)
		npc.died.connect(_on_npc_died)
		npcs.append(npc)
		hud.register_npc(npc)

func _on_npc_reached_exit(npc: NpcAgent) -> void:
	if winner != null:
		return
	winner = npc
	hud.announce_winner(npc)

func _on_npc_died(npc: NpcAgent) -> void:
	npcs.erase(npc)
	hud.mark_dead(npc)
	if npcs.is_empty() and winner == null:
		hud.announce_no_winner()

func _on_npc_leveled_up(npc: NpcAgent) -> void:
	hud.refresh_npc(npc)
