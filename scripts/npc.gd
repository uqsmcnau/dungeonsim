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
## Every living player, by current cell — shared across all NPCs, the same
## way `enemies` is, so each can see where the others are. Only ever holds
## PARTY LEADERS; a party's followers are found via `party`, not this dict.
var players: Dictionary = {}
## True while locked in a fight against another player. Unlike `is_moving`,
## this also has to freeze the OTHER side's own _process, since a PvP fight
## is driven entirely from one side's turn loop (see _run_group_pvp_turn).
var in_pvp_combat: bool = false
## Start zones, shop zones, mini boss rooms and the boss room — no PvP may
## be started on any of these cells, on top of the existing rule that no
## monsters ever spawn there.
var safe_cells: Dictionary = {}
## Every shop in the world, and the ones this character has actually laid
## eyes on (it only makes trips to shops it knows about).
var shops: Dictionary = {}
var known_shops: Dictionary = {}
var is_moving: bool = false
var finished: bool = false
var dead: bool = false
## What this character is doing right now, in plain words, for the HUD.
var current_action: String = "Exploring"
## Party of up to PartyOps.MAX_PARTY_SIZE characters (including self),
## sharing the same array once merged — mirroring how `pack` works for enemy groups.
## Only the leader (is_party_leader) runs its own idle AI, decides whether to
## fight or form a party, and picks where to explore; followers just tag
## along (see _follow_to) and fight alongside whenever the leader does.
var party: Array = []
var is_party_leader: bool = true
var party_offset: Vector2 = Vector2.ZERO

@onready var visual: Polygon2D = $Visual
@onready var name_label: Label = $NameLabel

func setup(spawn_cell: Vector2i, target_cell: Vector2i, maze_grid: Array, cs: float, color: Color, display_name: String, enemy_map: Dictionary, chest_map: Dictionary, shop_map: Dictionary, player_map: Dictionary, restricted_cells: Dictionary = {}) -> void:
	cell_pos = spawn_cell
	exit_cell = target_cell
	grid = maze_grid
	cell_size = cs
	npc_name = display_name
	enemies = enemy_map
	chests = chest_map
	shops = shop_map
	players = player_map
	safe_cells = restricted_cells
	party = [self]
	stats = NpcStats.new()
	stats.roll_ability_scores()
	stats.alignment = NpcStats.random_alignment()
	visited[cell_pos] = true
	visual.color = color
	position = _cell_to_world(cell_pos)
	players[cell_pos] = self
	_update_label()
	_check_for_chest()

func _process(delta: float) -> void:
	if dead:
		return
	stats.regen_mp(delta)
	## Followers don't act independently at all — they just tag along with
	## the leader (movement) and fight alongside it (combat), both driven
	## entirely from the leader's own logic.
	if not is_party_leader:
		return
	if finished or is_moving or in_pvp_combat:
		return
	## Safety net: if a live enemy is ever standing on our own cell (e.g. one
	## wandered into our destination while we were mid-transit), resolve that
	## before doing anything else, so an enemy can never be walked past.
	if _has_live_enemy(cell_pos):
		var enemy: EnemyAgent = enemies[cell_pos]
		if enemy.in_combat:
			return
		if CombatMath.decide_fight(stats, enemy.stats):
			_engage(cell_pos, enemy)
			return
		_retreat()
		if is_moving:
			return
	## Same safety net for another player ending up on our cell. Whether we
	## throw the first punch is up to alignment (see _decide_pvp_fight) —
	## unless we're in a safe room (a start zone, shop, mini boss room or the
	## boss room), where PvP can never be started at all. If not fighting,
	## we consider teaming up instead, and failing that just step away.
	if _has_live_player(cell_pos):
		var opponent: NpcAgent = players[cell_pos]
		if not opponent.in_pvp_combat:
			if not safe_cells.has(cell_pos) and _decide_pvp_fight(opponent):
				_engage_player(cell_pos, opponent)
				return
			if PartyOps.can_form_party_with(self, opponent):
				PartyOps.join_party_of(opponent, self)
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

func _has_live_player(cell: Vector2i) -> bool:
	if not players.has(cell):
		return false
	var other = players[cell]
	return other != null and is_instance_valid(other) and not other.dead and other != self

