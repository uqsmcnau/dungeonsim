class_name NpcAgent
extends Node2D

const TURN_SECONDS := 1.0

const RECOVER_MP_COST := 5
const RECOVER_CAST_SECONDS := 1.0
const OUT_OF_COMBAT_HEAL_THRESHOLD := 0.9
const IN_COMBAT_HEAL_THRESHOLD := 0.5
## Break off a fight once HP is down to this many expected enemy hits.
const FLEE_DANGER_TURNS := 0.5
## Enemies occasionally hit harder than a character can plan around, which
## is what keeps even a careful character from being completely safe.
const ENEMY_CRIT_CHANCE := 0.27
const ENEMY_CRIT_MULTIPLIER := 2.0
## How far (in cells) a character can see, and how far ahead it will plan a
## route to a chest it has spotted.
const SIGHT_RANGE := 6
const CHEST_PATH_DEPTH := 24
## A shop trip is only worth it if the shop is within this many steps.
const SHOP_PATH_DEPTH := 80
const SHOPPING_SECONDS := 1.0
const CONSUME_SECONDS := 1.0
## Below this fraction of max MP, top up with a Mana Potion if carrying one.
const LOW_MANA_FRACTION := 0.3

signal reached_exit(npc: NpcAgent)
signal leveled_up(npc: NpcAgent)
signal died(npc: NpcAgent)

@export var npc_name: String = "NPC"
@export var move_seconds_base: float = 0.35

var stats: NpcStats
var grid: Array = []
var cell_size: float = 48.0
var cell_pos: Vector2i = Vector2i.ZERO
var exit_cell: Vector2i = Vector2i.ZERO
var visited: Dictionary = {}
var enemies: Dictionary = {}
var chests: Dictionary = {}
var chest_goal: Vector2i = MazeQuery.NONE
## Every shop in the world, and the ones this character has actually laid
## eyes on (it only makes trips to shops it knows about).
var shops: Dictionary = {}
var known_shops: Dictionary = {}
var is_moving: bool = false
var finished: bool = false
var dead: bool = false
## What this character is doing right now, in plain words, for the HUD.
var current_action: String = "Exploring"

@onready var visual: Polygon2D = $Visual
@onready var name_label: Label = $NameLabel

func setup(spawn_cell: Vector2i, target_cell: Vector2i, maze_grid: Array, cs: float, color: Color, display_name: String, enemy_map: Dictionary, chest_map: Dictionary, shop_map: Dictionary) -> void:
	cell_pos = spawn_cell
	exit_cell = target_cell
	grid = maze_grid
	cell_size = cs
	npc_name = display_name
	enemies = enemy_map
	chests = chest_map
	shops = shop_map
	stats = NpcStats.new()
	stats.roll_ability_scores()
	visited[cell_pos] = true
	visual.color = color
	position = _cell_to_world(cell_pos)
	_update_label()
	_check_for_chest()

func _process(delta: float) -> void:
	if dead:
		return
	stats.regen_mp(delta)
	if finished or is_moving:
		return
	## Safety net: if a live enemy is ever standing on our own cell (e.g. one
	## wandered into our destination while we were mid-transit), resolve that
	## before doing anything else, so an enemy can never be walked past.
	if _has_live_enemy(cell_pos):
		var enemy: EnemyAgent = enemies[cell_pos]
		if enemy.in_combat:
			return
		if _decide_fight(enemy):
			_engage(cell_pos, enemy)
			return
		_retreat()
		if is_moving:
			return
	var pending_tome := _pending_tome()
	if pending_tome != "":
		_consume_item_idle(pending_tome)
		return
	if _needs_healing():
		if stats.mp >= RECOVER_MP_COST:
			_cast_recover_idle()
		elif stats.has_item("Health Potion"):
			_consume_item_idle("Health Potion")
		else:
			current_action = "Resting"
		return
	if stats.mp < int(stats.max_mp * LOW_MANA_FRACTION) and stats.has_item("Mana Potion"):
		_consume_item_idle("Mana Potion")
		return
	_take_step()

## Outside combat, a hurt character stops to recover rather than pressing on
## injured — casting Recover when it can afford it, drinking a Health Potion
## if it has one and can't, or just waiting for its mana to regenerate.
func _needs_healing() -> bool:
	return stats.hp < int(stats.max_hp * OUT_OF_COMBAT_HEAL_THRESHOLD)

