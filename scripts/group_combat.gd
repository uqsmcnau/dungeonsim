class_name GroupCombat
extends RefCounted

## The two group fight loops: a player party against a monster pack, and a
## player party against another player party. Every living member on both
## sides takes part, each fighting with their own tactics each turn (see
## NpcAgent.choose_combat_action / apply_combat_action); these just run the
## turns and the beginning and end of the fight.
##
## Both identify a side by its party's shared array rather than by any one
## character or cell: whoever's "driving" (the party's current leader, see
## PartyOps.leader_of) can change mid-fight if they fall and others survive,
## and newcomers who join (see PartyOps.join_party_of) land in the same
## array, so they're picked up from the next turn on. Turns are paced by
## pause-respecting SceneTree timers calling straight back into these
## static functions.
##
## Every blow, spell, heal and escape is also reported, as it happens, on
## the combat_event signal of the player it involves (a CombatEvent, sent
## before any death it causes is dealt with), for the battle window to play
## out.

const TURN_SECONDS := 1.0
## Break off a fight once HP is down to this many expected enemy hits.
const FLEE_DANGER_TURNS := 0.5
## Enemies occasionally hit harder than a character can plan around, which
## is what keeps even a careful character from being completely safe.
const ENEMY_CRIT_CHANCE := 0.27
const ENEMY_CRIT_MULTIPLIER := 2.0

# =========================== Party vs monster pack ========================

## Starts a fight between `npc`'s whole party and an enemy pack on
## `enemy_cell`. Every party member (not just whoever's driving right now)
## gets is_moving locked for the whole fight, the same way engage_players
## locks in_pvp_combat on everyone upfront -- otherwise a follower promoted
## to leader mid-fight (see NpcAgent.die()) would still have is_moving false
## and could wander off exploring on its own while the fight it's now
## supposedly driving is still going.
static func engage_pack(npc: NpcAgent, enemy_cell: Vector2i, enemy: EnemyAgent) -> void:
	for ally in npc.living_party():
		ally.is_moving = true
		ally.in_pack_combat = true
	for pack_member in enemy.living_pack():
		pack_member.in_combat = true
		pack_member.fighting_party = npc.party
	run_pack_turn(npc.party, enemy_cell, npc.enemies)

## Whether `me`, leading its side of a fight against someone with
## `foe_stats`, breaks it off: when the next blow could well finish it --
## unless it's cornered (NpcAgent.cornered), or has nowhere to back off to.
## Fleeing on the spot would only end the fight for the other side to start
## it again, over and over, nobody ever moving.
static func _should_flee(me: NpcAgent, foe_stats: NpcStats) -> bool:
	if me.cornered or NpcRoutes.retreat_cell(me) == me.cell_pos:
		return false
	return me.stats.hp <= CombatMath.damage_taken_per_hit(me.stats, foe_stats) * FLEE_DANGER_TURNS

## One turn of a party-vs-pack fight. `my_party` is the party's shared
## array, `enemy_cell` is where the pack is anchored, and `enemies` the
## shared monster map it's looked up in (passed along rather than read off a
## party member, since a party that's been wiped out has none left).
##
## This used to find the driver by looking up whoever was registered on the
## party's cell in `players`. Anything that knocked that registration out
## mid-fight (e.g. a dying follower erasing its leader's entry) ended the
## loop with the party still locked -- stuck in place for good.
static func run_pack_turn(my_party: Array, enemy_cell: Vector2i, enemies: Dictionary) -> void:
	var me: NpcAgent = PartyOps.leader_of(my_party)
	if me == null:
		release_pack(enemies, enemy_cell)
		return
	var enemy := pack_at(enemies, enemy_cell)
	var foes: Array = enemy.living_pack() if enemy != null else []
	if foes.is_empty():
		conclude_pack_fight(me, enemy_cell)
		return

	var target: EnemyAgent = me.weakest_of(foes)
	if _should_flee(me, target.stats):
		disengage_pack_fight(me, enemy_cell)
		return

	me.current_action = "Fighting a level %d enemy" % target.stats.level
	me.show_label("%s ⚔ Lv.%d" % [me.map_name(), target.stats.level])
	var timer := me.get_tree().create_timer(TURN_SECONDS, false)
	timer.timeout.connect(resolve_pack_turn.bind(my_party, enemy_cell, enemies))