## If the destination holds a live enemy, decide whether to fight (a battle
## fought in 1-second turns) or flee (retreat toward already-explored ground
## instead). A live enemy always blocks the cell until it's defeated. If
## another NPC is already fighting it, wait it out. The same goes for another
## player standing there, except whether to fight is governed by alignment
## rather than combat odds alone (see _decide_pvp_fight), and never allowed
## at all in a safe room — and if neither side wants to fight, they may band
## together into one party instead.
func _attempt_move(next_cell: Vector2i) -> void:
	if _has_live_enemy(next_cell):
		var enemy: EnemyAgent = enemies[next_cell]
		if enemy.in_combat:
			_retreat()
		elif CombatMath.decide_fight(stats, enemy.stats):
			_engage(next_cell, enemy)
		else:
			_retreat()
		return
	if _has_live_player(next_cell):
		var opponent: NpcAgent = players[next_cell]
		if opponent.in_pvp_combat:
			_retreat()
		elif not safe_cells.has(next_cell) and _decide_pvp_fight(opponent):
			_engage_player(next_cell, opponent)
		elif PartyOps.can_form_party_with(self, opponent):
			PartyOps.join_party_of(self, opponent)
		else:
			_retreat()
		return
	_move_to(next_cell)

## Whether to throw the first punch at another player — governed by
## alignment, not just the odds: Evil attacks anyone it thinks it can beat,
## Good only attacks an Evil opponent it thinks it can beat, and Neutral
## never starts one. Once a fight is actually underway (_run_group_pvp_turn)
## alignment no longer matters — everyone defends themselves regardless.
func _decide_pvp_fight(opponent: NpcAgent) -> bool:
	match stats.alignment:
		NpcStats.ALIGNMENT_EVIL:
			pass
		NpcStats.ALIGNMENT_GOOD:
			if opponent.stats.alignment != NpcStats.ALIGNMENT_EVIL:
				return false
		_:
			return false
	return CombatMath.win_chance_against(stats, opponent.stats) > 0.5

## The living member of `combatants` (an Array of anything exposing `.stats`)
## with the lowest current HP — used so a group fight naturally focuses fire
## on whoever's closest to falling.
func _weakest(combatants: Array):
	var weakest = null
	var weakest_hp := 1 << 30
	for c in combatants:
		if c.stats.hp < weakest_hp:
			weakest = c
			weakest_hp = c.stats.hp
	return weakest

## Every living member of this character's party, including itself.
func living_party() -> Array:
	var result: Array = []
	for member in party:
		if is_instance_valid(member) and not member.dead:
			result.append(member)
	return result

## Starts a fight between this character's whole party and an enemy pack —
## every living member on both sides joins in, each fighting with their own
## tactics each turn (see _resolve_group_combat_turn).
func _engage(next_cell: Vector2i, enemy: EnemyAgent) -> void:
	is_moving = true
	for pack_member in enemy.living_pack():
		pack_member.in_combat = true
	_run_group_combat_turn(cell_pos, next_cell)

## Survival first (Recover, or a Health Potion if it can't afford that), then
## whichever of its attack spells or a plain attack actually deals the most
## damage right now. A spell's damage is fixed by intelligence while a plain
## attack scales with strength, level and weapon bonuses, so a spell that
## out-damages a fresh character is often no longer the better choice once
## they've leveled up or found a sword — this compares them fresh each turn
## rather than always preferring magic once it's known.
func _choose_combat_action(opponent_stats: NpcStats) -> String:
	if stats.hp < int(stats.max_hp * IN_COMBAT_HEAL_THRESHOLD):
		if stats.mp >= RECOVER_MP_COST:
			return "recover"
		if stats.has_item("Health Potion"):
			return "potion_hp"

	var best_action := "attack"
	var best_damage: float = CombatMath.expected_damage_dealt(stats, opponent_stats)
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

## Applies one chosen combat action (a plain attack, a spell, a potion, or
## Recover) against an opponent's stat block. Shared between a monster fight
## and a player-vs-player one — only what each side does with it differs.
func _apply_combat_action(action: String, opponent_stats: NpcStats) -> void:
	match action:
		"recover":
			stats.mp -= RECOVER_MP_COST
			stats.hp = min(stats.max_hp, stats.hp + stats.recover_power())
		"potion_hp":
			_apply_consumable_effect("Health Potion")
		"fireball":
			stats.mp -= NpcStats.FIREBALL_MP_COST
			opponent_stats.hp -= max(1, stats.fireball_power())
		"spark":
			stats.mp -= NpcStats.SPARK_MP_COST
			opponent_stats.hp -= max(1, stats.spark_power())
		_:
			if randf() < CombatMath.hit_chance_against(stats, opponent_stats):
				opponent_stats.hp -= max(1, stats.attack_power() + randi() % 4 - opponent_stats.defense())

