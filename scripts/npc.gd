class_name NpcAgent
extends Node2D

const RECOVER_MP_COST := 5
const RECOVER_CAST_SECONDS := 1.0
const OUT_OF_COMBAT_HEAL_THRESHOLD := 0.9
const IN_COMBAT_HEAL_THRESHOLD := 0.5
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
## One blow, spell, heal or escape in a fight this character is part of
## (see GroupCombat._report for what's in `event`) -- what the battle
## window (BattleWindow) plays out.
signal combat_event(event: Dictionary)

@export var npc_name: String = "NPC"
@export var move_seconds_base: float = 0.35

var stats: NpcStats
var grid: Array = []
var cell_size: float = 48.0
var cell_pos: Vector2i = Vector2i.ZERO
var exit_cell: Vector2i = Vector2i.ZERO
var visited: Dictionary = {}
## This character's own map of the maze: every cell it has ever seen, plus
## everything its party members had seen when they teamed up (see
## PartyOps.pool_seen_cells) and whatever any of them has seen since. It's
## a copy per member, so it's kept after leaving a party or outliving it.
## Drives the Party Vision fog (see GameManager._sync_fog).
var seen_cells: Dictionary = {}
## The cells in view right now, from `_sight_cell` -- recomputed by
## look_around only when this character has moved to a new cell.
var sight_cells: Dictionary = {}
var _sight_cell: Vector2i = MazeQuery.NONE
## The icon's slide under way, if any (see slide_to).
var _slide: Tween = null
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
## is driven entirely from one side's turn loop (see GroupCombat.run_pvp_turn).
var in_pvp_combat: bool = false
## While in_pvp_combat: the other side's shared party array (see
## GroupCombat.engage_players), so who we're fighting can be looked up.
var pvp_foes: Array = []
## Mid-fight against a monster pack (see GroupCombat.engage_pack). The is_moving lock is what
## actually holds the party still; this records *why*, so something that
## frees is_moving for its own reasons (e.g. PartyOps.relocate_to_party when
## joining a party) knows to leave a fight's lock in place.
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
## The party's randomly generated name (see PartyNames), shared by every
## member. Empty until this character first ends up in a party of two or
## more; kept after the rest of the party falls, so a lone survivor who
## teams up with another loner later carries the old name on (see
## PartyOps._merged_party_name).
var party_name: String = ""
## Where the spectator's Guidance has sent this party (right-click, see
## guide_to), or NONE. Only the leader's counts: it's handed on if the
## leader falls (PartyOps.promote_next_leader), and dropped if this party
## merges into another (PartyOps.join_party_of) -- that one isn't ours to
## steer.
var guidance_target: Vector2i = MazeQuery.NONE
## Who or what killed this character, and how -- e.g. "Bram (Lv.4 Evil)"
## and "Fireball for 12 damage" -- recorded by whoever lands the killing
## blow (see die) for their HUD panel. Both "" while alive.
var killed_by: String = ""
var death_method: String = ""
var is_party_leader: bool = true
var party_offset: Vector2 = Vector2.ZERO

@onready var visual: Polygon2D = $Visual
@onready var name_label: Label = $NameLabel
## In a party, the one label left showing (the leader's -- see sync_label)
## sits this much higher, clear of the members' icons standing around it.
const PARTY_LABEL_LIFT := 10.0
var _label_base_y: float = 0.0
## How long a passing message (a find, a sale, a party growing) stays up
## before the label goes back to rest.
const LABEL_MESSAGE_SECONDS := 1.5
## Whether the label is showing something other than its resting text (see
## show_label), and for a passing message, the seconds until it goes back
## -- 0 means until something calls reset_label (e.g. a fight ending).
var _label_busy: bool = false
var _label_time_left: float = 0.0

func _ready() -> void:
	leveled_up.connect(_on_leveled_up)
	_label_base_y = name_label.position.y

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
	look_around()
	visual.color = color
	position = _cell_to_world(cell_pos)
	players[cell_pos] = self
	reset_label()
	_check_for_chest()