static func resolve_pack_turn(my_party: Array, enemy_cell: Vector2i, enemies: Dictionary) -> void:
	var me: NpcAgent = PartyOps.leader_of(my_party)
	if me == null:
		release_pack(enemies, enemy_cell)
		return
	var enemy := pack_at(enemies, enemy_cell)
	if enemy == null:
		conclude_pack_fight(me, enemy_cell)
		return

	var foes: Array = enemy.living_pack()
	for ally in me.living_party():
		if foes.is_empty():
			break
		var target: EnemyAgent = me.weakest_of(foes)
		var action: String = ally.choose_combat_action(target.stats)
		var result: Dictionary = ally.apply_combat_action(action, target.stats)
		ally.combat_event.emit(CombatEvent.of_action(ally, target, action, result["amount"], result["missed"]))
		if target.stats.hp <= 0:
			foes.erase(target)
			ally.share_gold_with_party(target.stats.gold)
			ally.share_xp_with_party(target.stats.xp)
			target.defeat()

	if foes.is_empty():
		conclude_pack_fight(me, enemy_cell)
		return

	for foe in foes:
		var allies: Array = me.living_party()
		if allies.is_empty():
			break
		var victim: NpcAgent = allies[randi() % allies.size()]
		if randf() < CombatMath.hit_chance_against(foe.stats, victim.stats):
			var damage: int = max(1, foe.stats.attack_power() + randi() % 3 - victim.stats.defense())
			var crit := randf() < ENEMY_CRIT_CHANCE
			if crit:
				damage = int(ceil(damage * ENEMY_CRIT_MULTIPLIER))
			victim.stats.hp -= damage
			victim.combat_event.emit(CombatEvent.of_action(foe, victim, CombatRules.ATTACK, damage, false, crit))
			if victim.stats.hp <= 0:
				victim.die(foe.killer_description(), "%s for %d damage" % ["A critical hit" if crit else "A hit", damage])
		else:
			victim.combat_event.emit(CombatEvent.of_action(foe, victim, CombatRules.ATTACK, 0, true))

	# If the whole party fell, release the pack via release_pack, not
	# `enemy.in_combat = false`: `enemy` is whoever led the pack at the start
	# of this turn, and if the party killed it above, a follower has since
	# taken over -- releasing the dead one would leave the survivor locked
	# in_combat (and frozen in place) forever.
	if PartyOps.leader_of(my_party) == null:
		release_pack(enemies, enemy_cell)
		return
	run_pack_turn(my_party, enemy_cell, enemies)

## Releases the pack's in_combat flag when a party-vs-pack fight ends
## abruptly with no living representative left to drive it to a proper
## conclusion (e.g. the whole party died). Without this the pack would stay
## permanently marked as mid-fight, and nobody could ever engage -- or even
## walk past -- it again (see NpcAgent._process/_attempt_move, which both
## retreat from a cell whose enemy.in_combat is true rather than passing
## it). Looks the pack up fresh by cell so it always finds the current
## leader, and releases the whole pack (see EnemyAgent.end_combat).
static func release_pack(enemies: Dictionary, enemy_cell: Vector2i) -> void:
	var enemy := pack_at(enemies, enemy_cell)
	if enemy != null:
		enemy.end_combat()

## Whoever leads the pack on `cell` in the monster map, or null. Checked
## for validity before being typed: a turn's timer isn't tied to any node,
## so it can still fire after the whole scene (monsters and all) has been
## freed -- e.g. at the end of a test.
static func pack_at(enemies: Dictionary, cell: Vector2i) -> EnemyAgent:
	var found = enemies.get(cell)
	return found if is_instance_valid(found) else null

## Ends a party-vs-pack fight once the pack is wiped out: frees every party
## member's is_moving lock (see engage_pack) and moves the surviving party
## onto the now-empty cell (see claim_cell).
static func conclude_pack_fight(me: NpcAgent, enemy_cell: Vector2i) -> void:
	for member in me.party:
		if is_instance_valid(member):
			member.is_moving = false
			member.in_pack_combat = false
	claim_cell(me, enemy_cell)

