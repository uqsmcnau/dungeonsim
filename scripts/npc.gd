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
## How many of its own steps a character ignores a chest for after finding
## no monster-free route to it (see _chest_step) -- long enough to wander
## off and explore elsewhere, short enough to come back for it once the
## monster in the way has moved on.
const CHEST_SKIP_STEPS := 12
## How far a character will plan a route to another party it wants to team
## up with. They're within SIGHT_RANGE in a straight line, so this mostly
## leaves room for detours around monsters.
const PARTY_PATH_DEPTH := 18
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
## Chests set aside for now, by cell -> steps left to ignore them for.
var skipped_chests: Dictionary = {}
## Every living player, by current cell — shared across all NPCs, the same
## way `enemies` is, so each can see where the others are. Only ever holds
## PARTY LEADERS; a party's followers are found via `party`, not this dict.
var players: Dictionary = {}
## True while locked in a fight against another player. Unlike `is_moving`,
## this also has to freeze the OTHER side's own _process, since a PvP fight
## is driven entirely from one side's turn loop (see _run_group_pvp_turn).
var in_pvp_combat: bool = false
## Mid-fight against a monster pack (see _engage). The is_moving lock is what
## actually holds the party still; this records *why*, so a lock taken for
## some other reason (e.g. PartyOps.relocate_to_party's walk-in) knows not
## to release it when it finishes.
var in_pack_combat: bool = false
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
			_try_join_fight_against(enemy)
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
		if opponent.is_in_combat():
			# Never attacked mid-fight, but they can be joined -- and it's
			# us who joins them, since their fight can't be interrupted.
			if PartyOps.can_form_party_with(self, opponent):
				PartyOps.join_party_of(self, opponent)
				return
		else:
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
	var timer := get_tree().create_timer(RECOVER_CAST_SECONDS, false)
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
	var timer := get_tree().create_timer(CONSUME_SECONDS, false)
	timer.timeout.connect(_finish_consume_idle.bind(item_name))

func _finish_consume_idle(item_name: String) -> void:
	_apply_consumable_effect(item_name)
	is_moving = false
	_update_label()

func _take_step() -> void:
	_notice_shops()

	# Priorities: teaming up with another party in sight that's up for it,
	# then a shop worth visiting, then a chest in sight, then exploring --
	# and none of these is worth picking a fight over, so an enemy in the
	# way means carrying on with the next option instead.
	var party_step := _party_up_step()
	if party_step != cell_pos:
		# Not _move_to: the step may well be onto the other party's cell,
		# and _attempt_move is what merges the two on arrival.
		_attempt_move(party_step)
		return

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

## Next step toward the nearest other party leader in line of sight that
## this party wants to team up with (see _wants_to_party_with), routed
## around monsters -- or our own cell if there's no one. Both sides run
## this, so two parties that spot each other close the gap from both ends;
## one stuck in a fight can't move, so the other comes to it.
func _party_up_step() -> Vector2i:
	var candidates: Dictionary = {}
	for c in players:
		if _wants_to_party_with(players[c]):
			candidates[c] = true
	if candidates.is_empty():
		return cell_pos
	var target := MazeQuery.nearest_visible(grid, cell_pos, SIGHT_RANGE, candidates)
	if target == MazeQuery.NONE:
		return cell_pos
	var step := MazeQuery.step_toward(grid, cell_pos, target, PARTY_PATH_DEPTH, _live_enemy_cells())
	if step != cell_pos:
		current_action = "Heading to join %s" % players[target].npc_name
	return step

## Whether this party and `other`'s would both rather band together than
## not: the usual merge rules allow it (PartyOps.can_form_party_with), and
## neither side would throw the first punch on contact -- otherwise walking
## over "to team up" would really be walking into a fight. Someone already
## mid-fight can't be attacked (see _attempt_move), so for them only the
## merge rules matter.
func _wants_to_party_with(other) -> bool:
	if other == null or not is_instance_valid(other) or other == self:
		return false
	if other.dead or other.finished or other.party == party:
		return false
	if not PartyOps.can_form_party_with(self, other):
		return false
	if other.is_in_combat():
		return true
	return not _decide_pvp_fight(other) and not other._decide_pvp_fight(self)

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
	var timer := get_tree().create_timer(SHOPPING_SECONDS, false)
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
		var timer := get_tree().create_timer(1.5, false)
		timer.timeout.connect(_update_label)
	else:
		_update_label()

## Next step toward a chest, or our own cell if there's none to go for. Once
## a chest has been spotted it stays the goal (even if the route around a
## corner briefly loses sight of it) until it's taken by someone or turns out
## to be unreachable.
##
## Routes around monsters, since a chest isn't worth picking a fight over.
## If there's no way there that avoids them, the chest is set aside for
## CHEST_SKIP_STEPS steps. Simply dropping the goal isn't enough: the chest
## would be re-spotted on the very next step, so the character would bounce
## forever between stepping toward it and backing off from the monster in
## the way.
func _chest_step() -> Vector2i:
	_tick_skipped_chests()
	if chest_goal != MazeQuery.NONE and not chests.has(chest_goal):
		chest_goal = MazeQuery.NONE
	if chest_goal == MazeQuery.NONE:
		chest_goal = MazeQuery.nearest_visible(grid, cell_pos, SIGHT_RANGE, _chests_worth_trying())
	if chest_goal == MazeQuery.NONE:
		return cell_pos
	var step := MazeQuery.step_toward(grid, cell_pos, chest_goal, CHEST_PATH_DEPTH, _live_enemy_cells())
	if step == cell_pos:
		skipped_chests[chest_goal] = CHEST_SKIP_STEPS
		chest_goal = MazeQuery.NONE
	return step

