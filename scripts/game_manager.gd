class_name GameManager
extends Node2D

const MAZE_WIDTH := 48
const MAZE_HEIGHT := 48
const CELL_SIZE := 20.0
const NPC_COUNT := 20
const ENEMY_DENSITY := 0.06
const EXTRA_CHEST_DENSITY := 0.012
const SHOP_COLUMNS := 2
const SHOP_ROWS := 2
const EXTRA_CONNECTION_CHANCE := 0.15
const LEVEL_CURVE_EXPONENT := 1.5
const BOSS_LEVEL := 12
const BOSS_SCALE := 1.5
const MINI_BOSS_COUNT := 3
const MINI_BOSS_LEVEL := 8
const MINI_BOSS_SCALE := 1.3
## Some encounters spawn as a pack of 2-3 individually weaker enemies
## instead of one at full strength, so a party has multiple bodies to work
## through rather than always a single, tougher target.
const PACK_ENCOUNTER_CHANCE := 0.3
const PACK_LEVEL_SCALE := 0.65
## How far (in pixels) from a character's icon center a click still selects
## it -- about half a cell, matching the 16px icon.
const PICK_RADIUS := 10.0
## Seconds of game time (it doesn't tick while paused) between uses of
## Guidance, the spectator's right-click "go there" for the selected party.
const GUIDANCE_COOLDOWN := 15.0
## How far the selection ring sits beyond the outermost member's icon
## centre -- a touch more than half the 16px icon's diagonal.
const SELECTION_ICON_MARGIN := 13.0
## The selection ring's radius around a gravestone -- just clear of its icon.
const GRAVE_RING_RADIUS := 12.0
const NPC_SCENE: PackedScene = preload("res://scenes/NPC.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const CHEST_SCENE: PackedScene = preload("res://scenes/Chest.tscn")
const GRAVE_SCENE: PackedScene = preload("res://scenes/Gravestone.tscn")

## Party Vision: while a character is selected, the fog of war shows only
## what their party knows -- the cells its members can see right now, and
## everything any of them has ever seen (see NpcAgent.seen_cells) -- rather
## than what everyone has. Starts the toolbar's "Party Vision" toggle in
## this state. Has no effect with the fog of war turned off.
@export var party_vision: bool = true

## One distinct entry per NPC_COUNT -- kept at exactly 20 so no two of the
## 20 starting characters share both a name and a color (they'd otherwise
## cycle and repeat via the modulo indexing below once NPC_COUNT exceeded
## the list length).
var npc_colors := [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW,
	Color.ORANGE, Color.PURPLE, Color.CYAN, Color.MAGENTA,
	Color.LIME, Color.PINK, Color.TEAL, Color.GOLD,
	Color.BROWN, Color.CORAL, Color.VIOLET, Color.SALMON,
	Color.KHAKI, Color.CRIMSON, Color.TURQUOISE, Color.SIENNA,
]
var npc_names := [
	"Aria", "Bram", "Cass", "Dorn", "Eska", "Finn",
	"Gale", "Hesk", "Iris", "Jace", "Kael", "Lyra",
	"Mira", "Nox", "Orla", "Pell", "Quen", "Rook", "Sable", "Tam",
]

var npcs: Array = []
var winner: NpcAgent = null
var grid: Array = []
var start_cells: Array = []
var exit_cell: Vector2i
var enemy_map: Dictionary = {}
var chest_map: Dictionary = {}
## Every living player, by current cell — lets NPCs see and fight each other.
var player_map: Dictionary = {}
## Centers of the shops, in list form (for drawing) and lookup form.
var shop_cells: Array = []
var shop_map: Dictionary = {}
## Centers of the mini boss rooms, for drawing.
var mini_boss_cells: Array = []
## Starting safe zones, shop zones, mini boss rooms and the boss room: no
## enemies spawn or wander here, and no random chests are placed here.
var restricted_cells: Dictionary = {}
## Seconds until Guidance can be used again (0 = ready). Ticked down in
## _process, so it freezes while the game is paused.
var guidance_cooldown_left: float = 0.0
## A gravestone for every character who's died, by character, standing
## where they fell. Clicking one brings up their final HUD panel, with how
## they died.
var graves: Dictionary = {}

@onready var maze_view: MazeView = $World/MazeView
@onready var npc_container: Node2D = $World/NPCs
@onready var enemy_container: Node2D = $World/Enemies
@onready var chest_container: Node2D = $World/Chests
@onready var grave_container: Node2D = $World/Graves
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
	_place_mini_bosses(generator)
	maze_view.set_maze(grid, CELL_SIZE, start_cells, exit_cell, shop_cells, mini_boss_cells)
	maze_view.reveal_permanently(_zone_cells(exit_cell))
	hud.fog_toggled.connect(_on_fog_toggled)
	hud.party_vision_toggle.set_pressed_no_signal(party_vision)
	hud.party_vision_toggled.connect(_on_party_vision_toggled)
	$ClickPicker.clicked.connect(_on_world_clicked)
	$ClickPicker.right_clicked.connect(_on_world_right_clicked)
	hud.selection_changed.connect(_sync_selection_highlight)
	hud.selection_changed.connect(_sync_fog)
	_spawn_enemies()
	_spawn_boss()
	_spawn_chests()
	_spawn_npcs()

func _process(delta: float) -> void:
	hud.update_positions(npcs)
	_sync_fog()
	_sync_guidance_marker()
	_sync_selection_highlight()
	guidance_cooldown_left = maxf(0.0, guidance_cooldown_left - delta)
	hud.update_guidance(guidance_cooldown_left, GUIDANCE_COOLDOWN)

## The fog checkbox stays usable while paused, but _process doesn't run then,
## so re-sync immediately or enemies/chests wouldn't appear/hide until resume.
func _on_fog_toggled(enabled: bool) -> void:
	maze_view.set_fog_enabled(enabled)
	_sync_fog()

## Likewise usable while paused, so re-sync straight away.
func _on_party_vision_toggled(enabled: bool) -> void:
	party_vision = enabled
	_sync_fog()

## Clicking a character's icon selects them -- opening their inspector panel
## and highlighting their party on the map -- as does clicking a fallen
## character's gravestone (a living character standing over one wins);
## clicking anywhere else on the map deselects them.
func _on_world_clicked(world_pos: Vector2) -> void:
	var npc: NpcAgent = npc_at(world_pos)
	if npc == null:
		npc = grave_at(world_pos)
	if npc != null:
		hud.inspect(npc)
	else:
		hud.close_inspector()

## Guidance: right-clicking the maze while a character is selected
## (inspected) sends their whole party there -- whoever's leading it, even
## if the selected character is a follower. Usable once every
## GUIDANCE_COOLDOWN seconds; the cooldown only starts when Guidance is
## actually given, so a click that goes nowhere doesn't waste it. Works
## while paused; the party sets off once the game resumes.
func _on_world_right_clicked(world_pos: Vector2) -> void:
	var leader := _inspected_party_leader()
	if leader == null:
		return
	var cell := world_to_cell(world_pos)
	if cell.x < 0 or cell.x >= MAZE_WIDTH or cell.y < 0 or cell.y >= MAZE_HEIGHT:
		return
	if guidance_cooldown_left > 0.0:
		hud.guidance_denied()
		return
	if leader.guide_to(cell):
		guidance_cooldown_left = GUIDANCE_COOLDOWN
		hud.update_guidance(guidance_cooldown_left, GUIDANCE_COOLDOWN)
	_sync_guidance_marker()

## The leader of the selected character's party, or null if nobody's
## selected or they're out of the running.
func _inspected_party_leader() -> NpcAgent:
	var npc: NpcAgent = hud.inspected
	if npc == null or npc.dead or npc.finished:
		return null
	return npc._current_party_leader(npc.party)

func world_to_cell(world_pos: Vector2) -> Vector2i:
	var local: Vector2 = npc_container.get_global_transform().affine_inverse() * world_pos
	return Vector2i(floori(local.x / CELL_SIZE), floori(local.y / CELL_SIZE))

## Rings the selected character's whole party on the map, following them as
## they move -- centred on the leader, wide enough to take in every member's
## icon (party members stand slightly offset from the leader, see
## PartyOps.PARTY_OFFSETS). A dead character's gravestone is ringed
## instead; nothing is when nobody's selected.
func _sync_selection_highlight() -> void:
	var npc: NpcAgent = hud.inspected
	if npc == null:
		maze_view.set_selection_highlight(Vector2.ZERO, 0.0)
		return
	if npc.dead:
		var grave: Node2D = graves.get(npc)
		if grave == null:
			maze_view.set_selection_highlight(Vector2.ZERO, 0.0)
		else:
			maze_view.set_selection_highlight(grave.position, GRAVE_RING_RADIUS)
		return
	var leader: NpcAgent = npc._current_party_leader(npc.party)
	if leader == null:
		leader = npc
	var radius := 0.0
	for member in leader.living_party():
		radius = maxf(radius, member.position.distance_to(leader.position))
	maze_view.set_selection_highlight(leader.position, radius + SELECTION_ICON_MARGIN)

## The party whose view Party Vision shows: the selected character's,
## followers included. Nobody (so everyone's view shows) when it's switched
## off, nobody's selected, or the selected character has died.
func _party_vision_focus() -> Array:
	var npc: NpcAgent = hud.inspected
	if not party_vision or npc == null or npc.dead:
		return []
	return npc.living_party()

## Marks where the selected party has been sent by Guidance, if anywhere.
func _sync_guidance_marker() -> void:
	var leader := _inspected_party_leader()
	maze_view.set_guidance_marker(leader.guidance_target if leader != null else MazeQuery.NONE)

## The living character whose icon is nearest `world_pos`, within
## PICK_RADIUS, or null. Party members share a cell (offset by
## PartyOps.PARTY_OFFSETS), so their icons overlap -- nearest wins.
func npc_at(world_pos: Vector2) -> NpcAgent:
	var best: NpcAgent = null
	var best_dist := PICK_RADIUS
	for npc in npcs:
		if npc.dead:
			continue
		var dist: float = npc.global_position.distance_to(world_pos)
		if dist <= best_dist:
			best = npc
			best_dist = dist
	return best

## The fallen character whose gravestone is nearest `world_pos`, within
## PICK_RADIUS, or null. Only gravestones showing on the map count.
func grave_at(world_pos: Vector2) -> NpcAgent:
	var best: NpcAgent = null
	var best_dist := PICK_RADIUS
	for npc in graves:
		var grave: Node2D = graves[npc]
		if not grave.visible:
			continue
		var dist: float = grave.global_position.distance_to(world_pos)
		if dist <= best_dist:
			best = npc
			best_dist = dist
	return best

func _sync_fog() -> void:
	for npc in npcs:
		npc.look_around()
	maze_view.update_fog(npcs, _party_vision_focus())
	for cell in enemy_map:
		var enemy: EnemyAgent = enemy_map[cell]
		var cell_visible: bool = maze_view.is_currently_visible(cell)
		# enemy_map only ever holds the pack's leader; followers (sharing the
		# same cell, offset slightly) aren't in it at all, so without this
		# they'd never get hidden and would always show through the fog.
		for pack_member in enemy.living_pack():
			pack_member.visible = cell_visible
	for cell in chest_map:
		var chest: ChestAgent = chest_map[cell]
		chest.visible = maze_view.is_currently_visible(cell)
	# Landmarks, like shops: shown wherever the map's been discovered (by
	# the selected party, under Party Vision), not only while in sight.
	for npc in graves:
		graves[npc].visible = maze_view.is_discovered(npc.cell_pos)

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

## The 3x3 block around `center`, clipped to the maze bounds.
func _zone_cells(center: Vector2i) -> Dictionary:
	var cells: Dictionary = {}
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := Vector2i(center.x + dx, center.y + dy)
			if c.x >= 0 and c.x < MAZE_WIDTH and c.y >= 0 and c.y < MAZE_HEIGHT:
				cells[c] = true
	return cells

## Marks the 3x3 block around `center` (clipped to the maze) as restricted.
func _restrict_zone(center: Vector2i) -> void:
	restricted_cells.merge(_zone_cells(center))

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
				maze_view.register_sticky_zone(_zone_cells(center))
				break

## Guards a handful of 3x3 mini boss rooms (structured the same way as the
## main boss room) with a single tough, stationary enemy each. Defeating one
## drops a silver chest — holding an upgraded, silver-only item — right on
## the cell it fell on.
func _place_mini_bosses(generator: MazeGenerator) -> void:
	for i in range(MINI_BOSS_COUNT):
		for attempt in range(60):
			var center := Vector2i(randi_range(4, MAZE_WIDTH - 5), randi_range(4, MAZE_HEIGHT - 5))
			if not _zone_is_free(center):
				continue
			generator.carve_boss_room(grid, center, MAZE_WIDTH, MAZE_HEIGHT)
			_restrict_zone(center)
			mini_boss_cells.append(center)
			maze_view.register_sticky_zone(_zone_cells(center))

			var mini_boss: EnemyAgent = ENEMY_SCENE.instantiate()
			enemy_container.add_child(mini_boss)
			mini_boss.setup(center, CELL_SIZE, MINI_BOSS_LEVEL, grid, enemy_map, {}, npcs, false)
			mini_boss.is_mini_boss = true
			mini_boss.visual.color = Color(0.55, 0.15, 0.75, 1.0)
			mini_boss.scale = Vector2(MINI_BOSS_SCALE, MINI_BOSS_SCALE)
			mini_boss.mini_boss_defeated.connect(_on_mini_boss_defeated)
			break

func _on_mini_boss_defeated(cell: Vector2i) -> void:
	_place_chest(cell, ItemCatalog.RARITY_SILVER)

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
		if randf() < PACK_ENCOUNTER_CHANCE:
			_spawn_enemy_pack(cell, level)
		else:
			var enemy: EnemyAgent = ENEMY_SCENE.instantiate()
			enemy_container.add_child(enemy)
			enemy.setup(cell, CELL_SIZE, level, grid, enemy_map, restricted_cells, npcs)

## A handful of individually weaker enemies sharing one encounter in place
## of a single enemy at full strength — fights the same way a lone enemy
## does, just with more bodies for a party to work through.
func _spawn_enemy_pack(cell: Vector2i, base_level: int) -> void:
	var pack_size: int = 2 + (1 if randf() < 0.5 else 0)
	var pack_level: int = max(1, int(round(base_level * PACK_LEVEL_SCALE)))
	var members: Array = []
	for i in range(pack_size):
		var enemy: EnemyAgent = ENEMY_SCENE.instantiate()
		enemy_container.add_child(enemy)
		enemy.setup(cell, CELL_SIZE, pack_level, grid, enemy_map, restricted_cells, npcs)
		members.append(enemy)
	EnemyAgent.form_pack(members)

## A single stationary, much stronger enemy guards the exit cell. Since a
## live enemy always blocks its cell until defeated, nobody can set foot on
## the goal until the boss falls — and the NPC that lands the winning blow
## is the same one whose move immediately after that carries it onto the
## goal, so the boss-slayer is guaranteed to be first through.
func _spawn_boss() -> void:
	var boss: EnemyAgent = ENEMY_SCENE.instantiate()
	enemy_container.add_child(boss)
	boss.setup(exit_cell, CELL_SIZE, BOSS_LEVEL, grid, enemy_map, {}, npcs, false)
	boss.is_boss = true
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

func _place_chest(cell: Vector2i, rarity: String = ItemCatalog.RARITY_BRONZE) -> void:
	var chest: ChestAgent = CHEST_SCENE.instantiate()
	chest_container.add_child(chest)
	chest.setup(cell, CELL_SIZE, rarity)
	chest_map[cell] = chest

## Drops everything a fallen character was carrying where they died. If
## another chest already sits on that exact cell (two characters happening to
## die in the same spot), the loot is merged into it instead of replacing it.
func _place_death_chest(cell: Vector2i, loot: Dictionary, gold: int) -> void:
	if loot.is_empty() and gold <= 0:
		return
	if chest_map.has(cell):
		var existing: ChestAgent = chest_map[cell]
		existing.merge_in(loot, gold)
		return
	var chest: ChestAgent = CHEST_SCENE.instantiate()
	chest_container.add_child(chest)
	chest.setup_from_death(cell, CELL_SIZE, loot, gold)
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
		npc.setup(start_cell, exit_cell, grid, CELL_SIZE, color, display_name, enemy_map, chest_map, shop_map, player_map, restricted_cells)
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
	_place_grave(npc)
	hud.mark_dead(npc)
	_place_death_chest(npc.cell_pos, npc.stats.inventory.duplicate(), npc.stats.gold)
	if npcs.is_empty() and winner == null:
		hud.announce_no_winner()

## A gravestone exactly where `npc`'s icon stood when they fell.
func _place_grave(npc: NpcAgent) -> void:
	var grave: Node2D = GRAVE_SCENE.instantiate()
	grave.position = npc.position
	grave_container.add_child(grave)
	graves[npc] = grave
	_sync_selection_highlight()  # in case they were selected: ring the grave now

func _on_npc_leveled_up(npc: NpcAgent) -> void:
	hud.refresh_npc(npc)
	hud.flash_level_up(npc)
