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
## Monsters regen far slower than the shared formula's baseline (players use
## the same formula for MP, a resource meant to refill quickly) — otherwise a
## tough enemy fully heals in the time it takes to retreat and come back,
## which would make wearing it down across several attempts pointless.
const REGEN_TIME_SCALE := 0.03

## How far a monster's map icon reaches from its middle (see
## MonsterKind.outline).
const ICON_RADIUS := 9.0

## Emitted by the last of a pack to fall, as it does -- the whole pack's
## beaten, on `cell` (see WorldBuilder: a mid boss's party leaves a chest).
signal pack_defeated(cell: Vector2i)

var cell_pos: Vector2i = Vector2i.ZERO
var home_cell: Vector2i = Vector2i.ZERO
## The same stat block characters use (see NpcStats.for_enemy).
var stats: NpcStats
## What kind of monster it is -- a Rat, a Troll, the Dragon -- which goes
## with its level (see MonsterCatalog).
var kind: MonsterKind
var alive: bool = true
var in_combat: bool = false
## The shared party array of whoever this pack is fighting (set alongside
## in_combat by GroupCombat.engage_pack, and only meaningful while that's true) --
## lets a player who walks up to the monster side of a fight find the
## fighters and join them.
var fighting_party: Array = []
var is_moving: bool = false
var is_mid_boss: bool = false
## The one guarding the exit (see WorldBuilder._spawn_boss).
var is_boss: bool = false
## Stationary bosses never chase or wander, but still tick for HP regen. A
## pack's non-leader members also have this false, for the same reason.
var wanders: bool = true
## Other enemies sharing this same encounter (a pack of 2-3 weaker enemies
## in place of one full-strength one), including self. Only the leader
## wanders/chases/registers in `enemies`; followers are stationary (like a
## boss) and just tag along visually, but the whole living pack joins any
## fight against it. Solo enemies just have themselves in this list.
var pack: Array = []
var is_pack_leader: bool = true
var pack_offset: Vector2 = Vector2.ZERO
## Whether it's the roaming kind (see setup's `can_wander`): a pack's
## follower doesn't wander, but takes it up again if it ends up leading the
## pack. A boss's guards never do.
var roams: bool = true
## Who this monster guards, if it's one of a boss's party -- "the Dragon",
## "an Ogre Warlord" (see WorldBuilder) -- for how it reads as a killer.
var guarding: String = ""

var grid: Array = []
var cell_size: float = 40.0
var enemies: Dictionary = {}
var forbidden: Dictionary = {}
var players: Array = []

var _wander_cooldown: float = 0.0

@onready var visual: Polygon2D = $Visual
@onready var label: Label = $Label

func setup(cell: Vector2i, cs: float, enemy_level: int, maze_grid: Array, enemy_map: Dictionary,
		forbidden_cells: Dictionary, player_list: Array, can_wander: bool = true) -> void:
	cell_pos = cell
	home_cell = cell
	stats = NpcStats.for_enemy(enemy_level)
	grid = maze_grid
	cell_size = cs
	enemies = enemy_map
	forbidden = forbidden_cells
	players = player_list
	wanders = can_wander
	roams = can_wander
	position = Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)
	set_kind(MonsterCatalog.for_level(stats.level))
	enemies[cell_pos] = self
	pack = [self]
	if wanders:
		_wander_cooldown = randf_range(WANDER_MIN_WAIT, WANDER_MAX_WAIT)
	_schedule_next_think(randf_range(0.0, THINK_SECONDS))

## Makes it a `new_kind` of monster (see MonsterCatalog) -- the kind for
## its level, unless it's an Orc Chieftain -- and shows it on its icon.
func set_kind(new_kind: MonsterKind) -> void:
	kind = new_kind
	var icon := kind.outline()
	for i in range(icon.size()):
		icon[i] *= ICON_RADIUS
	visual.polygon = icon
	visual.color = kind.color
	label.text = "%d" % stats.level
	label.add_theme_color_override("font_color", Color.BLACK if visual.color.get_luminance() > 0.45 else Color.WHITE)