func _process(delta: float) -> void:
	if dead:
		return
	stats.regen_mp(delta)
	_tick_label(delta)
	## Followers don't act independently at all — they just tag along with
	## the leader (movement) and fight alongside it (combat), both driven
	## entirely from the leader's own logic.
	if not is_party_leader:
		return
	_reclaim_registration()
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
			GroupCombat.engage_pack(self, cell_pos, enemy)
			return
		retreat()
		if is_moving:
			return
	## Same safety net for another player ending up on our cell. Whether we
	## throw the first punch is up to alignment (see _decide_pvp_fight) —
	## unless we're in a safe room (a start zone, shop, mini boss room or the
	## boss room), where PvP can never be started at all. If not fighting,
	## we consider teaming up instead, and failing that they're just passing
	## through (see _squeeze_past) -- so we carry on as normal.
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
				GroupCombat.engage_players(self, cell_pos, opponent)
				return
			if PartyOps.can_form_party_with(self, opponent):
				PartyOps.join_party_of(opponent, self)
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
	show_label("%s ✨ Recover" % map_name())
	var timer := get_tree().create_timer(RECOVER_CAST_SECONDS, false)
	timer.timeout.connect(_finish_recover_idle)

func _finish_recover_idle() -> void:
	stats.mp -= RECOVER_MP_COST
	stats.hp = min(stats.max_hp, stats.hp + stats.recover_power())
	is_moving = false
	reset_label()

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
	show_label("%s %s %s" % [map_name(), verb, item_name])
	var timer := get_tree().create_timer(CONSUME_SECONDS, false)
	timer.timeout.connect(_finish_consume_idle.bind(item_name))

func _finish_consume_idle(item_name: String) -> void:
	_apply_consumable_effect(item_name)
	is_moving = false
	reset_label()

func _take_step() -> void:
	_notice_shops()

	# The spectator's Guidance trumps everything else this party might want to do
	# -- teaming up, shops, chests and exploring all wait until it arrives.
	if guidance_target != MazeQuery.NONE and _follow_guidance():
		return

	# Priorities: teaming up with another party in sight that's up for it,
	# then a shop worth visiting, then a chest in sight, then exploring --
	# and none of these is worth picking a fight over, so an enemy in the
	# way means carrying on with the next option instead.
	var party_step := _party_up_step()
	if party_step != cell_pos:
		# Not move_to: the step may well be onto the other party's cell,
		# and _attempt_move is what merges the two on arrival.
		_attempt_move(party_step)
		return

	var shop_step := _shop_step()
	if shop_step != cell_pos and not _has_live_enemy(shop_step):
		move_to(shop_step)
		return

	var chest_step := _chest_step()
	if chest_step != cell_pos and not _has_live_enemy(chest_step):
		move_to(chest_step)
		return

	var open_dirs := MazeQuery.open_neighbors(grid, cell_pos)
	if open_dirs.is_empty():
		return
	var candidate := _choose_candidate(open_dirs)
	if candidate == cell_pos:
		return
	_attempt_move(candidate)

## Guidance: sends this party to `cell` (the spectator's right-click, see
## GameManager._on_world_right_clicked for the cooldown), anywhere in the
## maze -- seen or not. They find their way there by A* (see
## _guidance_step). Returns false if there's nowhere to go: they're
## already there.
func guide_to(cell: Vector2i) -> bool:
	if dead or finished or cell == cell_pos:
		guidance_target = MazeQuery.NONE
		return false
	guidance_target = cell
	current_action = "Following guidance"
	return true

## Every cell anyone in this party has been to or seen -- a party pools
## what its members know (see seen_cells).
func _party_known_cells() -> Dictionary:
	var known: Dictionary = {}
	for member in living_party():
		known.merge(member.visited)
		known.merge(member.seen_cells)
	return known