## An unread tome the character is carrying, if any — Fireball takes priority
## over Spark since it's the stronger spell. Read at the next idle moment,
## since there's no reason to delay learning a permanent spell.
func _pending_tome() -> String:
	for item_name in ["Tome of Fireball", "Tome of Spark"]:
		if not stats.has_item(item_name):
			continue
		var spell: String = ItemCatalog.find(item_name)["spell"]
		if not stats.knows_spell(spell):
			return item_name
	return ""

func _cast_recover_idle() -> void:
	is_moving = true
	current_action = "Casting Recover"
	name_label.text = "%s ✨ Recover" % npc_name
	var timer := get_tree().create_timer(RECOVER_CAST_SECONDS)
	timer.timeout.connect(_finish_recover_idle)

func _finish_recover_idle() -> void:
	stats.mp -= RECOVER_MP_COST
	stats.hp = min(stats.max_hp, stats.hp + stats.recover_power())
	is_moving = false
	_update_label()

## Applies a consumable's effect (a heal, a mana top-up, or learning a spell
## from a tome) and uses up the one copy that was consumed.
func _apply_consumable_effect(item_name: String) -> void:
	var item := ItemCatalog.find(item_name)
	match item.get("effect", ""):
		"heal_hp":
			stats.hp = min(stats.max_hp, stats.hp + int(item["amount"]))
		"restore_mp":
			stats.mp = min(stats.max_mp, stats.mp + int(item["amount"]))
		"learn_spell":
			stats.learn_spell(item["spell"])
	stats.consume_item(item_name)

func _consume_verb(item_name: String) -> String:
	return "Reading" if ItemCatalog.find(item_name).get("effect") == "learn_spell" else "Drinking"

## Consuming an item — a potion or a tome — takes a full action outside
## combat too, the same as casting a spell does.
func _consume_item_idle(item_name: String) -> void:
	is_moving = true
	var verb := _consume_verb(item_name)
	current_action = "%s %s" % [verb, item_name]
	name_label.text = "%s %s %s" % [npc_name, verb, item_name]
	var timer := get_tree().create_timer(CONSUME_SECONDS)
	timer.timeout.connect(_finish_consume_idle.bind(item_name))

func _finish_consume_idle(item_name: String) -> void:
	_apply_consumable_effect(item_name)
	is_moving = false
	_update_label()

func _take_step() -> void:
	_notice_shops()

	# Priorities: a shop worth visiting, then a chest in sight, then exploring
	# — and neither is worth picking a fight over, so an enemy in the way
	# means carrying on with the next option instead.
	var shop_step := _shop_step()
	if shop_step != cell_pos and not _has_live_enemy(shop_step):
		_move_to(shop_step)
		return

	var chest_step := _chest_step()
	if chest_step != cell_pos and not _has_live_enemy(chest_step):
		_move_to(chest_step)
		return

	var open_dirs := MazeQuery.open_neighbors(grid, cell_pos)
	if open_dirs.is_empty():
		return
	var candidate := _choose_candidate(open_dirs)
	if candidate == cell_pos:
		return
	_attempt_move(candidate)

## Remembers any shop currently in sight.
func _notice_shops() -> void:
	var seen := MazeQuery.nearest_visible(grid, cell_pos, SIGHT_RANGE, shops)
	if seen != MazeQuery.NONE:
		known_shops[seen] = true

## Next step toward the nearest known shop — but only while there's something
## to do there (spare items to sell, or gold for an item we don't have yet).
func _shop_step() -> Vector2i:
	if known_shops.is_empty() or not stats.has_shop_business():
		return cell_pos
	var nearest := MazeQuery.NONE
	var nearest_dist := 1 << 30
	for c in known_shops:
		var d: int = abs(c.x - cell_pos.x) + abs(c.y - cell_pos.y)
		if d < nearest_dist:
			nearest = c
			nearest_dist = d
	return MazeQuery.step_toward(grid, cell_pos, nearest, SHOP_PATH_DEPTH)

## Sells spares and buys anything missing that the gold stretches to.
func _start_shopping() -> void:
	is_moving = true
	current_action = "Shopping"
	name_label.text = "%s $ Shopping" % npc_name
	var timer := get_tree().create_timer(SHOPPING_SECONDS)
	timer.timeout.connect(_finish_shopping)

