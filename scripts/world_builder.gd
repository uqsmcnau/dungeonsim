class_name WorldBuilder
extends RefCounted

## Generates the dungeon and stocks it: the maze itself, the safe zones
## (start zones, shops, mini boss rooms, the boss room), and the monsters,
## bosses and chests placed through it -- plus the chests that turn up later
## (a mini boss's silver chest, a fallen character's belongings). The world's
## state (grid, the shared maps of who's where, ...) stays on GameManager,
## where everything else reads it; this only fills it in.

const ENEMY_DENSITY := 0.06
const EXTRA_CHEST_DENSITY := 0.012
## Shops go one to a region of a SHOP_GRID x SHOP_GRID grid over the maze,
## bar the middle region, which is the boss's (see _place_shops).
const SHOP_GRID := 3
const EXTRA_CONNECTION_CHANCE := 0.15
const LEVEL_CURVE_EXPONENT := 1.5
const BOSS_LEVEL := 12
const BOSS_SCALE := 1.5
const MINI_BOSS_COUNT := 6
const MINI_BOSS_LEVEL := 8
const MINI_BOSS_SCALE := 1.3
## Some encounters spawn as a pack of 2-3 individually weaker enemies
## instead of one at full strength, so a party has multiple bodies to work
## through rather than always a single, tougher target.
const PACK_ENCOUNTER_CHANCE := 0.3
const PACK_LEVEL_SCALE := 0.65
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const CHEST_SCENE: PackedScene = preload("res://scenes/Chest.tscn")

var game: GameManager

func _init(owner: GameManager) -> void:
	game = owner

## The maze and its zones, inside a circle (see MazeShape): the boss
## room at the center, a start zone for each character around the edge,
## shops and mini boss rooms in between. Hands the result to the MazeView to
## draw.
func build_maze() -> void:
	var generator := MazeGenerator.new()
	game.maze_shape = MazeShape.circle(GameManager.MAZE_WIDTH, GameManager.MAZE_HEIGHT)
	game.exit_cell = Vector2i(GameManager.MAZE_WIDTH / 2, GameManager.MAZE_HEIGHT / 2)
	game.grid = generator.generate(GameManager.MAZE_WIDTH, GameManager.MAZE_HEIGHT, EXTRA_CONNECTION_CHANCE, game.maze_shape)
	generator.carve_boss_room(game.grid, game.exit_cell, GameManager.MAZE_WIDTH, GameManager.MAZE_HEIGHT)
	game.start_cells = start_positions(GameManager.NPC_COUNT)
	for s in game.start_cells:
		generator.open_room(game.grid, s, GameManager.MAZE_WIDTH, GameManager.MAZE_HEIGHT)
	_build_restricted_cells()
	_place_shops(generator)
	_place_mini_bosses(generator)
	# Sealing the boss rooms' sides can strand a dead end; let it back in,
	# keeping the rooms to their four entrances.
	var rooms: Dictionary = zone_cells(game.exit_cell)
	for center in game.mini_boss_cells:
		rooms.merge(zone_cells(center))
	generator.reconnect(game.grid, game.exit_cell, rooms)
	game.maze_view.set_maze(game.grid, GameManager.CELL_SIZE, game.start_cells, game.exit_cell, game.shop_cells,
		game.mini_boss_cells, game.maze_shape)
	game.maze_view.reveal_permanently(zone_cells(game.exit_cell))

## Monsters through the maze, the boss on the exit, and chests.
func stock() -> void:
	_spawn_enemies()
	_spawn_boss()
	_spawn_chests()

## `count` start zones spaced evenly around the edge of the maze, so however
## many characters there are, each begins from a distinct point on the
## perimeter, all racing inward to the center. Each sits as near the edge as
## its whole 3x3 zone fits inside the maze.
func start_positions(count: int) -> Array:
	var result: Array = []
	for i in range(count):
		var angle := TAU * i / count - PI / 2.0  # starting from the top
		var inset := 1.5
		var cell := game.maze_shape.cell_toward(angle, inset)
		while not _zone_inside(cell) and inset < game.maze_shape.radius:
			inset += 0.5
			cell = game.maze_shape.cell_toward(angle, inset)
		result.append(cell)
	return result