## Takes the next step toward the Guidance target, returning whether it did
## anything (false once it's arrived, or the target's become unreachable,
## so this step falls through to the party's own AI).
##
## Routes around monsters and other parties where it can. If the only way is
## past one, the normal rules decide what happens on contact: a fight is
## fought and the Guidance picks back up afterwards; merging into their
## party hands control to them (join_party_of drops the Guidance). But if
## this party just backs off, the Guidance is abandoned -- retrying would
## only bounce back and forth in front of whoever's in the way.
func _follow_guidance() -> bool:
	if cell_pos == guidance_target:
		guidance_target = MazeQuery.NONE
		reset_label()
		return false
	var step := _guidance_step()
	if step == cell_pos:
		guidance_target = MazeQuery.NONE
		return false

	current_action = "Following guidance"
	var contested := _has_live_enemy(step) or _has_live_player(step)
	_attempt_move(step)
	if contested and is_party_leader and not is_in_combat():
		guidance_target = MazeQuery.NONE
		current_action = "Guidance blocked"
	return true

## The next cell toward the Guidance target, or our own cell if there's no
## way there: the first step of an A* search over the party's pooled map
## that treats passages nobody's seen as open (MazeQuery.explore_step),
## re-planned every step as more of the maze comes into view.
func _guidance_step() -> Vector2i:
	var known := _party_known_cells()
	var avoid := _live_enemy_cells()
	for c in players:
		if c != cell_pos and _has_live_player(c):
			avoid[c] = true
	var step := MazeQuery.explore_step(grid, cell_pos, guidance_target, known, avoid)
	if step == cell_pos:
		step = MazeQuery.explore_step(grid, cell_pos, guidance_target, known)
	return step

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
	if known_shops.is_empty() or not _party_has_shop_business():
		return cell_pos
	var nearest := MazeQuery.NONE
	var nearest_dist := 1 << 30
	for c in known_shops:
		var d: int = abs(c.x - cell_pos.x) + abs(c.y - cell_pos.y)
		if d < nearest_dist:
			nearest = c
			nearest_dist = d
	return MazeQuery.step_toward(grid, cell_pos, nearest, SHOP_PATH_DEPTH)

## Whether a shop visit would do anything for anyone in the party -- the
## whole party shops together (see _finish_shopping).
func _party_has_shop_business() -> bool:
	for member in living_party():
		if member.stats.has_shop_business():
			return true
	return false

## The whole party shops: spares go to party-mates who'd wear them first,
## then everyone sells what's left and buys what their own gold stretches to.
func _start_shopping() -> void:
	is_moving = true
	current_action = "Shopping"
	show_label("%s $ Shopping" % map_name())
	var timer := get_tree().create_timer(SHOPPING_SECONDS, false)
	timer.timeout.connect(_finish_shopping)

func _finish_shopping() -> void:
	if dead:
		return
	var members := _self_first_party()
	PartyOps.pass_spares_around(members)
	var sold := 0
	var bought := 0
	for member in members:
		sold += member.stats.sell_spares()
		bought += member.stats.buy_missing().size()
		bought += member.stats.buy_potions().size()
	is_moving = false
	if sold > 0 or bought > 0:
		show_label("%s sold %d, bought %d" % [map_name(), sold, bought], LABEL_MESSAGE_SECONDS)
	else:
		reset_label()

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
	return players.has(cell) and players[cell] != self and holds_cell(players[cell], cell)

## Whether `other` (an entry in `players`) really is a living party leader
## standing on `cell`. Anything else is a stale entry left behind -- which
## used to count as someone being there, so a party could get into a fight
## with someone on the far side of the maze, and the winner then walked
## straight across it to "claim" the loser's cell.
static func holds_cell(other, cell: Vector2i) -> bool:
	return other != null and is_instance_valid(other) and not other.dead and other.is_party_leader and other.cell_pos == cell