## One turn of a party-vs-pack fight. `my_cell`/`enemy_cell` are the fixed
## cells the two sides are anchored at for the whole fight; who specifically
## is "driving" it (picked fresh each turn via the shared `players`/`enemies`
## maps) can change mid-fight if whoever was driving falls and others on
## their side survive — those maps are always kept pointing at a living
## representative (see _die() and EnemyAgent.defeat()), so this never gets
## stuck on a stale reference.
func _run_group_combat_turn(my_cell: Vector2i, enemy_cell: Vector2i) -> void:
	var me: NpcAgent = players.get(my_cell)
	if me == null:
		return
	var enemy: EnemyAgent = enemies.get(enemy_cell)
	var foes: Array = enemy.living_pack() if enemy != null and is_instance_valid(enemy) else []
	if foes.is_empty():
		me._conclude_group_combat(enemy_cell)
		return
	if me.living_party().is_empty():
		return

	var target: EnemyAgent = me._weakest(foes)
	if me.stats.hp <= CombatMath.damage_taken_per_hit(me.stats, target.stats) * FLEE_DANGER_TURNS:
		me._disengage_group_combat(enemy_cell)
		return

	me.current_action = "Fighting a level %d enemy" % target.stats.level
	me.name_label.text = "%s ⚔ Lv.%d" % [me.npc_name, target.stats.level]
	var timer := me.get_tree().create_timer(TURN_SECONDS)
	timer.timeout.connect(_resolve_group_combat_turn.bind(my_cell, enemy_cell))

func _resolve_group_combat_turn(my_cell: Vector2i, enemy_cell: Vector2i) -> void:
	var me: NpcAgent = players.get(my_cell)
	if me == null:
		return
	var enemy: EnemyAgent = enemies.get(enemy_cell)
	if enemy == null or not is_instance_valid(enemy):
		me._conclude_group_combat(enemy_cell)
		return

	var foes: Array = enemy.living_pack()
	for ally in me.living_party():
		if foes.is_empty():
			break
		var target: EnemyAgent = me._weakest(foes)
		var action: String = ally._choose_combat_action(target.stats)
		ally._apply_combat_action(action, target.stats)
		if target.stats.hp <= 0:
			foes.erase(target)
			ally.stats.gold += target.stats.gold
			if ally.stats.add_xp(target.stats.xp):
				ally.leveled_up.emit(ally)
			target.defeat()

	if foes.is_empty():
		me._conclude_group_combat(enemy_cell)
		return

	for foe in foes:
		var allies: Array = me.living_party()
		if allies.is_empty():
			break
		var victim: NpcAgent = allies[randi() % allies.size()]
		if randf() < CombatMath.hit_chance_against(foe.stats, victim.stats):
			var damage: int = max(1, foe.stats.attack_power() + randi() % 3 - victim.stats.defense())
			if randf() < ENEMY_CRIT_CHANCE:
				damage = int(ceil(damage * ENEMY_CRIT_MULTIPLIER))
			victim.stats.hp -= damage
			if victim.stats.hp <= 0:
				victim._die()

	if me.living_party().is_empty():
		enemy.in_combat = false
		return

	var next_driver: NpcAgent = players.get(my_cell)
	if next_driver == null:
		enemy.in_combat = false
		return
	next_driver._run_group_combat_turn(my_cell, enemy_cell)

## Ends a party-vs-pack fight once the pack is wiped out: moves the
## surviving party onto the now-empty cell.
func _conclude_group_combat(enemy_cell: Vector2i) -> void:
	is_moving = false
	_update_label()
	_move_to(enemy_cell)

## Breaks off a fight that's turning dangerous for the character driving it.
## Damage already dealt stays on the pack, so the party can retreat, recover,
## and come back to finish it.
func _disengage_group_combat(enemy_cell: Vector2i) -> void:
	var enemy: EnemyAgent = enemies.get(enemy_cell)
	if enemy != null and is_instance_valid(enemy):
		enemy.in_combat = false
	is_moving = false
	_update_label()
	_retreat()

## Starts a player-vs-player fight between this character's whole party and
## another leader's whole party — every living member on both sides joins
## in, each fighting with their own tactics each turn (see
## _resolve_group_pvp_turn).
func _engage_player(next_cell: Vector2i, opponent: NpcAgent) -> void:
	is_moving = true
	for member in living_party():
		member.in_pvp_combat = true
	for member in opponent.living_party():
		member.in_pvp_combat = true
	_run_group_pvp_turn(party, opponent.party, cell_pos, next_cell)