func _tick_skipped_chests() -> void:
	for c in skipped_chests.keys():
		skipped_chests[c] -= 1
		if skipped_chests[c] <= 0:
			skipped_chests.erase(c)

func _chests_worth_trying() -> Dictionary:
	if skipped_chests.is_empty():
		return chests
	var result: Dictionary = {}
	for c in chests:
		if not skipped_chests.has(c):
			result[c] = chests[c]
	return result

func _live_enemy_cells() -> Dictionary:
	var result: Dictionary = {}
	for c in enemies:
		if _has_live_enemy(c):
			result[c] = true
	return result

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
## another party is already fighting it, join them if the two parties could
## team up (see _try_join_fight_against), or back off if not. The same goes for another
## player standing there, except whether to fight is governed by alignment
## rather than combat odds alone (see _decide_pvp_fight), and never allowed
## at all in a safe room — and if neither side wants to fight, they may band
## together into one party instead. A player already mid-fight (with
## monsters or other players) is never attacked, but can still be joined:
## this party merges into theirs and fights alongside them from the next
## turn on, without their fight being interrupted.
func _attempt_move(next_cell: Vector2i) -> void:
	if _has_live_enemy(next_cell):
		var enemy: EnemyAgent = enemies[next_cell]
		if enemy.in_combat:
			if not _try_join_fight_against(enemy):
				_retreat()
		elif CombatMath.decide_fight(stats, enemy.stats):
			_engage(next_cell, enemy)
		else:
			_retreat()
		return
	if _has_live_player(next_cell):
		var opponent: NpcAgent = players[next_cell]
		if opponent.is_in_combat():
			if PartyOps.can_form_party_with(self, opponent):
				PartyOps.join_party_of(self, opponent)
			else:
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

func is_in_combat() -> bool:
	return in_pvp_combat or in_pack_combat

## Approached from the monster side of someone else's fight: finds whoever's
## currently leading the party fighting `enemy` and, if the two parties could
## team up, joins them -- moving over to stand with them on their side
## (see PartyOps.relocate_to_party) rather than wading in onto the
## monster's cell. Returns whether it joined.
func _try_join_fight_against(enemy: EnemyAgent) -> bool:
	var fighter: NpcAgent = _current_party_leader(enemy.fighting_party)
	if fighter == null or fighter == self or not fighter.in_pack_combat:
		return false
	if not PartyOps.can_form_party_with(self, fighter):
		return false
	PartyOps.join_party_of(self, fighter)
	return true

## Every living member of this character's party, including itself.
func living_party() -> Array:
	var result: Array = []
	for member in party:
		if is_instance_valid(member) and not member.dead:
			result.append(member)
	return result

## Starts a fight between this character's whole party and an enemy pack —
## every living member on both sides joins in, each fighting with their own
## tactics each turn (see _resolve_group_combat_turn). Every party member
## (not just whoever's driving right now) gets is_moving locked for the
## whole fight, the same way _engage_player locks in_pvp_combat on everyone
## upfront -- otherwise a follower promoted to leader mid-fight (see _die())
## would still have is_moving false and could wander off exploring on its
## own while the fight it's now supposedly driving is still going.
func _engage(next_cell: Vector2i, enemy: EnemyAgent) -> void:
	for ally in living_party():
		ally.is_moving = true
		ally.in_pack_combat = true
	for pack_member in enemy.living_pack():
		pack_member.in_combat = true
		pack_member.fighting_party = party
	_run_group_combat_turn(party, next_cell)

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

## One turn of a party-vs-pack fight. `my_party` is the party's shared
## array -- a stable identity for this side for the whole fight, the same
## way the PvP loop identifies its sides -- and `enemy_cell` is where the
## pack is anchored. Whoever's "driving" (the party's current leader, see
## _current_party_leader) can change mid-fight if they fall and others
## survive, and newcomers who join (see PartyOps.join_party_of) land in the
## same array, so they're picked up from the next turn on.
##
## This used to find the driver by looking up whoever was registered on the
## party's cell in `players`. Anything that knocked that registration out
## mid-fight (e.g. a dying follower erasing its leader's entry) ended the
## loop with the party still locked -- stuck in place for good.
func _run_group_combat_turn(my_party: Array, enemy_cell: Vector2i) -> void:
	var me: NpcAgent = _current_party_leader(my_party)
	if me == null:
		_release_group_combat_lock(enemy_cell)
		return
	var enemy: EnemyAgent = enemies.get(enemy_cell)
	var foes: Array = enemy.living_pack() if enemy != null and is_instance_valid(enemy) else []
	if foes.is_empty():
		me._conclude_group_combat(enemy_cell)
		return

	var target: EnemyAgent = me._weakest(foes)
	if me.stats.hp <= CombatMath.damage_taken_per_hit(me.stats, target.stats) * FLEE_DANGER_TURNS:
		me._disengage_group_combat(enemy_cell)
		return

	me.current_action = "Fighting a level %d enemy" % target.stats.level
	me.name_label.text = "%s ⚔ Lv.%d" % [me.npc_name, target.stats.level]
	var timer := me.get_tree().create_timer(TURN_SECONDS, false)
	timer.timeout.connect(_resolve_group_combat_turn.bind(my_party, enemy_cell))