func _finish_shopping() -> void:
	if dead:
		return
	var sold := stats.sell_spares()
	var bought := stats.buy_missing()
	bought.append_array(stats.buy_potions())
	is_moving = false
	if sold > 0 or not bought.is_empty():
		name_label.text = "%s sold %d, bought %d" % [npc_name, sold, bought.size()]
		var timer := get_tree().create_timer(1.5)
		timer.timeout.connect(_update_label)
	else:
		_update_label()

## Next step toward a chest, or our own cell if there's none to go for. Once
## a chest has been spotted it stays the goal (even if the route around a
## corner briefly loses sight of it) until it's taken by someone or turns out
## to be unreachable.
func _chest_step() -> Vector2i:
	if chest_goal != MazeQuery.NONE and not chests.has(chest_goal):
		chest_goal = MazeQuery.NONE
	if chest_goal == MazeQuery.NONE:
		chest_goal = MazeQuery.nearest_visible(grid, cell_pos, SIGHT_RANGE, chests)
	if chest_goal == MazeQuery.NONE:
		return cell_pos
	var step := MazeQuery.step_toward(grid, cell_pos, chest_goal, CHEST_PATH_DEPTH)
	if step == cell_pos:
		chest_goal = MazeQuery.NONE
	return step

## Prefers an unvisited, enemy-free cell; falls back to any unvisited cell
## (even an enemy's) once safe options run out, then to the BFS frontier
## search, then to a random already-visited neighbor if fully boxed in.
func _choose_candidate(open_dirs: Array) -> Vector2i:
	var unvisited: Array = []
	for c in open_dirs:
		if not visited.has(c):
			unvisited.append(c)

	if unvisited.is_empty():
		var frontier_step := _step_toward_frontier()
		if frontier_step != cell_pos:
			return frontier_step
		return open_dirs[randi() % open_dirs.size()]

	var safe: Array = []
	for c in unvisited:
		if not _has_live_enemy(c):
			safe.append(c)
	if safe.size() > 0:
		return safe[randi() % safe.size()]
	return unvisited[randi() % unvisited.size()]

func _has_live_enemy(cell: Vector2i) -> bool:
	if not enemies.has(cell):
		return false
	var enemy = enemies[cell]
	return enemy != null and is_instance_valid(enemy) and enemy.alive

## If the destination holds a live enemy, decide whether to fight (a battle
## fought in 1-second turns) or flee (retreat toward already-explored ground
## instead). A live enemy always blocks the cell until it's defeated. If
## another NPC is already fighting it, wait it out.
func _attempt_move(next_cell: Vector2i) -> void:
	if _has_live_enemy(next_cell):
		var enemy: EnemyAgent = enemies[next_cell]
		if enemy.in_combat:
			_retreat()
		elif _decide_fight(enemy):
			_engage(next_cell, enemy)
		else:
			_retreat()
		return
	_move_to(next_cell)

func _player_hit_chance(enemy: EnemyAgent) -> float:
	return CombatRules.hit_chance(stats.accuracy(), enemy.stats.evasion())

func _enemy_hit_chance(enemy: EnemyAgent) -> float:
	return CombatRules.hit_chance(enemy.stats.accuracy(), stats.evasion())

## Average damage of one of our hits / one of theirs, assuming it lands.
func _damage_per_hit_dealt(enemy: EnemyAgent) -> float:
	return max(1.0, stats.attack_power() + 1.5 - enemy.stats.defense())

func _damage_per_hit_taken(enemy: EnemyAgent) -> float:
	return max(1.0, enemy.stats.attack_power() + 1.0 - stats.defense())

## Average damage per turn, counting the turns an attack misses.
func _expected_damage_dealt(enemy: EnemyAgent) -> float:
	return _player_hit_chance(enemy) * _damage_per_hit_dealt(enemy)

func _expected_damage_taken(enemy: EnemyAgent) -> float:
	return _enemy_hit_chance(enemy) * _damage_per_hit_taken(enemy)

