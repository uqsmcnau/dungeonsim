class_name Hunting
extends RefCounted

## A party going after the strongest monster it's sure it can beat: any in
## sight, and the bosses -- the boss on the exit and the mid bosses, none of
## whom ever leave their rooms -- wherever it's seen one. NpcAgent decides
## when (see NpcAgent._take_step) and fights what it meets (see
## NpcAgent._will_fight); these, static functions taking the character like
## Shopping and NpcRoutes, work out which and which way.

## How sure a party must be of beating a monster's whole pack -- a boss's
## party, say -- before setting off to fight it (see
## CombatMath.group_win_chance): more than even odds, since the estimate
## leaves out the monsters' critical hits.
const CONFIDENCE := 0.6

## Next step toward the monster `npc`'s party is out to fight
## (NpcAgent.hunt_target), or its own cell if there's none: once it's
## picked one (see strongest) it keeps after it while it's still worth it
## (see worth_hunting), even if a wall hides it for a step -- dropping it
## the moment it's out of sight had the party turn to something else, see
## it again, turn back...
static func step(npc: NpcAgent) -> Vector2i:
	var busy := NpcRoutes.leave_alone(npc)
	var stormy := NpcRoutes.storm_cells(npc)
	if not worth_hunting(npc, npc.hunt_target, busy, stormy, true):
		npc.hunt_target = strongest(npc, busy, stormy)
	var target: EnemyAgent = npc.hunt_target
	if target == null:
		return npc.cell_pos
	var next := NpcRoutes.step_through_seen(npc, target.cell_pos)
	if next == npc.cell_pos:
		npc.hunt_target = null
		return npc.cell_pos
	npc.current_action = "Off to fight %s" % target.kind.called(target.in_boss_party())
	return next

## The strongest monster `npc`'s party could set off to fight (see
## worth_hunting, given the cells to leave alone and the storm's), or null:
## the one whose pack is worth the most XP -- the boss on the exit, if it's
## up to that, since beating it wins the race; then the mid bosses, and so
## on -- and of those alike, the nearest.
static func strongest(npc: NpcAgent, busy: Dictionary, stormy: Dictionary) -> EnemyAgent:
	var best: EnemyAgent = null
	var best_xp := 0
	var best_dist := 0
	for c in npc.enemies:
		var enemy = npc.enemies[c]
		if not worth_hunting(npc, enemy, busy, stormy):
			continue
		var xp := 0
		for m in enemy.living_pack():
			xp += m.stats.xp
		var dist: int = abs(c.x - npc.cell_pos.x) + abs(c.y - npc.cell_pos.y)
		if best == null or xp > best_xp or (xp == best_xp and dist < best_dist):
			best = enemy
			best_xp = xp
			best_dist = dist
	return best

## Whether `enemy` (a live pack leader on the map) is one `npc`'s party
## could set off to fight: in sight -- or, `already_hunting` it, not far
## off -- or holding a boss room it's seen. Bosses never leave their rooms,
## so a room seen once (by anyone in the party, see NpcAgent.seen_cells) is
## remembered, to come back to once strong enough; other monsters wander
## off. And it must be sure it can win (see confident_against). Not one in
## the storm (`stormy`), one someone else is fighting, or one it's just
## backed away from (`busy`, see NpcRoutes.leave_alone).
static func worth_hunting(npc: NpcAgent, enemy, busy: Dictionary, stormy: Dictionary,
		already_hunting: bool = false) -> bool:
	if enemy == null or not is_instance_valid(enemy) or not enemy.alive or enemy.in_combat:
		return false
	var c: Vector2i = enemy.cell_pos
	if npc.enemies.get(c) != enemy or busy.has(c) or stormy.has(c):
		return false
	if enemy.in_boss_party():
		if not npc.seen_cells.has(c):
			return false
	elif not npc.sight_cells.has(c):
		if not already_hunting or MazeQuery.chebyshev(npc.cell_pos, c) > NpcAgent.SIGHT_RANGE * 2:
			return false
	return confident_against(npc, enemy)

## Whether `npc`'s party is sure it can beat `enemy`'s whole pack, as it
## stands now: odds better than CONFIDENCE.
static func confident_against(npc: NpcAgent, enemy: EnemyAgent) -> bool:
	var ours: Array = npc.living_party().map(func(m): return m.stats)
	var theirs: Array = enemy.living_pack().map(func(m): return m.stats)
	return CombatMath.group_win_chance(ours, theirs) > CONFIDENCE
