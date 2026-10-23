class_name NpcRoutes
extends RefCounted

## Where a character steps next, from what it knows of the maze: exploring,
## heading somewhere it's decided to go, backing off, getting out of the
## storm. Every route keeps out of the storm (see Storm) where there's
## another way, and goes through it only if it must. These take the
## NpcAgent as a parameter, like PartyOps and GroupCombat: NpcAgent decides
## what to do, these work out which way.

## The cells to steer round: those the storm covers, and any dry pocket
## it's cut off from the middle (see Storm.unsafe) -- none if there's no
## storm.
static func storm_cells(npc: NpcAgent) -> Dictionary:
	return npc.storm.unsafe if npc.storm != null else {}

## Cells with a live monster on them, as far as `npc` knows -- only those
## within `reach` cells of it, if that's given.
static func live_enemy_cells(npc: NpcAgent, reach: int = -1) -> Dictionary:
	var result: Dictionary = {}
	for c in npc.enemies:
		if (reach < 0 or MazeQuery.chebyshev(c, npc.cell_pos) <= reach) and npc.has_live_enemy(c):
			result[c] = true
	return result

## First step towards `to`, staying out of the storm if there's a way (and
## round `blocked` cells), else through it.
static func step_toward(npc: NpcAgent, to: Vector2i, max_depth: int, blocked: Dictionary = {}) -> Vector2i:
	var stormy := storm_cells(npc)
	if not stormy.is_empty() and not stormy.has(to):
		var avoiding: Dictionary = blocked.duplicate()
		avoiding.merge(stormy)
		var step := MazeQuery.step_toward(npc.grid, npc.cell_pos, to, max_depth, avoiding)
		if step != npc.cell_pos:
			return step
	return MazeQuery.step_toward(npc.grid, npc.cell_pos, to, max_depth, blocked)

## First step towards the nearest safe ground (see Storm.unsafe), round any
## monsters if there's a way -- through the storm if that's the only way,
## out of a pocket it's cut off as much as out of the storm itself. Or
## `npc`'s own cell if it's already safe, or there's nowhere left to run.
static func out_of_storm(npc: NpcAgent) -> Vector2i:
	var storm := npc.storm
	if storm == null or storm.is_closed() or storm.is_safe(npc.cell_pos):
		return npc.cell_pos
	var step := MazeQuery.step_out_of(npc.grid, npc.cell_pos, storm.unsafe, live_enemy_cells(npc))
	if step == npc.cell_pos:
		step = MazeQuery.step_out_of(npc.grid, npc.cell_pos, storm.unsafe)
	return step

## Whether stepping to `next` would take `npc` off safe ground into the
## storm (or a pocket it's cut off). Only worth it to get somewhere that
## matters: anything else -- a chest, a shop, someone to team up with, more
## to explore -- and it'd only turn round and get out again the next step,
## back and forth until the storm took its ground anyway.
static func leaves_safe_ground(npc: NpcAgent, next: Vector2i) -> bool:
	var stormy := storm_cells(npc)
	return stormy.has(next) and not stormy.has(npc.cell_pos)

