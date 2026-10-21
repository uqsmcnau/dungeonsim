class_name NpcRoutes
extends RefCounted

## Where a character steps next, from what it knows of the maze: exploring,
## heading somewhere it's decided to go, backing off, getting out of the
## storm. Every route keeps out of the storm (see Storm) where there's
## another way, and goes through it only if it must. These take the
## NpcAgent as a parameter, like PartyOps and GroupCombat: NpcAgent decides
## what to do, these work out which way.

## The cells the storm covers right now (none if there's no storm), for
## routes to steer round.
static func storm_cells(npc: NpcAgent) -> Dictionary:
	return npc.storm.covered if npc.storm != null else {}

## Cells with a live monster on them, as far as `npc` knows.
static func live_enemy_cells(npc: NpcAgent) -> Dictionary:
	var result: Dictionary = {}
	for c in npc.enemies:
		if npc.has_live_enemy(c):
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

## First step towards the nearest ground the storm doesn't cover, round any
## monsters if there's a way -- or `npc`'s own cell if it isn't caught in
## the storm, or there's nowhere left to run.
static func out_of_storm(npc: NpcAgent) -> Vector2i:
	var storm := npc.storm
	if storm == null or storm.is_closed() or not storm.covers(npc.cell_pos):
		return npc.cell_pos
	var step := MazeQuery.step_out_of(npc.grid, npc.cell_pos, storm.covered, live_enemy_cells(npc))
	if step == npc.cell_pos:
		step = MazeQuery.step_out_of(npc.grid, npc.cell_pos, storm.covered)
	return step

## Which of `open_dirs` (open neighbours of `npc`'s cell) to explore next.
## Prefers an unvisited, enemy-free cell; falls back to any unvisited cell
## (even an enemy's) once safe options run out, then to the BFS frontier
## search, then to a random already-visited neighbor if fully boxed in.
##
## Ground the storm covers comes last: an unvisited cell out of it first,
## then the frontier by a route that stays out of it, and only then
## unvisited cells or a route in it.
static func explore(npc: NpcAgent, open_dirs: Array) -> Vector2i:
	var stormy := storm_cells(npc)
	var unvisited: Array = open_dirs.filter(func(c): return not npc.visited.has(c))
	var dry: Array = unvisited.filter(func(c): return not stormy.has(c))
	var safe: Array = dry.filter(func(c): return not npc.has_live_enemy(c))
	if not safe.is_empty():
		return safe[randi() % safe.size()]
	if not dry.is_empty():
		return dry[randi() % dry.size()]
	var frontier_step := toward_frontier(npc, stormy)
	if frontier_step != npc.cell_pos:
		return frontier_step
	if not unvisited.is_empty():
		var calm: Array = unvisited.filter(func(c): return not npc.has_live_enemy(c))
		return calm[randi() % calm.size()] if not calm.is_empty() else unvisited[randi() % unvisited.size()]
	frontier_step = toward_frontier(npc)
	if frontier_step != npc.cell_pos:
		return frontier_step
	return open_dirs[randi() % open_dirs.size()]

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