## Compares how many turns it'd take to kill the enemy against how many it
## would take to be killed, and fights with a probability that reflects it.
func _decide_fight(enemy: EnemyAgent) -> bool:
	var turns_to_kill: float = max(enemy.stats.hp, 1) / _expected_damage_dealt(enemy)
	var turns_to_die: float = max(stats.hp, 1) / _expected_damage_taken(enemy)
	var win_chance: float = clampf(turns_to_die / (turns_to_die + turns_to_kill), 0.05, 0.95)
	return randf() < win_chance

## Breaks off a fight that's turning dangerous. Damage already dealt stays on
## the enemy, so a character can retreat, recover, and come back to finish it.
func _disengage(enemy: EnemyAgent) -> void:
	enemy.in_combat = false
	is_moving = false
	_update_label()
	_retreat()

## Starts a battle fought in 1-second turns: the NPC is locked in place for
## the duration of each turn, and the fight keeps going (attack, spell,
## potion or Recover, chosen fresh each turn) until one side falls.
func _engage(next_cell: Vector2i, enemy: EnemyAgent) -> void:
	is_moving = true
	enemy.in_combat = true
	_run_combat_turn(next_cell, enemy)

## Survival first (Recover, or a Health Potion if it can't afford that), then
## whichever of its attack spells or a plain attack actually deals the most
## damage right now. A spell's damage is fixed by intelligence while a plain
## attack scales with strength, level and weapon bonuses, so a spell that
## out-damages a fresh character is often no longer the better choice once
## they've leveled up or found a sword — this compares them fresh each turn
## rather than always preferring magic once it's known.
func _choose_combat_action(enemy: EnemyAgent) -> String:
	if stats.hp < int(stats.max_hp * IN_COMBAT_HEAL_THRESHOLD):
		if stats.mp >= RECOVER_MP_COST:
			return "recover"
		if stats.has_item("Health Potion"):
			return "potion_hp"

	var best_action := "attack"
	var best_damage: float = _expected_damage_dealt(enemy)
	# Never spend the last of its mana on offense — always keep enough in
	# reserve for one emergency Recover, so a spellcaster can't run itself
	# out of healing by attacking too aggressively.
	if stats.knows_spell("spark") and stats.mp - NpcStats.SPARK_MP_COST >= RECOVER_MP_COST and stats.spark_power() > best_damage:
		best_action = "spark"
		best_damage = stats.spark_power()
	if stats.knows_spell("fireball") and stats.mp - NpcStats.FIREBALL_MP_COST >= RECOVER_MP_COST and stats.fireball_power() > best_damage:
		best_action = "fireball"
		best_damage = stats.fireball_power()
	return best_action

func _run_combat_turn(next_cell: Vector2i, enemy: EnemyAgent) -> void:
	if not is_instance_valid(enemy) or not enemy.alive:
		is_moving = false
		_update_label()
		_move_to(next_cell)
		return

	if stats.hp <= _damage_per_hit_taken(enemy) * FLEE_DANGER_TURNS:
		_disengage(enemy)
		return

	var action := _choose_combat_action(enemy)
	match action:
		"recover":
			current_action = "Casting Recover"
			name_label.text = "%s ✨ Recover" % npc_name
		"potion_hp":
			current_action = "Drinking Health Potion"
			name_label.text = "%s Health Potion" % npc_name
		"fireball":
			current_action = "Casting Fireball"
			name_label.text = "%s 🔥 Fireball" % npc_name
		"spark":
			current_action = "Casting Spark"
			name_label.text = "%s ⚡ Spark" % npc_name
		_:
			current_action = "Fighting a level %d enemy" % enemy.stats.level
			name_label.text = "%s ⚔ Lv.%d" % [npc_name, enemy.stats.level]

	var timer := get_tree().create_timer(TURN_SECONDS)
	timer.timeout.connect(_resolve_combat_turn.bind(next_cell, enemy, action))

