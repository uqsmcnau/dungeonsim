class_name EnemyAgent
extends Node2D

const THINK_SECONDS := 0.3
const WANDER_MIN_WAIT := 1.5
const WANDER_MAX_WAIT := 3.5
const WANDER_MOVE_SECONDS := 1.2
const LEASH_RADIUS := 2
## An enemy that spots a player gives chase, but only out to this far from
## home, and walks back once it loses sight of them.
const SIGHT_RANGE := 4
const CHASE_MOVE_SECONDS := 0.8
const CHASE_LEASH_RADIUS := 6

var cell_pos: Vector2i = Vector2i.ZERO
var home_cell: Vector2i = Vector2i.ZERO
## The same stat block characters use (see NpcStats.for_enemy).
var stats: NpcStats
var alive: bool = true
var in_combat: bool = false
var is_moving: bool = false

var grid: Array = []
var cell_size: float = 40.0
var enemies: Dictionary = {}
var forbidden: Dictionary = {}
var players: Array = []

var _wander_cooldown: float = 0.0

@onready var visual: Polygon2D = $Visual
@onready var label: Label = $Label

func setup(cell: Vector2i, cs: float, enemy_level: int, maze_grid: Array, enemy_map: Dictionary, forbidden_cells: Dictionary, player_list: Array, wanders: bool = true) -> void:
	cell_pos = cell
	home_cell = cell
	stats = NpcStats.for_enemy(enemy_level)
	grid = maze_grid
	cell_size = cs
	enemies = enemy_map
	forbidden = forbidden_cells
	players = player_list
	position = Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)
	visual.color = Color(1.0, clampf(0.6 - stats.level * 0.08, 0.05, 0.6), 0.05, 1.0)
	label.text = "%d" % stats.level
	enemies[cell_pos] = self
	if wanders:
		_wander_cooldown = randf_range(WANDER_MIN_WAIT, WANDER_MAX_WAIT)
		_schedule_next_think(randf_range(0.0, THINK_SECONDS))

func defeat() -> void:
	alive = false
	queue_free()

func _schedule_next_think(wait_time: float = THINK_SECONDS) -> void:
	var timer := get_tree().create_timer(wait_time)
	timer.timeout.connect(_on_think_timer)

func _on_think_timer() -> void:
	if not alive:
		return
	_think()
	_schedule_next_think()

## Chases a player it can see; otherwise drifts home if it has strayed, or
## wanders about near home at its own slow pace.
func _think() -> void:
	if is_moving or in_combat:
		return

	var chase := _chase_step()
	if chase != cell_pos:
		_move_to(chase, CHASE_MOVE_SECONDS)
		return

	_wander_cooldown -= THINK_SECONDS
	if _wander_cooldown > 0.0:
		return
	_wander_cooldown = randf_range(WANDER_MIN_WAIT, WANDER_MAX_WAIT)
	if _dist_from_home(cell_pos) > LEASH_RADIUS:
		_return_home_step()
	else:
		_try_wander()

## Next step toward the nearest visible player, or our own cell if none is in
## sight, the way there is blocked, or it would take us beyond the chase leash.
func _chase_step() -> Vector2i:
	var targets: Dictionary = {}
	for p in players:
		if is_instance_valid(p) and not p.dead:
			targets[p.cell_pos] = true
	if targets.is_empty():
		return cell_pos

	var target := MazeQuery.nearest_visible(grid, cell_pos, SIGHT_RANGE, targets)
	if target == MazeQuery.NONE:
		return cell_pos

	var step := MazeQuery.step_toward(grid, cell_pos, target, SIGHT_RANGE * 2, _blocked_cells())
	if step == cell_pos or _dist_from_home(step) > CHASE_LEASH_RADIUS:
		return cell_pos
	return step

func _return_home_step() -> void:
	var step := MazeQuery.step_toward(grid, cell_pos, home_cell, CHASE_LEASH_RADIUS + 4, _blocked_cells())
	if step != cell_pos:
		_move_to(step)

## Cells this enemy may never step onto: restricted zones (safe zones, the
## boss room) and anywhere another enemy already stands.
func _blocked_cells() -> Dictionary:
	var blocked := forbidden.duplicate()
	blocked.merge(enemies)
	return blocked

func _dist_from_home(cell: Vector2i) -> int:
	return abs(cell.x - home_cell.x) + abs(cell.y - home_cell.y)

## Steps to a random open neighbor, but only if it stays within LEASH_RADIUS
## of the spawn cell and isn't already occupied by another enemy.
func _try_wander() -> void:
	var valid: Array = []
	for c in MazeQuery.open_neighbors(grid, cell_pos):
		if forbidden.has(c) or enemies.has(c):
			continue
		if _dist_from_home(c) <= LEASH_RADIUS:
			valid.append(c)
	if valid.is_empty():
		return
	_move_to(valid[randi() % valid.size()])

func _move_to(target: Vector2i, seconds: float = WANDER_MOVE_SECONDS) -> void:
	is_moving = true
	enemies.erase(cell_pos)
	cell_pos = target
	enemies[cell_pos] = self
	var target_world := Vector2((target.x + 0.5) * cell_size, (target.y + 0.5) * cell_size)
	var tween := create_tween()
	tween.tween_property(self, "position", target_world, seconds)
	tween.finished.connect(func(): is_moving = false)
