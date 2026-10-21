class_name MonsterRespawner
extends RefCounted

## Monster respawning: the maze is split into AREA_SIZE x AREA_SIZE-cell
## areas, each remembering how many monsters it started with (see
## area_capacity). An area that's lost some slowly gets them back -- one
## encounter every RESPAWN_SECONDS of game time -- but never past its
## original count, and only out of sight of every player and at least
## RESPAWN_MIN_PLAYER_DISTANCE cells (in either direction) from all of
## them. If there's nowhere hidden to put one, it tries again every
## RESPAWN_RETRY_SECONDS. Bosses and mini bosses never come back.
const AREA_SIZE := 8
const RESPAWN_SECONDS := 40.0
const RESPAWN_RETRY_SECONDS := 2.0
const RESPAWN_MIN_PLAYER_DISTANCE := 9
## How often respawning is checked on -- counting every area's monsters
## each frame would be wasted work for timers measured in tens of seconds.
const RESPAWN_CHECK_SECONDS := 1.0

var game: GameManager
var world: WorldBuilder
## How many monsters each area (see area_of) started out with -- the most
## respawning will ever bring it back up to. Monsters belong to the area of
## their home cell: they're leashed close to it (see EnemyAgent), so they
## never really leave.
var area_capacity: Dictionary = {}
## For each area that's below its capacity, seconds until its next respawn.
var area_respawn_timers: Dictionary = {}
## Game time gone by since respawning was last checked on.
var _check_elapsed: float = 0.0

## Made once the world's been stocked: whatever's there then is what each
## area will be brought back up to.
func _init(owner: GameManager, builder: WorldBuilder) -> void:
	game = owner
	world = builder
	area_capacity = area_populations()

## Called every frame by GameManager; checks on respawning every
## RESPAWN_CHECK_SECONDS, with all the time gone by since.
func tick(delta: float) -> void:
	_check_elapsed += delta
	if _check_elapsed >= RESPAWN_CHECK_SECONDS:
		tick_respawns(_check_elapsed)
		_check_elapsed = 0.0

## Which area (see AREA_SIZE) a cell belongs to.
func area_of(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x / AREA_SIZE, cell.y / AREA_SIZE)

## How many living monsters belong to each area right now (by home cell),
## leaving out bosses and mini bosses, which never respawn.
func area_populations() -> Dictionary:
	var counts: Dictionary = {}
	for enemy in game.enemy_container.get_children():
		if not enemy is EnemyAgent or not enemy.alive or enemy.is_boss or enemy.is_mini_boss:
			continue
		var area := area_of(enemy.home_cell)
		counts[area] = int(counts.get(area, 0)) + 1
	return counts

## Counts down each area that's short of monsters, and gives it one more
## encounter when its time's up (see AREA_SIZE). Runs from _process every
## RESPAWN_CHECK_SECONDS, with all the time gone by since, so it stops while
## the game's paused.
func tick_respawns(delta: float) -> void:
	var populations := area_populations()
	for area in area_capacity:
		var missing: int = int(area_capacity[area]) - int(populations.get(area, 0))
		if missing <= 0:
			area_respawn_timers.erase(area)
			continue
		var left: float = float(area_respawn_timers.get(area, RESPAWN_SECONDS)) - delta
		if left > 0.0:
			area_respawn_timers[area] = left
		elif _respawn_in(area, missing):
			area_respawn_timers[area] = RESPAWN_SECONDS
		else:
			area_respawn_timers[area] = RESPAWN_RETRY_SECONDS

## Spawns one encounter -- a lone monster, or a pack no bigger than `room`
## -- on a hidden cell in `area`. False if there's nowhere hidden to put it.
func _respawn_in(area: Vector2i, room: int) -> bool:
	var cell := hidden_spawn_cell(area)
	if cell == MazeQuery.NONE:
		return false
	var level := world.enemy_level_for(cell)
	if room >= 2 and randf() < WorldBuilder.PACK_ENCOUNTER_CHANCE:
		world.spawn_enemy_pack(cell, level, room)
	else:
		world.spawn_enemy(cell, level)
	return true

## A random cell in `area` where a monster could appear without anyone
## seeing it happen: outside safe zones, with nothing already on it, out of
## every living player's sight and at least RESPAWN_MIN_PLAYER_DISTANCE
## from all of them -- or NONE if there's no such cell.
func hidden_spawn_cell(area: Vector2i) -> Vector2i:
	var candidates: Array = []
	for y in range(area.y * AREA_SIZE, mini((area.y + 1) * AREA_SIZE, GameManager.MAZE_HEIGHT)):
		for x in range(area.x * AREA_SIZE, mini((area.x + 1) * AREA_SIZE, GameManager.MAZE_WIDTH)):
			var c := Vector2i(x, y)
			if MazeGenerator.is_outside(game.grid, c) or game.restricted_cells.has(c):
				continue
			if game.enemy_map.has(c) or game.chest_map.has(c) or game.player_map.has(c):
				continue
			if _seen_or_near_a_player(c):
				continue
			candidates.append(c)
	if candidates.is_empty():
		return MazeQuery.NONE
	return candidates[randi() % candidates.size()]

func _seen_or_near_a_player(cell: Vector2i) -> bool:
	for npc in game.npcs:
		if npc.dead:
			continue
		if npc.sight_cells.has(cell):
			return true
		if max(abs(cell.x - npc.cell_pos.x), abs(cell.y - npc.cell_pos.y)) < RESPAWN_MIN_PLAYER_DISTANCE:
			return true
	return false