func _resolve_combat_turn(next_cell: Vector2i, enemy: EnemyAgent, action: String) -> void:
	if not is_instance_valid(enemy) or not enemy.alive:
		is_moving = false
		_update_label()
		_move_to(next_cell)
		return

	match action:
		"recover":
			stats.mp -= RECOVER_MP_COST
			stats.hp = min(stats.max_hp, stats.hp + stats.recover_power())
		"potion_hp":
			_apply_consumable_effect("Health Potion")
		"fireball":
			stats.mp -= NpcStats.FIREBALL_MP_COST
			enemy.stats.hp -= max(1, stats.fireball_power())
		"spark":
			stats.mp -= NpcStats.SPARK_MP_COST
			enemy.stats.hp -= max(1, stats.spark_power())
		_:
			if randf() < _player_hit_chance(enemy):
				enemy.stats.hp -= max(1, stats.attack_power() + randi() % 4 - enemy.stats.defense())

	if enemy.stats.hp <= 0:
		enemies.erase(next_cell)
		stats.gold += enemy.stats.gold
		var xp_gain: int = enemy.stats.xp
		enemy.defeat()
		if stats.add_xp(xp_gain):
			leveled_up.emit(self)
		is_moving = false
		_update_label()
		_move_to(next_cell)
		return

	if randf() < _enemy_hit_chance(enemy):
		var damage: int = max(1, enemy.stats.attack_power() + randi() % 3 - stats.defense())
		if randf() < ENEMY_CRIT_CHANCE:
			damage = int(ceil(damage * ENEMY_CRIT_MULTIPLIER))
		stats.hp -= damage

	if stats.hp <= 0:
		enemy.in_combat = false
		_die()
		return

	_run_combat_turn(next_cell, enemy)

## HP hitting 0 is final: the character dies, is hidden from the maze, and
## stops doing anything further. game_manager listens for `died` to drop it
## from the active roster and grey out its HUD panel.
func _die() -> void:
	dead = true
	stats.hp = 0
	current_action = "Defeated"
	visible = false
	died.emit(self)

func _retreat() -> void:
	var open_dirs := MazeQuery.open_neighbors(grid, cell_pos)
	var retreat_options: Array = []
	for c in open_dirs:
		if visited.has(c) and not _has_live_enemy(c):
			retreat_options.append(c)
	if retreat_options.is_empty():
		return
	_move_to(retreat_options[randi() % retreat_options.size()])

## BFS over cells reachable through open passages, looking for the nearest
## cell that still has an unvisited neighbor. Returns the first step along
## the way there, or cell_pos itself if nothing is left to discover.
func _step_toward_frontier() -> Vector2i:
	var queue: Array = [cell_pos]
	var came_from: Dictionary = {cell_pos: cell_pos}

	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		for n in MazeQuery.open_neighbors(grid, cur):
			if came_from.has(n):
				continue
			came_from[n] = cur
			if not visited.has(n):
				var step: Vector2i = n
				while came_from[step] != cell_pos:
					step = came_from[step]
				return step
			queue.append(n)

	return cell_pos

func _move_to(next_cell: Vector2i) -> void:
	is_moving = true
	var target_world := _cell_to_world(next_cell)
	var duration: float = move_seconds_base / max(stats.move_speed(), 0.1)
	var tween := create_tween()
	tween.tween_property(self, "position", target_world, duration)
	tween.finished.connect(_on_move_finished.bind(next_cell))

func _on_move_finished(next_cell: Vector2i) -> void:
	cell_pos = next_cell
	is_moving = false
	_on_enter_cell()

func _on_enter_cell() -> void:
	visited[cell_pos] = true
	_check_for_chest()
	if cell_pos == exit_cell and not finished:
		finished = true
		reached_exit.emit(self)
	_update_label()
	if finished:
		current_action = "Finished the maze!"
	if shops.has(cell_pos) and stats.has_shop_business():
		_start_shopping()

## Picks up any equipment sitting on our current cell. First come, first
## served — the chest is removed from the shared map the moment it's
## collected, so nobody else can also grab it. Only the first copy of a given
## item takes effect; a duplicate is kept as a spare to sell.
func _check_for_chest() -> void:
	if not chests.has(cell_pos):
		return
	var chest: ChestAgent = chests[cell_pos]
	chests.erase(cell_pos)
	if chest == null or not is_instance_valid(chest):
		return
	var item_name: String = chest.collect()
	var worn := stats.acquire_item(item_name)
	name_label.text = "%s found %s%s!" % [npc_name, item_name, "" if worn else " (spare)"]
	var timer := get_tree().create_timer(1.5)
	timer.timeout.connect(_update_label)

func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)

func _update_label() -> void:
	name_label.text = "%s Lv.%d" % [npc_name, stats.level]
	current_action = "Exploring"