## If the destination holds a live enemy, decide whether to fight (a battle
## fought in 1-second turns) or flee (retreat toward already-explored ground
## instead). A live enemy always blocks the cell until it's defeated. If
## another party is already fighting it, join them if the two parties could
## team up (see _try_join_fight_against), or back off if not. The same goes for another
## player standing there, except whether to fight is governed by alignment
## rather than combat odds alone (see _decide_pvp_fight), and never allowed
## at all in a safe room — and if neither side wants to fight, they may band
## together into one party instead, and failing that this one simply
## squeezes past (see _squeeze_past). A player already mid-fight (with
## monsters or other players) is never attacked, but can still be joined:
## this party merges into theirs and fights alongside them from the next
## turn on, without their fight being interrupted -- and if it can't join,
## it backs off rather than wading into someone else's fight.
func _attempt_move(next_cell: Vector2i) -> void:
	if _has_live_enemy(next_cell):
		var enemy: EnemyAgent = enemies[next_cell]
		if enemy.in_combat:
			if not _try_join_fight_against(enemy):
				retreat()
		elif CombatMath.decide_fight(stats, enemy.stats):
			GroupCombat.engage_pack(self, next_cell, enemy)
		else:
			retreat()
		return
	if _has_live_player(next_cell):
		var opponent: NpcAgent = players[next_cell]
		if opponent.is_in_combat():
			if PartyOps.can_form_party_with(self, opponent):
				PartyOps.join_party_of(self, opponent)
			else:
				retreat()
		elif not safe_cells.has(next_cell) and _decide_pvp_fight(opponent):
			GroupCombat.engage_players(self, next_cell, opponent)
		elif PartyOps.can_form_party_with(self, opponent):
			PartyOps.join_party_of(self, opponent)
		else:
			_squeeze_past(opponent, next_cell)
		return
	move_to(next_cell)

## Walks on through `opponent`'s cell when the two won't fight and can't team
## up -- for a moment the two share it, as two parties can. Backing off
## instead used to leave two such players stuck for good wherever one's way
## on lay past the other: each refusing the other, retreating, then coming
## straight back (or freezing outright with nowhere left to back off to).
## Passing through takes over the cell's spot in `players` (see
## _reclaim_registration for the one being passed).
func _squeeze_past(opponent: NpcAgent, next_cell: Vector2i) -> void:
	current_action = "Passing %s" % opponent.map_name()
	move_to(next_cell)

## Whether to throw the first punch at another player — governed by
## alignment, not just the odds: Evil attacks anyone it thinks it can beat,
## Good only attacks an Evil opponent it thinks it can beat, and Neutral
## never starts one. Once a fight is actually underway (GroupCombat.run_pvp_turn)
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
func weakest_of(combatants: Array):
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
	var fighter: NpcAgent = PartyOps.leader_of(enemy.fighting_party)
	if fighter == null or fighter == self or not fighter.in_pack_combat:
		return false
	if not PartyOps.can_form_party_with(self, fighter):
		return false
	PartyOps.join_party_of(self, fighter)
	return true

## Splits `amount` xp evenly across this character's living party (see
## _split_evenly) -- called on whoever landed the killing blow.
func share_xp_with_party(amount: int) -> void:
	var split := _split_evenly(amount)
	for member in split:
		if member.stats.add_xp(split[member]):
			member.leveled_up.emit(member)

## Splits `amount` gold evenly across this character's living party (see
## _split_evenly) -- called on whoever landed the killing blow or opened
## the chest.
func share_gold_with_party(amount: int) -> void:
	var split := _split_evenly(amount)
	for member in split:
		member.stats.gold += split[member]

## How to divide `amount` evenly across this character's living party (just
## itself, if it's on its own), as {member: share}. When it doesn't divide
## evenly, the leftover points go one each to the first members, starting
## with this character, so none is lost to rounding. Members whose share
## comes to nothing are left out.
func _split_evenly(amount: int) -> Dictionary:
	var members := _self_first_party()
	@warning_ignore("integer_division")
	var share: int = amount / members.size()
	var remainder: int = amount % members.size()
	var split: Dictionary = {}
	for i in range(members.size()):
		var gain: int = share + (1 if i < remainder else 0)
		if gain > 0:
			split[members[i]] = gain
	return split

## This character's living party with itself first -- the order shares are
## handed out in, so ties and leftovers favour whoever did the deed.
func _self_first_party() -> Array:
	var members: Array = living_party()
	members.erase(self)
	members.push_front(self)
	return members

## Takes an item handed over from a chest or a party-mate (see
## PartyOps.best_recipient). Followers never get idle moments of their own
## -- only the leader's AI runs -- so a follower given a spell tome it can
## use reads it on the spot, rather than carrying it around unread forever.
func receive_item(item_name: String) -> void:
	stats.acquire_item(item_name)
	var item := ItemCatalog.find(item_name)
	if not is_party_leader and item.get("effect") == "learn_spell" and not stats.knows_spell(item["spell"]):
		_apply_consumable_effect(item_name)