## Moves the side `winner` leads onto the loser's `cell` to claim it (and
## any loot left there) -- but only if it's right there: its own cell or an
## open neighbour. The cell was noted when the fight began, and the two can
## have ended up further apart since (a defender attacked mid-step still
## finishes the step), so heading straight for it could mean sliding
## through walls, cell_pos jumping a cell or more at once.
static func claim_cell(winner: NpcAgent, cell: Vector2i) -> void:
	winner.reset_label()
	if cell == winner.cell_pos or MazeQuery.open_neighbors(winner.grid, winner.cell_pos).has(cell):
		winner.move_to(cell)

## Breaks off a fight that's turning dangerous for the character driving it.
## Damage already dealt stays on the pack, so the party can retreat, recover,
## and come back to finish it. Frees every party member's is_moving lock
## (see engage_pack), not just the driver's.
static func disengage_pack_fight(me: NpcAgent, enemy_cell: Vector2i) -> void:
	me.combat_event.emit(CombatEvent.escape(me))
	release_pack(me.enemies, enemy_cell)
	for member in me.party:
		if is_instance_valid(member):
			member.is_moving = false
			member.in_pack_combat = false
	me.reset_label()
	me.retreat()

# ============================ Party vs party ==============================

## Starts a player-vs-player fight between `npc`'s whole party and
## `opponent`'s, the opponent standing on `opponent_cell`.
##
## in_pvp_combat on every member of both sides is the only lock needed --
## NpcAgent._process already refuses to act while it's set. This used to
## also set is_moving on the attacker, but only the attacker's own exit
## paths ever cleared that: when the *defender* fled (or its party vanished
## mid-fight), the attacker stayed locked forever, still "Fighting".
static func engage_players(npc: NpcAgent, opponent_cell: Vector2i, opponent: NpcAgent) -> void:
	for member in npc.living_party():
		member.in_pvp_combat = true
		member.pvp_foes = opponent.party
	for member in opponent.living_party():
		member.in_pvp_combat = true
		member.pvp_foes = npc.party
	run_pvp_turn(npc.party, opponent.party, npc.cell_pos, opponent_cell)

## One turn of a party-vs-party fight. `my_party`/`their_party` are the two
## sides' shared party arrays — a stable identity even when (as when this
## fight was triggered by one side finding the other already on its own
## cell) both sides occupy the exact same cell, which a cell-keyed lookup
## couldn't tell apart. `my_cell`/`their_cell` are only kept around for the
## final move onto the loser's position once the fight ends.
static func run_pvp_turn(my_party: Array, their_party: Array, my_cell: Vector2i, their_cell: Vector2i) -> void:
	var me: NpcAgent = PartyOps.leader_of(my_party)
	var them: NpcAgent = PartyOps.leader_of(their_party)
	if me == null or them == null:
		release_pvp(my_party, their_party)
		return
	var foes: Array = them.living_party()
	var allies: Array = me.living_party()
	if foes.is_empty() or allies.is_empty():
		conclude_pvp(my_party, their_party, my_cell, their_cell)
		return

	var my_target: NpcAgent = me.weakest_of(foes)
	if _should_flee(me, my_target.stats):
		disengage_pvp(me, my_party, their_party)
		return
	var their_target: NpcAgent = them.weakest_of(allies)
	if _should_flee(them, their_target.stats):
		disengage_pvp(them, their_party, my_party)
		return

	me.current_action = "Fighting %s" % them.npc_name
	me.show_label("%s ⚔ vs %s" % [me.map_name(), them.map_name()])
	them.current_action = "Fighting %s" % me.npc_name
	them.show_label("%s ⚔ vs %s" % [them.map_name(), me.map_name()])

	var timer := me.get_tree().create_timer(TURN_SECONDS, false)
	timer.timeout.connect(resolve_pvp_turn.bind(my_party, their_party, my_cell, their_cell))