## Whoever in `party_ref` is currently the registered leader (re-checked
## fresh each call, since a fallen driver is replaced by a promoted
## party-mate — see _die()). Falls back to any living member defensively,
## though _die()'s promotion should mean that's never actually needed.
func _current_party_leader(party_ref: Array) -> NpcAgent:
	for member in party_ref:
		if is_instance_valid(member) and not member.dead and member.is_party_leader:
			return member
	for member in party_ref:
		if is_instance_valid(member) and not member.dead:
			return member
	return null

## One turn of a party-vs-party fight. `my_party`/`their_party` are the two
## sides' shared party arrays — a stable identity even when (as when this
## fight was triggered by one side finding the other already on its own
## cell) both sides occupy the exact same cell, which a cell-keyed lookup
## couldn't tell apart. `my_cell`/`their_cell` are only kept around for the
## final move onto the loser's position once the fight ends.
func _run_group_pvp_turn(my_party: Array, their_party: Array, my_cell: Vector2i, their_cell: Vector2i) -> void:
	var me: NpcAgent = _current_party_leader(my_party)
	var them: NpcAgent = _current_party_leader(their_party)
	if me == null or them == null:
		_release_pvp_locks(my_party, their_party)
		return
	var foes: Array = them.living_party()
	var allies: Array = me.living_party()
	if foes.is_empty() or allies.is_empty():
		_conclude_group_pvp(my_party, their_party, my_cell, their_cell)
		return

	var my_target: NpcAgent = me._weakest(foes)
	if me.stats.hp <= CombatMath.damage_taken_per_hit(me.stats, my_target.stats) * FLEE_DANGER_TURNS:
		me._disengage_group_pvp(my_party, their_party)
		return
	var their_target: NpcAgent = them._weakest(allies)
	if them.stats.hp <= CombatMath.damage_taken_per_hit(them.stats, their_target.stats) * FLEE_DANGER_TURNS:
		them._disengage_group_pvp(their_party, my_party)
		return

	me.current_action = "Fighting %s" % them.npc_name
	me.name_label.text = "%s ⚔ vs %s" % [me.npc_name, them.npc_name]
	them.current_action = "Fighting %s" % me.npc_name
	them.name_label.text = "%s ⚔ vs %s" % [them.npc_name, me.npc_name]

	var timer := me.get_tree().create_timer(TURN_SECONDS)
	timer.timeout.connect(_resolve_group_pvp_turn.bind(my_party, their_party, my_cell, their_cell))

func _resolve_group_pvp_turn(my_party: Array, their_party: Array, my_cell: Vector2i, their_cell: Vector2i) -> void:
	var me: NpcAgent = _current_party_leader(my_party)
	var them: NpcAgent = _current_party_leader(their_party)
	if me == null or them == null:
		_release_pvp_locks(my_party, their_party)
		return

	var foes: Array = them.living_party()
	for ally in me.living_party():
		if foes.is_empty():
			break
		var target: NpcAgent = me._weakest(foes)
		var action: String = ally._choose_combat_action(target.stats)
		ally._apply_combat_action(action, target.stats)
		if target.stats.hp <= 0:
			foes.erase(target)
			target._die()

	var allies: Array = me.living_party()
	if foes.is_empty() or allies.is_empty():
		_conclude_group_pvp(my_party, their_party, my_cell, their_cell)
		return

	for foe in foes:
		allies = me.living_party()
		if allies.is_empty():
			break
		var target: NpcAgent = foe._weakest(allies)
		var action: String = foe._choose_combat_action(target.stats)
		foe._apply_combat_action(action, target.stats)
		if target.stats.hp <= 0:
			target._die()

	if me.living_party().is_empty() or them.living_party().is_empty():
		_conclude_group_pvp(my_party, their_party, my_cell, their_cell)
		return

	var next_driver: NpcAgent = _current_party_leader(my_party)
	if next_driver == null:
		_release_pvp_locks(my_party, their_party)
		return
	next_driver._run_group_pvp_turn(my_party, their_party, my_cell, their_cell)

## Ends a party-vs-party fight once one side (or both) has no one left
## standing: releases both sides' combat locks, and if exactly one side
## still has survivors, moves them onto the other's cell to claim it (and
## any death-chest loot left behind) — a no-op move if the two were already
## sharing the same cell.
func _conclude_group_pvp(my_party: Array, their_party: Array, my_cell: Vector2i, their_cell: Vector2i) -> void:
	_release_pvp_locks(my_party, their_party)
	var my_side: NpcAgent = _current_party_leader(my_party)
	var their_side: NpcAgent = _current_party_leader(their_party)
	if my_side != null and their_side == null:
		my_side.is_moving = false
		my_side._update_label()
		my_side._move_to(their_cell)
	elif their_side != null and my_side == null:
		their_side.is_moving = false
		their_side._update_label()
		their_side._move_to(my_cell)