## Every living member of this character's party, including itself.
func living_party() -> Array:
	var result: Array = []
	for member in party:
		if is_instance_valid(member) and not member.dead:
			result.append(member)
	return result

## Survival first (Recover, or a Health Potion if it can't afford that), then
## whichever of its attack spells or a plain attack actually deals the most
## damage right now. A spell's damage is fixed by intelligence while a plain
## attack scales with strength, level and weapon bonuses, so a spell that
## out-damages a fresh character is often no longer the better choice once
## they've leveled up or found a sword — this compares them fresh each turn
## rather than always preferring magic once it's known.
func choose_combat_action(opponent_stats: NpcStats) -> String:
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
## Returns what happened, for the battle window: {"amount": the damage dealt
## or HP healed, "missed": whether a plain attack missed}.
func apply_combat_action(action: String, opponent_stats: NpcStats) -> Dictionary:
	var hp_before: int = stats.hp
	var damage := 0
	match action:
		"recover":
			stats.mp -= RECOVER_MP_COST
			stats.hp = min(stats.max_hp, stats.hp + stats.recover_power())
		"potion_hp":
			_apply_consumable_effect("Health Potion")
		"fireball":
			stats.mp -= NpcStats.FIREBALL_MP_COST
			damage = max(1, stats.fireball_power())
		"spark":
			stats.mp -= NpcStats.SPARK_MP_COST
			damage = max(1, stats.spark_power())
		_:
			if randf() >= CombatMath.hit_chance_against(stats, opponent_stats):
				return {"amount": 0, "missed": true}
			damage = max(1, stats.attack_power() + randi() % 4 - opponent_stats.defense())
	if action == "recover" or action == "potion_hp":
		return {"amount": stats.hp - hp_before, "missed": false}
	opponent_stats.hp -= damage
	return {"amount": damage, "missed": false}

## HP hitting 0 is final: the character dies, is hidden from the maze, and
## stops doing anything further. game_manager listens for `died` to drop it
## from the active roster and grey out its HUD panel. If this was the party
## leader and others survive, one of them is promoted so the party keeps
## acting rather than freezing with no one driving it.
##
## Clears in_pvp_combat on itself rather than leaving that to whatever
## called die() (e.g. GroupCombat.release_pvp, which walks the party array to
## find everyone to unlock) — party.erase(self) just below mutates that same
## shared array in place, so a cleanup pass running afterward would no
## longer find this character in it at all.
##
## `by` and `how` record who or what killed them and with what (see
## killed_by / death_method).
func die(by: String = "", how: String = "") -> void:
	killed_by = by
	death_method = how
	dead = true
	stats.hp = 0
	current_action = "Defeated"
	visible = false
	in_pvp_combat = false
	in_pack_combat = false
	stop_sliding()  # or the step's arrival would put them back on the map
	unregister()
	party.erase(self)
	if is_party_leader and not party.is_empty():
		PartyOps.promote_next_leader(self)
	for member in living_party():
		member.sync_label()  # e.g. a last survivor goes back to their own name
	died.emit(self)

## How this character reads as someone's killer: "Bram (Lv.4 Evil)", plus
## " of <party>" if they're in one.
func killer_description() -> String:
	var desc := "%s (Lv.%d %s)" % [npc_name, stats.level, stats.alignment]
	if party.size() > 1 and party_name != "":
		desc += " of %s" % party_name
	return desc

## A combat action (see apply_combat_action) as a killing blow: the spell
## cast, or whatever weapon they're wielding -- "Fireball for 12 damage",
## "Iron Sword for 6 damage", "Bare hands for 3 damage".
func killing_blow(action: String, damage: int) -> String:
	var weapon := "Bare hands"
	match action:
		"fireball":
			weapon = "Fireball"
		"spark":
			weapon = "Spark"
		_:
			for item_name in stats.equipped_in("hand"):
				if ItemCatalog.find(item_name).get("effects", {}).has("attack"):
					weapon = item_name
					break
	return "%s for %d damage" % [weapon, damage]