## Whether the whole 3x3 block around `center` is inside the maze.
func _zone_inside(center: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if MazeGenerator.is_outside(game.grid, center + Vector2i(dx, dy)):
				return false
	return true

## How many cells the maze has (the grid, less the rock outside its outline).
func maze_cell_count() -> int:
	var count := 0
	for y in range(GameManager.MAZE_HEIGHT):
		for x in range(GameManager.MAZE_WIDTH):
			if not MazeGenerator.is_outside(game.grid, Vector2i(x, y)):
				count += 1
	return count

func _build_restricted_cells() -> void:
	for s in game.start_cells:
		_restrict_zone(s)
	_restrict_zone(game.exit_cell)

## The 3x3 block around `center`, clipped to the maze.
func zone_cells(center: Vector2i) -> Dictionary:
	var cells: Dictionary = {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := Vector2i(center.x + dx, center.y + dy)
			if not MazeGenerator.is_outside(game.grid, c):
				cells[c] = true
	return cells

## Marks the 3x3 block around `center` (clipped to the maze) as restricted.
func _restrict_zone(center: Vector2i) -> void:
	game.restricted_cells.merge(zone_cells(center))

## Whether a new zone could go around `center`: wholly inside the maze, and
## overlapping no other.
func _zone_is_free(center: Vector2i) -> bool:
	if not _zone_inside(center):
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if game.restricted_cells.has(Vector2i(center.x + dx, center.y + dy)):
				return false
	return true

## Puts one shop in each region of a grid laid over the maze -- all but the
## middle one, where the boss is -- so they're spread out in a ring round it
## rather than clumped. Each shop sits at the middle of its own
## 3x3 safe zone, opened up inside and off-limits to enemies.
func _place_shops(generator: MazeGenerator) -> void:
	var margin := 4
	var region_w: int = (GameManager.MAZE_WIDTH - 2 * margin) / SHOP_GRID
	var region_h: int = (GameManager.MAZE_HEIGHT - 2 * margin) / SHOP_GRID
	for row in range(SHOP_GRID):
		for col in range(SHOP_GRID):
			if row == SHOP_GRID / 2 and col == SHOP_GRID / 2:
				continue
			for attempt in range(40):
				var center := Vector2i(
					margin + col * region_w + randi() % region_w,
					margin + row * region_h + randi() % region_h)
				if not _zone_is_free(center):
					continue
				generator.open_room(game.grid, center, GameManager.MAZE_WIDTH, GameManager.MAZE_HEIGHT)
				_restrict_zone(center)
				game.shop_cells.append(center)
				game.shop_map[center] = true
				game.maze_view.register_sticky_zone(zone_cells(center))
				break

## Guards a handful of 3x3 mini boss rooms (structured the same way as the
## main boss room) with a single tough, stationary enemy each. Defeating one
## drops a silver chest — holding an upgraded, silver-only item — right on
## the cell it fell on.
func _place_mini_bosses(generator: MazeGenerator) -> void:
	for i in range(MINI_BOSS_COUNT):
		for attempt in range(60):
			var center := Vector2i(randi_range(4, GameManager.MAZE_WIDTH - 5), randi_range(4, GameManager.MAZE_HEIGHT - 5))
			if not _zone_is_free(center):
				continue
			generator.carve_boss_room(game.grid, center, GameManager.MAZE_WIDTH, GameManager.MAZE_HEIGHT)
			_restrict_zone(center)
			game.mini_boss_cells.append(center)
			game.maze_view.register_sticky_zone(zone_cells(center))

			var mini_boss: EnemyAgent = ENEMY_SCENE.instantiate()
			game.enemy_container.add_child(mini_boss)
			mini_boss.setup(center, GameManager.CELL_SIZE, MINI_BOSS_LEVEL, game.grid, game.enemy_map, {}, game.npcs, false)
			mini_boss.is_mini_boss = true
			mini_boss.visual.color = Color(0.55, 0.15, 0.75, 1.0)
			mini_boss.scale = Vector2(MINI_BOSS_SCALE, MINI_BOSS_SCALE)
			mini_boss.mini_boss_defeated.connect(_on_mini_boss_defeated)
			break

func _on_mini_boss_defeated(cell: Vector2i) -> void:
	place_chest(cell, ItemCatalog.RARITY_SILVER)

## Scatters enemies across the maze (never in a restricted zone), making them
## stronger the closer their cell is to the center.
func _spawn_enemies() -> void:
	var open_cells: Array = unrestricted_cells()
	var count: int = int(maze_cell_count() * ENEMY_DENSITY)

	for i in range(min(count, open_cells.size())):
		var cell: Vector2i = open_cells[i]
		var level := enemy_level_for(cell)
		if randf() < PACK_ENCOUNTER_CHANCE:
			spawn_enemy_pack(cell, level)
		else:
			spawn_enemy(cell, level)

## How strong a monster spawning on `cell` is: stronger the closer it is to
## the center (in steps, measured against the furthest the maze's edge gets).
func enemy_level_for(cell: Vector2i) -> int:
	var center := game.exit_cell
	var max_distance := game.maze_shape.radius * sqrt(2.0)
	var distance: int = abs(cell.x - center.x) + abs(cell.y - center.y)
	var closeness: float = 1.0 - float(distance) / maxf(max_distance, 1.0)
	# Raising to a power > 1 keeps closeness (and thus level) low across
	# most of the outer maze near the start points, only ramping up
	# sharply in the last stretch approaching the boss room.
	closeness = pow(clampf(closeness, 0.0, 1.0), LEVEL_CURVE_EXPONENT)
	return 1 + int(round(closeness * 5.0))

func spawn_enemy(cell: Vector2i, level: int) -> void:
	var enemy: EnemyAgent = ENEMY_SCENE.instantiate()
	game.enemy_container.add_child(enemy)
	enemy.setup(cell, GameManager.CELL_SIZE, level, game.grid, game.enemy_map, game.restricted_cells, game.npcs)

## A handful of individually weaker enemies sharing one encounter in place
## of a single enemy at full strength — fights the same way a lone enemy
## does, just with more bodies for a party to work through. At most
## `max_size` strong (respawning uses it to stay within an area's capacity).
func spawn_enemy_pack(cell: Vector2i, base_level: int, max_size: int = 3) -> void:
	var pack_size: int = mini(2 + (1 if randf() < 0.5 else 0), max_size)
	var pack_level: int = max(1, int(round(base_level * PACK_LEVEL_SCALE)))
	var members: Array = []
	for i in range(pack_size):
		var enemy: EnemyAgent = ENEMY_SCENE.instantiate()
		game.enemy_container.add_child(enemy)
		enemy.setup(cell, GameManager.CELL_SIZE, pack_level, game.grid, game.enemy_map, game.restricted_cells, game.npcs)
		members.append(enemy)
	EnemyAgent.form_pack(members)

## A single stationary, much stronger enemy guards the exit cell. Since a
## live enemy always blocks its cell until defeated, nobody can set foot on
## the goal until the boss falls — and the NPC that lands the winning blow
## is the same one whose move immediately after that carries it onto the
## goal, so the boss-slayer is guaranteed to be first through.
func _spawn_boss() -> void:
	var boss: EnemyAgent = ENEMY_SCENE.instantiate()
	game.enemy_container.add_child(boss)
	boss.setup(game.exit_cell, GameManager.CELL_SIZE, BOSS_LEVEL, game.grid, game.enemy_map, {}, game.npcs, false)
	boss.is_boss = true
	boss.visual.color = Color(0.55, 0.02, 0.05, 1.0)
	boss.scale = Vector2(BOSS_SCALE, BOSS_SCALE)

## Every cell of the maze outside the safe zones, shuffled.
func unrestricted_cells() -> Array:
	var cells: Array = []
	for y in range(GameManager.MAZE_HEIGHT):
		for x in range(GameManager.MAZE_WIDTH):
			var c := Vector2i(x, y)
			if not game.restricted_cells.has(c) and not MazeGenerator.is_outside(game.grid, c):
				cells.append(c)
	cells.shuffle()
	return cells

## Drops one equipment chest into each starting safe zone (on a random cell
## other than the exact spawn point, so it's something to walk over and pick
## up rather than an instant freebie), then scatters more at random through
## the rest of the dungeon for characters to spot and detour to.
func _spawn_chests() -> void:
	for s in game.start_cells:
		place_chest(_pick_chest_cell(s))

	var extra: int = int(maze_cell_count() * EXTRA_CHEST_DENSITY)
	for c in unrestricted_cells():
		if extra <= 0:
			break
		if game.enemy_map.has(c) or game.chest_map.has(c):
			continue
		place_chest(c)
		extra -= 1

func place_chest(cell: Vector2i, rarity: String = ItemCatalog.RARITY_BRONZE) -> void:
	var chest: ChestAgent = CHEST_SCENE.instantiate()
	game.chest_container.add_child(chest)
	chest.setup(cell, GameManager.CELL_SIZE, rarity)
	game.chest_map[cell] = chest

## Drops everything a fallen character was carrying where they died. If
## another chest already sits on that exact cell (two characters happening to
## die in the same spot), the loot is merged into it instead of replacing it.
func place_death_chest(cell: Vector2i, loot: Dictionary, gold: int) -> void:
	if loot.is_empty() and gold <= 0:
		return
	if game.chest_map.has(cell):
		var existing: ChestAgent = game.chest_map[cell]
		existing.merge_in(loot, gold)
		return
	var chest: ChestAgent = CHEST_SCENE.instantiate()
	game.chest_container.add_child(chest)
	chest.setup_from_death(cell, GameManager.CELL_SIZE, loot, gold)
	game.chest_map[cell] = chest

func _pick_chest_cell(start: Vector2i) -> Vector2i:
	var candidates: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var c := Vector2i(start.x + dx, start.y + dy)
			if not MazeGenerator.is_outside(game.grid, c):
				candidates.append(c)
	if candidates.is_empty():
		return start
	return candidates[randi() % candidates.size()]