static func resolve_pvp_turn(my_party: Array, their_party: Array, my_cell: Vector2i, their_cell: Vector2i) -> void:
	var me: NpcAgent = PartyOps.leader_of(my_party)
	var them: NpcAgent = PartyOps.leader_of(their_party)
	if me == null or them == null:
		release_pvp(my_party, their_party)
		return

	var foes: Array = them.living_party()
	for ally in me.living_party():
		if foes.is_empty():
			break
		var target: NpcAgent = me.weakest_of(foes)
		var action: String = ally.choose_combat_action(target.stats)
		var hp_before: int = target.stats.hp
		var result: Dictionary = ally.apply_combat_action(action, target.stats)
		ally.combat_event.emit(CombatEvent.of_action(ally, target, action, result["amount"], result["missed"]))
		if target.stats.hp <= 0:
			foes.erase(target)
			target.die(ally.killer_description(), ally.killing_blow(action, hp_before - target.stats.hp))

	var allies: Array = me.living_party()
	if foes.is_empty() or allies.is_empty():
		conclude_pvp(my_party, their_party, my_cell, their_cell)
		return

	for foe in foes:
		allies = me.living_party()
		if allies.is_empty():
			break
		var target: NpcAgent = foe.weakest_of(allies)
		var action: String = foe.choose_combat_action(target.stats)
		var hp_before: int = target.stats.hp
		var result: Dictionary = foe.apply_combat_action(action, target.stats)
		foe.combat_event.emit(CombatEvent.of_action(foe, target, action, result["amount"], result["missed"]))
		if target.stats.hp <= 0:
			target.die(foe.killer_description(), foe.killing_blow(action, hp_before - target.stats.hp))

	if me.living_party().is_empty() or them.living_party().is_empty():
		conclude_pvp(my_party, their_party, my_cell, their_cell)
		return

	if PartyOps.leader_of(my_party) == null:
		release_pvp(my_party, their_party)
		return
	run_pvp_turn(my_party, their_party, my_cell, their_cell)

## Ends a party-vs-party fight once one side (or both) has no one left
## standing: releases both sides' combat locks, and if exactly one side
## still has survivors, moves them onto the other's cell to claim it (and
## any death-chest loot left behind; see claim_cell) — a no-op move if the
## two were already sharing the same cell.
static func conclude_pvp(my_party: Array, their_party: Array, my_cell: Vector2i, their_cell: Vector2i) -> void:
	release_pvp(my_party, their_party)
	var my_side: NpcAgent = PartyOps.leader_of(my_party)
	var their_side: NpcAgent = PartyOps.leader_of(their_party)
	# No is_moving to free here: a PvP fight doesn't lock it (see
	# engage_players), so it's only set if a side is genuinely mid-step.
	if my_side != null and their_side == null:
		claim_cell(my_side, their_cell)
	elif their_side != null and my_side == null:
		claim_cell(their_side, my_cell)

## Frees both sides from the fight, and clears the "Fighting X" status off
## everyone still standing -- otherwise a side that didn't drive the ending
## (e.g. the one left behind when the other flees) keeps showing it.
static func release_pvp(party_a: Array, party_b: Array) -> void:
	for party_ref in [party_a, party_b]:
		for member in party_ref:
			if is_instance_valid(member):
				member.in_pvp_combat = false
				member.pvp_foes = []
				if not member.dead:
					member.reset_label()

## Breaks off a player-vs-player fight that's turning dangerous for `me`,
## the character driving one side of it — both sides are freed to resume
## their own AI, and `me`'s party retreats together -- unless it's already
## on its way out. Attacked again mid-step (it's still registered on the
## cell it's leaving, so an attacker sharing that cell sets on it again
## every frame), fleeing afresh each time used to restart the step towards
## a fresh random way out before it got anywhere, the two stuck there for
## good.
static func disengage_pvp(me: NpcAgent, my_party: Array, their_party: Array) -> void:
	me.combat_event.emit(CombatEvent.escape(me))
	release_pvp(my_party, their_party)
	me.reset_label()
	if me.is_sliding():
		return
	me.is_moving = false
	me.retreat()

# ============================== Reporting =================================

## Who `npc`'s party is fighting right now: the living members of the
## monster pack (looked up in `enemies`) or the other party -- or nobody.
static func opponents_of(npc: NpcAgent, enemies: Dictionary) -> Array:
	if npc.in_pvp_combat:
		return npc.pvp_foes.filter(func(m): return is_instance_valid(m) and not m.dead)
	if npc.in_pack_combat:
		for cell in enemies:
			var enemy := pack_at(enemies, cell)
			if enemy != null and enemy.in_combat and is_same(enemy.fighting_party, npc.party):
				return enemy.living_pack()
	return []