func retreat() -> void:
	var open_dirs := MazeQuery.open_neighbors(grid, cell_pos)
	var retreat_options: Array = []
	for c in open_dirs:
		if visited.has(c) and not _has_live_enemy(c) and not _has_live_player(c):
			retreat_options.append(c)
	if retreat_options.is_empty():
		return
	move_to(retreat_options[randi() % retreat_options.size()])

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

func move_to(next_cell: Vector2i) -> void:
	is_moving = true
	var duration: float = move_seconds_base / max(stats.move_speed(), 0.1)
	slide_to(_cell_to_world(next_cell), duration).finished.connect(_on_move_finished.bind(next_cell))
	for member in party:
		if member != self and is_instance_valid(member) and not member.dead:
			member._follow_to(next_cell, duration)

## Every step the leader takes, each follower tags along to the same cell,
## offset slightly so the whole party stays visible as distinct members.
func _follow_to(next_cell: Vector2i, duration: float) -> void:
	cell_pos = next_cell
	slide_to(_cell_to_world(next_cell) + party_offset, duration).finished.connect(func(): visited[cell_pos] = true)

## Slides this character's icon to `world_pos` over `seconds`, first
## stopping any slide still under way -- one at a time, so whichever move
## came last decides both where the icon ends up and (through its finished
## callback, which a stopped slide never fires) where cell_pos says it is.
## Two at once used to pull the icon one way while the other's arrival set
## cell_pos somewhere else, leaving the fog lit around an empty spot.
func slide_to(world_pos: Vector2, seconds: float) -> Tween:
	stop_sliding()
	_slide = create_tween()
	_slide.tween_property(self, "position", world_pos, seconds)
	return _slide

func is_sliding() -> bool:
	return _slide != null and _slide.is_valid() and _slide.is_running()

## Stops the icon wherever it is, dropping the slide's finished callback.
func stop_sliding() -> void:
	if _slide != null and _slide.is_valid():
		_slide.kill()
	_slide = null

## What this character can see from where it stands (`sight_cells`), noting
## it on its own map and on the maps of everyone in its party -- party
## members share what they see. Only recomputed after a move, so it's cheap
## enough to call every frame (GameManager._sync_fog does).
func look_around() -> Dictionary:
	if dead or grid.is_empty() or cell_pos == _sight_cell:
		return sight_cells
	_sight_cell = cell_pos
	sight_cells = MazeQuery.visible_cells(grid, cell_pos, SIGHT_RANGE)
	for member in living_party():
		member.seen_cells.merge(sight_cells)
	seen_cells.merge(sight_cells)  # in case this character isn't in its own party list
	return sight_cells

## Puts this (leading) character back in `players` if its cell's entry has
## gone -- as when someone passed through it (see _squeeze_past), took over
## the entry, and then moved on, taking the entry with them -- or if the
## entry is stale (see holds_cell).
func _reclaim_registration() -> void:
	if not holds_cell(players.get(cell_pos), cell_pos):
		players[cell_pos] = self

## Removes this character's own entry from `players` -- and only its own.
## Followers share their leader's cell, and two leaders can briefly share
## one too, so a blind `players.erase(cell_pos)` would wipe out whoever
## else is registered there (e.g. a follower dying used to erase its
## leader, leaving the party invisible to everyone and its fight loop
## unable to find it).
func unregister() -> void:
	if players.get(cell_pos) == self:
		players.erase(cell_pos)

func _on_move_finished(next_cell: Vector2i) -> void:
	unregister()
	cell_pos = next_cell
	is_moving = false
	_on_enter_cell()

func _on_enter_cell() -> void:
	visited[cell_pos] = true
	look_around()
	players[cell_pos] = self
	_check_for_chest()
	if cell_pos == exit_cell and not finished:
		finished = true
		for member in party:
			if is_instance_valid(member):
				member.finished = true
		reached_exit.emit(self)
	reset_label()
	if finished:
		current_action = "Finished the maze!"
	if shops.has(cell_pos) and _party_has_shop_business():
		_start_shopping()