## Links several already-set-up enemies into one pack sharing a single
## encounter: only the first keeps wandering/chasing and blocking the cell
## for movement purposes; the rest become stationary followers (just like a
## stationary boss — still regenerating HP, just never acting on their own)
## that visually tag along and join any fight the pack gets into. The
## followers stand `spread` pixels each way from the leader's middle.
static func form_pack(members: Array, spread: float = 7.0) -> void:
	if members.size() < 2:
		return
	for m in members:
		m.pack = members
	var leader: EnemyAgent = members[0]
	var offsets := [Vector2(-spread, -spread), Vector2(spread, -spread), Vector2(-spread, spread), Vector2(spread, spread)]
	for i in range(1, members.size()):
		var follower: EnemyAgent = members[i]
		follower.is_pack_leader = false
		follower.wanders = false
		follower.cell_pos = leader.cell_pos
		follower.pack_offset = offsets[(i - 1) % offsets.size()]
		follower.position = leader.position + follower.pack_offset
	leader.enemies[leader.cell_pos] = leader

## How this monster reads as a player's killer, for their HUD panel (see
## NpcAgent.killed_by): "the Dragon (Lv.12)", "a Troll (Lv.8)" -- noting the
## boss it was guarding or the pack it was part of, if either:
## "a Wyvern (Lv.10), guarding the Dragon", "a Rat (Lv.2), one of a pack of 3".
func killer_description() -> String:
	var desc := "%s (Lv.%d)" % [kind.called(is_boss), stats.level]
	if guarding != "":
		desc += ", guarding " + guarding
	elif pack.size() > 1 and not is_mid_boss and not is_boss:
		desc += ", one of a pack of %d" % pack.size()
	return desc

## Whether it's one of a boss's party -- the boss on the exit, a mid boss,
## or a guard of either -- holding a boss room it never leaves.
func in_boss_party() -> bool:
	return is_boss or is_mid_boss or guarding != ""

## Every living member of this enemy's pack, including itself.
func living_pack() -> Array:
	var result: Array = []
	for m in pack:
		if is_instance_valid(m) and m.alive:
			result.append(m)
	return result

## Releases every living pack member from the fight, not just whoever's
## leading the pack right now -- a follower left still marked in_combat
## would freeze the moment it got promoted to leader (see _think), and
## block its cell for good (players won't engage or pass a busy pack).
func end_combat() -> void:
	for m in living_pack():
		m.in_combat = false
		m.fighting_party = []

func defeat() -> void:
	alive = false
	pack.erase(self)
	if pack.is_empty():
		pack_defeated.emit(cell_pos)
	if is_pack_leader:
		if pack.is_empty():
			enemies.erase(cell_pos)
		else:
			_promote_next_pack_leader()
	queue_free()

## If the pack's leader falls but others survive, one of them takes over
## wandering/chasing and blocking the cell — otherwise the rest of the pack
## would be stuck doing nothing forever, with nobody driving the pack.
func _promote_next_pack_leader() -> void:
	for m in pack:
		if is_instance_valid(m) and m.alive:
			m.is_pack_leader = true
			m.wanders = m.roams
			m.pack_offset = Vector2.ZERO
			m.position = position
			m.cell_pos = cell_pos
			enemies[cell_pos] = m
			return
	enemies.erase(cell_pos)

func _schedule_next_think(wait_time: float = THINK_SECONDS) -> void:
	var timer := get_tree().create_timer(wait_time, false)
	timer.timeout.connect(_on_think_timer)

func _on_think_timer() -> void:
	if not alive:
		return
	## Passive regen whenever not actively fighting — the same rule for a
	## stationary boss standing idle as for a wandering enemy between fights.
	if not in_combat:
		stats.regen_hp(THINK_SECONDS * REGEN_TIME_SCALE)
	_think()
	_schedule_next_think()

## Chases a player it can see; otherwise drifts home if it has strayed, or
## wanders about near home at its own slow pace. Does nothing at all for a
## stationary boss beyond the regen already handled in _on_think_timer.
func _think() -> void:
	if is_moving or in_combat or not wanders:
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
	return MazeQuery.manhattan(cell, home_cell)

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
	for member in pack:
		if member != self and is_instance_valid(member) and member.alive:
			member._follow_pack_move(target, seconds)

## A pack follower tagging along with its leader's move, offset slightly so
## the whole pack stays visible as distinct enemies.
func _follow_pack_move(target: Vector2i, seconds: float) -> void:
	cell_pos = target
	var target_world := Vector2((target.x + 0.5) * cell_size, (target.y + 0.5) * cell_size) + pack_offset
	var tween := create_tween()
	tween.tween_property(self, "position", target_world, seconds)