func _resolve_group_combat_turn(my_party: Array, enemy_cell: Vector2i) -> void:
	var me: NpcAgent = _current_party_leader(my_party)
	if me == null:
		_release_group_combat_lock(enemy_cell)
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

	# If the whole party fell, release the pack via _release_group_combat_lock,
	# not `enemy.in_combat = false`: `enemy` is whoever led the pack at the
	# start of this turn, and if the party killed it above, a follower has
	# since taken over -- releasing the dead one would leave the survivor
	# locked in_combat (and frozen in place) forever.
	var next_driver: NpcAgent = _current_party_leader(my_party)
	if next_driver == null:
		_release_group_combat_lock(enemy_cell)
		return
	next_driver._run_group_combat_turn(my_party, enemy_cell)

## Releases the pack's in_combat flag when a party-vs-pack fight ends
## abruptly with no living representative left to drive it to a proper
## conclusion (e.g. the whole party died). Without this the pack would stay
## permanently marked as mid-fight, and nobody could ever engage -- or even
## walk past -- it again (see _process/_attempt_move, which both retreat
## from a cell whose enemy.in_combat is true rather than passing it). Looks
## the pack up fresh by cell so it always finds the current leader, and
## releases the whole pack (see EnemyAgent.end_combat).
func _release_group_combat_lock(enemy_cell: Vector2i) -> void:
	var enemy: EnemyAgent = enemies.get(enemy_cell)
	if enemy != null and is_instance_valid(enemy):
		enemy.end_combat()

## Ends a party-vs-pack fight once the pack is wiped out: frees every party
## member's is_moving lock (see _engage) and moves the surviving party onto
## the now-empty cell.
func _conclude_group_combat(enemy_cell: Vector2i) -> void:
	for member in party:
		if is_instance_valid(member):
			member.is_moving = false
			member.in_pack_combat = false
	_update_label()
	_move_to(enemy_cell)

## Breaks off a fight that's turning dangerous for the character driving it.
## Damage already dealt stays on the pack, so the party can retreat, recover,
## and come back to finish it. Frees every party member's is_moving lock
## (see _engage), not just the one calling this.
func _disengage_group_combat(enemy_cell: Vector2i) -> void:
	_release_group_combat_lock(enemy_cell)
	for member in party:
		if is_instance_valid(member):
			member.is_moving = false
			member.in_pack_combat = false
	_update_label()
	_retreat()

## Starts a player-vs-player fight between this character's whole party and
## another leader's whole party — every living member on both sides joins
## in, each fighting with their own tactics each turn (see
## _resolve_group_pvp_turn).
##
## in_pvp_combat on every member of both sides is the only lock needed --
## _process already refuses to act while it's set. This used to also set
## is_moving on the attacker, but only the attacker's own exit paths ever
## cleared that: when the *defender* fled (or its party vanished
## mid-fight), the attacker stayed locked forever, still "Fighting".
func _engage_player(next_cell: Vector2i, opponent: NpcAgent) -> void:
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

	var timer := me.get_tree().create_timer(TURN_SECONDS, false)
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

## Frees both sides from the fight, and clears the "Fighting X" status off
## everyone still standing -- otherwise a side that didn't drive the ending
## (e.g. the one left behind when the other flees) keeps showing it.
func _release_pvp_locks(party_a: Array, party_b: Array) -> void:
	for party_ref in [party_a, party_b]:
		for member in party_ref:
			if is_instance_valid(member):
				member.in_pvp_combat = false
				if not member.dead:
					member._update_label()

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
	in_pack_combat = false
	_unregister()
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

## Removes this character's own entry from `players` -- and only its own.
## Followers share their leader's cell, and two leaders can briefly share
## one too, so a blind `players.erase(cell_pos)` would wipe out whoever
## else is registered there (e.g. a follower dying used to erase its
## leader, leaving the party invisible to everyone and its fight loop
## unable to find it).
func _unregister() -> void:
	if players.get(cell_pos) == self:
		players.erase(cell_pos)

func _on_move_finished(next_cell: Vector2i) -> void:
	_unregister()
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
	var timer := get_tree().create_timer(1.5, false)
	timer.timeout.connect(_update_label)

func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)

func _update_label() -> void:
	name_label.text = "%s Lv.%d" % [npc_name, stats.level]
	current_action = "Exploring"
