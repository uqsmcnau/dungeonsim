class_name WorldBuilder
extends RefCounted

## Generates the dungeon and stocks it: the maze itself, the safe zones
## (start zones, shops, mid boss rooms, the boss room), and the monsters,
## bosses and chests placed through it -- plus the chests that turn up later
## (a mid boss party's silver or gold chest, a fallen character's
## belongings). The world's
## state (grid, the shared maps of who's where, ...) stays on GameManager,
## where everything else reads it; this only fills it in.

const ENEMY_DENSITY := 0.06
const EXTRA_CHEST_DENSITY := 0.012
## Shops go one to a region of a SHOP_GRID x SHOP_GRID grid over the maze,
## bar the middle region, which is the boss's (see _place_shops).
const SHOP_GRID := 3
## The silver shops, and how far from the middle they go (in cells, between
## x and y) -- see _place_silver_shops.
const SILVER_SHOP_COUNT := 2
const SILVER_SHOP_REACH := Vector2(9.0, 13.0)
const EXTRA_CONNECTION_CHANCE := 0.15
const LEVEL_CURVE_EXPONENT := 1.5
## How far from the middle the nearest cells outside the boss room are --
## where the maze's strongest monsters are.
const BOSS_ROOM_REACH := 2
## The boss (the Dragon -- see MonsterCatalog) and the guards in its party
## of five.
const BOSS_LEVEL := 12
const BOSS_GUARD_LEVEL := 10
const BOSS_GUARDS := 4
const BOSS_SCALE := 1.5
## The mid bosses (see _place_mid_bosses, EnemyAgent.is_mid_boss), each
## with this many guards: the stronger Ogre Warlords (WARLORD_*) between
## WARLORD_REACH cells from the middle (x to y), the weaker Orc Chieftains
## (CHIEFTAIN_*) between CHIEFTAIN_REACH, out towards the edge.
const MID_BOSS_GUARDS := 2
const WARLORD_COUNT := 6
const WARLORD_LEVEL := 11
const WARLORD_GUARD_LEVEL := 8
const WARLORD_SCALE := 1.3
const WARLORD_REACH := Vector2(11.0, 17.0)
const CHIEFTAIN_COUNT := 8
const CHIEFTAIN_LEVEL := 6
const CHIEFTAIN_GUARD_LEVEL := 3
const CHIEFTAIN_SCALE := 1.15
const CHIEFTAIN_REACH := Vector2(20.0, 27.0)
## How far a boss's guards stand from it on the map (pixels each way) --
## further than a pack's, to stand clear of the bigger boss.
const BOSS_GUARD_SPREAD := 12.0
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
## shops and mid boss rooms in between. Hands the result to the MazeView to
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
	_place_silver_shops(generator)
	_place_mid_bosses(generator)
	# Sealing the boss rooms' sides can strand a dead end; let it back in,
	# keeping the rooms to their four entrances.
	var rooms: Dictionary = zone_cells(game.exit_cell)
	for center in game.mid_boss_cells:
		rooms.merge(zone_cells(center))
	generator.reconnect(game.grid, game.exit_cell, rooms)
	game.maze_view.set_maze(game.grid, GameManager.CELL_SIZE, game.start_cells, game.exit_cell, game.shop_map,
		game.mid_boss_cells, game.maze_shape)
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

## Puts one bronze shop in each region of a grid laid over the maze -- all
## but the middle one, where the boss is -- so they're spread out in a ring
## round it rather than clumped (see _open_shop).
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
				if _zone_is_free(center):
					_open_shop(generator, center, ItemCatalog.RARITY_BRONZE)
					break

## SILVER_SHOP_COUNT silver shops (selling the silver gear -- see
## NpcStats.missing_items), spaced evenly round the boss room, between
## SILVER_SHOP_REACH cells from the middle: deeper in, where the monsters are
## stronger, than the bronze shops.
func _place_silver_shops(generator: MazeGenerator) -> void:
	_place_in_ring(SILVER_SHOP_COUNT, SILVER_SHOP_REACH, func(center: Vector2i):
		_open_shop(generator, center, ItemCatalog.RARITY_SILVER))

## A shop of `rarity` at the middle of its own 3x3 safe zone, opened up
## inside and off-limits to enemies.
func _open_shop(generator: MazeGenerator, center: Vector2i, rarity: String) -> void:
	generator.open_room(game.grid, center, GameManager.MAZE_WIDTH, GameManager.MAZE_HEIGHT)
	_restrict_zone(center)
	game.shop_cells.append(center)
	game.shop_map[center] = rarity
	game.maze_view.register_sticky_zone(zone_cells(center))