## Picks up anything sitting on our current cell. First come, first served —
## the chest is removed from the shared map the moment it's collected, so
## nobody else can also grab it. A death drop can hand over several items
## plus gold at once. Each item goes to whichever party member it helps most
## (see PartyOps.best_recipient) -- the opener keeps anything nobody can
## use, as a spare to sell -- and the gold is split evenly across the party
## (see share_gold_with_party).
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
	var members := _self_first_party()
	# "Helmet" if the opener kept it, "Helmet → Bram" if it went to a mate.
	var given: Dictionary = {}
	for item_name in loot:
		for i in range(int(loot[item_name])):
			var recipient := PartyOps.best_recipient(members, item_name)
			recipient.receive_item(item_name)
			var entry: String = item_name if recipient == self else "%s → %s" % [item_name, recipient.npc_name]
			given[entry] = int(given.get(entry, 0)) + 1
	var parts: Array = []
	for entry in given:
		parts.append("%s x%d" % [entry, given[entry]] if given[entry] > 1 else entry)
	share_gold_with_party(gold)
	if gold > 0:
		parts.append("%dg" % gold)
	if parts.is_empty():
		return
	show_label("%s found %s!" % [map_name(), ", ".join(parts)], LABEL_MESSAGE_SECONDS)

func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)

## Shows `text` on this character's map label in place of its resting text,
## for `seconds` -- or, if 0, until reset_label puts it back (e.g. at the
## end of the fight it's describing).
func show_label(text: String, seconds: float = 0.0) -> void:
	name_label.text = text
	_label_busy = true
	_label_time_left = seconds

## Counts down a passing message (see show_label). Runs from _process, so
## it freezes while the game's paused.
func _tick_label(delta: float) -> void:
	if _label_time_left <= 0.0:
		return
	_label_time_left -= delta
	if _label_time_left <= 0.0:
		reset_label()

## A newly promoted leader carries on showing whatever the fallen one's
## label was, message countdown and all -- a countdown left running on the
## dead leader would never put the label back.
func take_over_label(former_leader: NpcAgent) -> void:
	name_label.text = former_leader.name_label.text
	_label_busy = former_leader._label_busy
	_label_time_left = former_leader._label_time_left
	sync_label()

## Puts the label back to rest (see _level_tag) once whatever it was
## showing is over.
func reset_label() -> void:
	_label_busy = false
	_label_time_left = 0.0
	name_label.text = _level_tag()
	current_action = "Exploring"
	sync_label()

## The label's resting text: the party's name while in a party, otherwise
## "Name Lv.N".
func _level_tag() -> String:
	if _shows_party_name():
		return party_name
	return "%s Lv.%d" % [npc_name, stats.level]

## Who the label above this character speaks for: their party, by name,
## while they're in one -- otherwise just them.
func map_name() -> String:
	return party_name if _shows_party_name() else npc_name

func _shows_party_name() -> bool:
	return party_name != "" and living_party().size() > 1

## One label per party: only the leader's shows, raised clear of the icons
## of the members standing around it (see PartyOps.PARTY_OFFSETS); a
## follower's is hidden. Called whenever a party changes shape -- someone
## joins (PartyOps.join_party_of), a leader is promoted, someone dies. A
## label at rest also swaps between the party's name and "Name Lv.N"; one
## busy showing something (see show_label) is left alone, and picks it up
## when it goes back to rest.
func sync_label() -> void:
	var in_party := living_party().size() > 1
	name_label.visible = is_party_leader or not in_party
	name_label.position.y = _label_base_y - (PARTY_LABEL_LIFT if in_party else 0.0)
	if not _label_busy:
		name_label.text = _level_tag()

## Keeps the "Name Lv.N" tag above this character current when it levels
## up. Otherwise only reset_label refreshes it, which followers almost
## never run (it's the leader's AI that does), so a follower levelling up
## from its share of a kill's xp kept showing its old level indefinitely.
## Leaves a label that's busy showing something else (a fight, a pickup,
## shopping) alone: those revert via reset_label when they're done,
## picking up the new level then.
func _on_leveled_up(_npc: NpcAgent) -> void:
	if not _label_busy:
		name_label.text = _level_tag()