func _release_pvp_locks(party_a: Array, party_b: Array) -> void:
	for party_ref in [party_a, party_b]:
		for member in party_ref:
			if is_instance_valid(member):
				member.in_pvp_combat = false

## Breaks off a player-vs-player fight that's turning dangerous for the
## character driving this side of it — both sides are freed to resume their
## own AI, and this side's party retreats together.
func _disengage_group_pvp(my_party: Array, their_party: Array) -> void:
	_release_pvp_locks(my_party, their_party)
	is_moving = false
	_update_label()
	_retreat()

## HP hitting 0 is final: the character dies, is hidden from the maze, and
## stops doing anything further. game_manager listens for `died` to drop it
## from the active roster and grey out its HUD panel. If this was the party
## leader and others survive, one of them is promoted so the party keeps
## acting rather than freezing with no one driving it.
##
## Clears in_pvp_combat on itself rather than leaving that to whatever
## called _die() (e.g. _release_pvp_locks, which walks the party array to
## find everyone to unlock) — party.erase(self) just below mutates that same
## shared array in place, so a cleanup pass running afterward would no
## longer find this character in it at all.
func _die() -> void:
	dead = true
	stats.hp = 0
	current_action = "Defeated"
	visible = false
	in_pvp_combat = false
	players.erase(cell_pos)
	party.erase(self)
	if is_party_leader and not party.is_empty():
		PartyOps.promote_next_leader(self)
	died.emit(self)

func _retreat() -> void:
	var open_dirs := MazeQuery.open_neighbors(grid, cell_pos)
	var retreat_options: Array = []
	for c in open_dirs:
		if visited.has(c) and not _has_live_enemy(c) and not _has_live_player(c):
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
	for member in party:
		if member != self and is_instance_valid(member) and not member.dead:
			member._follow_to(next_cell, duration)

## Every step the leader takes, each follower tags along to the same cell,
## offset slightly so the whole party stays visible as distinct members.
func _follow_to(next_cell: Vector2i, duration: float) -> void:
	cell_pos = next_cell
	var target_world: Vector2 = _cell_to_world(next_cell) + party_offset
	var tween := create_tween()
	tween.tween_property(self, "position", target_world, duration)
	tween.finished.connect(func(): visited[cell_pos] = true)

func _on_move_finished(next_cell: Vector2i) -> void:
	players.erase(cell_pos)
	cell_pos = next_cell
	is_moving = false
	_on_enter_cell()

func _on_enter_cell() -> void:
	visited[cell_pos] = true
	players[cell_pos] = self
	_check_for_chest()
	if cell_pos == exit_cell and not finished:
		finished = true
		for member in party:
			if is_instance_valid(member):
				member.finished = true
		reached_exit.emit(self)
	_update_label()
	if finished:
		current_action = "Finished the maze!"
	if shops.has(cell_pos) and stats.has_shop_business():
		_start_shopping()

## Picks up anything sitting on our current cell. First come, first served —
## the chest is removed from the shared map the moment it's collected, so
## nobody else can also grab it. Only the first copy of a given item takes
## effect; a duplicate is kept as a spare to sell. A death drop can hand over
## several items plus gold at once.
func _check_for_chest() -> void:
	if not chests.has(cell_pos):
		return
	var chest: ChestAgent = chests[cell_pos]
	chests.erase(cell_pos)
	if chest == null or not is_instance_valid(chest):
		return
	var result: Dictionary = chest.collect()
	var loot: Dictionary = result["loot"]
	var gold: int = int(result["gold"])
	var parts: Array = []
	for item_name in loot:
		var count: int = int(loot[item_name])
		for i in range(count):
			stats.acquire_item(item_name)
		parts.append("%s x%d" % [item_name, count] if count > 1 else item_name)
	stats.gold += gold
	if gold > 0:
		parts.append("%dg" % gold)
	if parts.is_empty():
		return
	name_label.text = "%s found %s!" % [npc_name, ", ".join(parts)]
	var timer := get_tree().create_timer(1.5)
	timer.timeout.connect(_update_label)

func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)

func _update_label() -> void:
	name_label.text = "%s Lv.%d" % [npc_name, stats.level]
	current_action = "Exploring"