## Guards 3x3 mid boss rooms (structured the same way as the main boss
## room), each with a stationary party of three -- a mid boss and two
## guards (see _spawn_boss_party) -- in two tiers: Ogre Warlords in a ring
## round the middle, and weaker Orc Chieftains out towards the edge.
## Beating a whole party leaves a chest where it stood: gold from an Ogre
## Warlord's (a gold-only item, the best there is), silver from an Orc
## Chieftain's.
func _place_mid_bosses(generator: MazeGenerator) -> void:
	_place_in_ring(WARLORD_COUNT, WARLORD_REACH, func(center: Vector2i):
		var boss := _open_mid_boss_room(generator, center, WARLORD_LEVEL, WARLORD_GUARD_LEVEL, ItemCatalog.RARITY_GOLD)
		boss.scale = Vector2(WARLORD_SCALE, WARLORD_SCALE))
	_place_in_ring(CHIEFTAIN_COUNT, CHIEFTAIN_REACH, func(center: Vector2i):
		var boss := _open_mid_boss_room(generator, center, CHIEFTAIN_LEVEL, CHIEFTAIN_GUARD_LEVEL, ItemCatalog.RARITY_SILVER)
		boss.set_kind(MonsterCatalog.orc_chieftain)
		for guard in boss.pack.slice(1):
			guard.guarding = boss.kind.called()
		boss.scale = Vector2(CHIEFTAIN_SCALE, CHIEFTAIN_SCALE))

## A mid boss room on `center`, held by a level `level` mid boss and its two
## level `guard_level` guards, who leave a chest of `chest_rarity` once
## they're all beaten. Returns the mid boss.
func _open_mid_boss_room(generator: MazeGenerator, center: Vector2i, level: int, guard_level: int,
		chest_rarity: String) -> EnemyAgent:
	generator.carve_boss_room(game.grid, center, GameManager.MAZE_WIDTH, GameManager.MAZE_HEIGHT)
	_restrict_zone(center)
	game.mid_boss_cells.append(center)
	game.maze_view.register_sticky_zone(zone_cells(center))
	var boss := _spawn_boss_party(center, level, guard_level, MID_BOSS_GUARDS)
	boss.is_mid_boss = true
	for member in boss.pack:
		member.pack_defeated.connect(place_chest.bind(chest_rarity))
	return boss

## `count` 3x3 zones (made by `place`, given each one's middle) spaced
## evenly round the middle of the maze, each between `reach.x` and `reach.y`
## cells out -- give or take, where there's room.
func _place_in_ring(count: int, reach: Vector2, place: Callable) -> void:
	var turn := randf() * TAU
	for i in range(count):
		for attempt in range(60):
			var angle := turn + TAU * i / count + randf_range(-0.4, 0.4) * 6.0 / count
			var distance := randf_range(reach.x, reach.y)
			var center := game.exit_cell + Vector2i((Vector2.from_angle(angle) * distance).round())
			if _zone_is_free(center):
				place.call(center)
				break

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

## How strong a monster spawning on `cell` is: level 1 out at the maze's
## edge, up to MonsterCatalog.MAZE_MAX_LEVEL right outside the boss room --
## by how far it is from the room's edge, against how far the maze's edge
## is (the maze being round, as the crow flies).
func enemy_level_for(cell: Vector2i) -> int:
	var max_distance := game.maze_shape.radius - BOSS_ROOM_REACH
	var distance := Vector2(cell - game.exit_cell).length() - BOSS_ROOM_REACH
	var closeness: float = 1.0 - distance / maxf(max_distance, 1.0)
	# Raising to a power > 1 keeps closeness (and thus level) low across
	# most of the outer maze near the start points, only ramping up
	# sharply in the last stretch approaching the boss room.
	closeness = pow(clampf(closeness, 0.0, 1.0), LEVEL_CURVE_EXPONENT)
	return 1 + int(round(closeness * (MonsterCatalog.MAZE_MAX_LEVEL - 1)))

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

## The boss's stationary party of five -- the boss and four guards (see
## _spawn_boss_party) -- holds the exit cell. Since a live enemy always
## blocks its cell until defeated, nobody can set foot on the goal until
## the whole party falls — and the NPC that lands the winning blow is the
## same one whose move immediately after that carries it onto the goal, so
## the boss-slayer is guaranteed to be first through.
func _spawn_boss() -> void:
	var boss := _spawn_boss_party(game.exit_cell, BOSS_LEVEL, BOSS_GUARD_LEVEL, BOSS_GUARDS)
	boss.is_boss = true
	boss.scale = Vector2(BOSS_SCALE, BOSS_SCALE)
	for guard in boss.pack:
		if guard != boss:
			guard.guarding = boss.kind.called(true)

## A boss of level `level` on `cell` leading `guards` guards of level
## `guard_level`: one pack, none of whom ever leave the room. Returns the
## boss.
func _spawn_boss_party(cell: Vector2i, level: int, guard_level: int, guards: int) -> EnemyAgent:
	var members: Array = []
	for i in range(guards + 1):
		var member: EnemyAgent = ENEMY_SCENE.instantiate()
		game.enemy_container.add_child(member)
		member.setup(cell, GameManager.CELL_SIZE, level if i == 0 else guard_level, game.grid, game.enemy_map, {}, game.npcs, false)
		members.append(member)
	EnemyAgent.form_pack(members, BOSS_GUARD_SPREAD)
	var boss: EnemyAgent = members[0]
	for guard in members.slice(1):
		guard.guarding = boss.kind.called()
	return boss

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