## Which of `open_dirs` (open neighbours of `npc`'s cell) to explore next.
## Prefers an unvisited, enemy-free cell; falls back to any unvisited cell
## (even an enemy's) once safe options run out, then to the BFS frontier
## search, then to a random already-visited neighbor if fully boxed in.
##
## Ground the storm covers (or has cut off, see storm_cells) comes last: an
## unvisited cell out of it first, then the frontier by a route that stays
## out of it. On safe ground with none of that left, it wanders about on
## safe ground rather than step into the storm; only caught in it already
## (with no way out, or it'd be escaping) does it explore there.
##
## A cell where someone else is mid-fight, or a monster it's just backed
## away from, is left alone while there's anywhere else to go (see
## leave_alone).
static func explore(npc: NpcAgent, open_dirs: Array) -> Vector2i:
	var busy := leave_alone(npc)
	var free: Array = open_dirs.filter(func(c): return not busy.has(c))
	if not free.is_empty():
		open_dirs = free
	var stormy := storm_cells(npc)
	var unvisited: Array = open_dirs.filter(func(c): return not npc.visited.has(c))
	var dry: Array = unvisited.filter(func(c): return not stormy.has(c))
	var safe: Array = dry.filter(func(c): return not npc.has_live_enemy(c))
	if not safe.is_empty():
		return safe[randi() % safe.size()]
	if not dry.is_empty():
		return dry[randi() % dry.size()]
	var avoid := stormy.duplicate()
	avoid.merge(busy)
	var frontier_step := toward_frontier(npc, avoid)
	if frontier_step != npc.cell_pos:
		return frontier_step
	if not stormy.has(npc.cell_pos):
		# On safe ground with nothing left to explore on it: wander about on
		# it rather than into the storm (see leaves_safe_ground) -- or, if
		# the only safe way on is somewhere to leave alone for now, wait.
		var dry_dirs: Array = open_dirs.filter(func(c): return not stormy.has(c) and not busy.has(c))
		return dry_dirs[randi() % dry_dirs.size()] if not dry_dirs.is_empty() else npc.cell_pos
	if not unvisited.is_empty():
		var calm: Array = unvisited.filter(func(c): return not npc.has_live_enemy(c))
		return calm[randi() % calm.size()] if not calm.is_empty() else unvisited[randi() % unvisited.size()]
	frontier_step = toward_frontier(npc)
	if frontier_step != npc.cell_pos:
		return frontier_step
	return open_dirs[randi() % open_dirs.size()]

## Cells exploring leaves alone while there's anywhere else to go: where
## another player (not one of `npc`'s party) is mid-fight, and the monsters
## it's just backed away from (NpcAgent.daunted). Stepping there would only
## mean backing off again -- someone else's fight can't be joined unless the
## two parties could team up, and is never attacked; a monster too strong
## for it is still too strong -- so exploring there would just mean walking
## up to it and back, over and over.
static func leave_alone(npc: NpcAgent) -> Dictionary:
	var result: Dictionary = {}
	for c in npc.daunted:
		if npc.has_live_enemy(c):  # it's still there: once it's moved on, so has the problem
			result[c] = true
	for c in npc.players:
		var other = npc.players[c]
		if is_instance_valid(other) and not npc.party.has(other) and other.is_in_combat():
			result[c] = true
	return result

## BFS over cells reachable through open passages, looking for the nearest
## cell that still has an unvisited neighbor. Returns the first step along
## the way there, or `npc`'s own cell if nothing is left to discover --
## never going through an `avoid` cell (the storm, say) on the way.
static func toward_frontier(npc: NpcAgent, avoid: Dictionary = {}) -> Vector2i:
	var from := npc.cell_pos
	var queue: Array = [from]
	var came_from: Dictionary = {from: from}
	while queue.size() > 0:
		var cur: Vector2i = queue.pop_front()
		for n in MazeQuery.open_neighbors(npc.grid, cur):
			if came_from.has(n) or avoid.has(n):
				continue
			came_from[n] = cur
			if not npc.visited.has(n):
				var step: Vector2i = n
				while came_from[step] != from:
					step = came_from[step]
				return step
			queue.append(n)
	return from

## Where backing off goes: a random neighbour already explored and clear of
## monsters and players -- out of the storm rather than into it, where
## there's the choice -- or `npc`'s own cell if there's nowhere.
static func retreat_cell(npc: NpcAgent) -> Vector2i:
	var options: Array = []
	for c in MazeQuery.open_neighbors(npc.grid, npc.cell_pos):
		if npc.visited.has(c) and not npc.has_live_enemy(c) and not npc.has_live_player(c):
			options.append(c)
	if options.is_empty():
		return npc.cell_pos
	var stormy := storm_cells(npc)
	var dry: Array = options.filter(func(c): return not stormy.has(c))
	if not dry.is_empty():
		options = dry
	return options[randi() % options.size()]
