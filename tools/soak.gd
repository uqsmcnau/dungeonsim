extends SceneTree

## Soak test: plays one whole game headless, start to finish, watching for
## the kinds of trouble that only turn up in a real game -- the ones that
## got past the unit tests before:
##   - a party leader frozen: nothing about them or around them changing
##     for STUCK_SECONDS (players stuck exploring; two stuck after a fight);
##   - a character's icon and cell_pos a cell or more apart for over
##     GAP_SECONDS (walls left lit where nobody is);
##   - a `players` map entry that doesn't stand for anyone there, for over
##     STALE_SECONDS (fights started from across the maze);
##   - fog lit with nobody near enough to see it, for over DARK_SECONDS;
## and, reported as LOOP lines that don't fail the run -- the AI caught in
## a loop, which has had many causes and still turns up rarely, in odd
## corners round the storm's edge (each worth a look, but no reason to fail
## a push over):
##   - a leader bouncing in and out of the storm: walking back into it,
##     within BOUNCE_SECONDS of getting out, BOUNCE_LIMIT times in
##     BOUNCE_WINDOW seconds (heading back to a pocket the storm had cut off)
##     -- not on its way out of it, whose route can cross the ring's edge
##     back and forth, the maze's passages being square and the ring round;
##   - a leader pacing: PACING_MOVES or more steps in PACING_SECONDS over
##     PACING_CELLS cells or fewer, with plenty of safe ground about (walking
##     up to the storm's edge after a chest and back, over and over).
## Keeps someone selected throughout, so the HUD, Party Vision and the
## battle window are exercised too. Reports each problem once, with the
## recent history of whoever's involved, and exits 1 if there were any.
##
## One game, from the project folder:
##   godot --headless --path . --fixed-fps 60 -s tools/soak.gd -- --seed=7
## Options (after the --): --seed=N (default 1; a game replays exactly from
## its seed), --seconds=N (game seconds before calling it a day; default 600).
## Godot's own --time-scale=N (before the -s) plays it at the toolbar's game
## speed xN; a game replays exactly only at the speed it was played at.
## Several games at once: tools/soak.sh.

const STUCK_SECONDS := 10.0
const GAP_SECONDS := 1.0
const STALE_SECONDS := 2.0
const DARK_SECONDS := 1.0
const BOUNCE_SECONDS := 3.0
const BOUNCE_WINDOW := 30.0
const BOUNCE_LIMIT := 3
const PACING_SECONDS := 20.0
const PACING_MOVES := 10
const PACING_CELLS := 3
## Pacing only counts while there's at least this much safe ground -- at the
## very end, with the storm nearly closed, there's nowhere much to go.
const PACING_MIN_SAFE_CELLS := 40
const HISTORY_LINES := 12

var main: GameManager
var game_seed := 1
var max_seconds := 600.0
var t := 0.0
var problems := 0
var _reported: Dictionary = {}
var _last_state: Dictionary = {}
var _still_since: Dictionary = {}
var _gap_since: Dictionary = {}
var _stale_since: Dictionary = {}
## Per leader: whether it was in the storm last frame, when it last got out,
## and when it walked back in (within BOUNCE_SECONDS) lately.
var _in_storm: Dictionary = {}
var _left_storm_at: Dictionary = {}
var _bounces: Dictionary = {}
## Per leader: whether it was escaping the storm last frame -- its label's
## back to its usual by the frame its step ends.
var _escaping: Dictionary = {}
## Per leader: its recent steps, as [time, cell].
var _steps: Dictionary = {}
var _maze_cells := -1
var _dark_since := -1.0
var _history: Dictionary = {}
var _frames_to_quit := 5

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			game_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seconds="):
			max_seconds = float(arg.get_slice("=", 1))
	main = load("res://scenes/Main.tscn").instantiate()
	main.game_seed = game_seed
	root.add_child(main)

func _process(delta: float) -> bool:
	if main == null:
		# The game's been freed (see _finish); give the audio a few frames to
		# let go of the music it was playing before shutting down.
		_frames_to_quit -= 1
		if _frames_to_quit <= 0:
			quit(1 if problems > 0 else 0)
		return false
	t += delta
	_keep_someone_selected()
	var living: Array = main.npcs.filter(func(n): return not n.dead)
	for n in living:
		_note_history(n)
	_check_frozen(living)
	_check_gaps(living)
	_check_stale_entries()
	_check_dark(living)
	_check_storm_bounces(living)
	_check_pacing(living)
	if t >= max_seconds or main.winner != null or living.is_empty():
		var winner: String = main.winner.npc_name if main.winner != null else "none"
		print("SOAK seed=%d speed=x%d t=%.0f winner=%s alive=%d problems=%d" % [
			game_seed, int(Engine.time_scale), t, winner, living.size(), problems])
		main.free()
		main = null
	return false

## Whoever's selected falls: pick someone else, preferably in a party.
func _keep_someone_selected() -> void:
	var npc: NpcAgent = main.hud.inspected
	if npc != null and not npc.dead:
		return
	var living: Array = main.npcs.filter(func(n): return not n.dead)
	if living.is_empty():
		return
	var in_parties: Array = living.filter(func(n): return n.party.size() > 1)
	var pool: Array = in_parties if not in_parties.is_empty() else living
	main.hud.inspect(pool[randi() % pool.size()])

# ================================= Checks =================================

func _check_frozen(living: Array) -> void:
	for n in living:
		if n.finished or not n.is_party_leader or n.current_action in ["Resting", "Waiting"]:
			continue
		var state := [n.cell_pos, n.position.round(), n.is_moving, n.in_pvp_combat, n.in_pack_combat, n.current_action, _hp_around(n)]
		if _last_state.get(n) != state:
			_last_state[n] = state
			_still_since[n] = t
		elif t - _still_since[n] > STUCK_SECONDS:
			var near: Array = living.filter(func(o): return o != n and _distance(o.cell_pos, n.cell_pos) <= 1)
			_problem("frozen:%s" % n.npc_name, "%s has been frozen for %ds" % [n.npc_name, STUCK_SECONDS], [n] + near)

## Everyone's HP in and next to `n`'s cell, and that of whoever its party's
## fighting, wherever they stand -- a fight that's still going changes it, a
## frozen one doesn't. (A fight can carry on two cells apart, and a foe who
## does nothing but heal leaves only their own HP changing.)
func _hp_around(n: NpcAgent) -> Array:
	var hps: Array = n.party.map(func(m): return m.stats.hp)
	for foe in n.pvp_foes:
		if is_instance_valid(foe):
			hps.append(foe.stats.hp)
	for o in main.npcs:
		if o != n and _distance(o.cell_pos, n.cell_pos) <= 1:
			hps.append(o.stats.hp)
	for c in main.enemy_map:
		if _distance(c, n.cell_pos) <= 1:
			var e = main.enemy_map[c]
			if is_instance_valid(e):
				hps.append(e.stats.hp)
	return hps

func _check_gaps(living: Array) -> void:
	for n in living:
		if _distance(_icon_cell(n), n.cell_pos) <= 1:
			_gap_since.erase(n)
			continue
		if not _gap_since.has(n):
			_gap_since[n] = t
		elif t - _gap_since[n] > GAP_SECONDS:
			_problem("gap:%s" % n.npc_name, "%s's icon is at %s but its cell is %s" % [n.npc_name, _icon_cell(n), n.cell_pos], [n])

func _check_stale_entries() -> void:
	for cell in _stale_since.keys():
		if not main.player_map.has(cell):
			_stale_since.erase(cell)
	for cell in main.player_map:
		var entry = main.player_map[cell]
		if NpcBody.holds_cell(entry, cell):
			_stale_since.erase(cell)
			continue
		if not _stale_since.has(cell):
			_stale_since[cell] = t
		elif t - _stale_since[cell] > STALE_SECONDS:
			var who: String = entry.npc_name if is_instance_valid(entry) else "a freed node"
			_problem("stale:%s" % cell, "the map has %s on %s, but they don't stand for anyone there" % [who, cell],
				[entry] if is_instance_valid(entry) else [])

func _check_dark(living: Array) -> void:
	var view: MazeView = main.maze_view
	var lit_alone := 0
	for c in view.currently_visible:
		if view.sticky_cells.has(c):
			continue
		if not living.any(func(n): return _distance(_icon_cell(n), c) <= NpcAgent.SIGHT_RANGE + 1):
			lit_alone += 1
	if lit_alone == 0:
		_dark_since = -1.0
	elif _dark_since < 0.0:
		_dark_since = t
	elif t - _dark_since > DARK_SECONDS:
		_problem("dark", "%d cells are lit with nobody near enough to see them" % lit_alone, [])

## Leaders following the spectator's Guidance may cross the storm on purpose.
func _check_storm_bounces(living: Array) -> void:
	var storm: Storm = main.storm
	for n in living:
		if not n.is_party_leader or n.guidance_target != MazeQuery.NONE:
			continue
		var inside := storm.covers(n.cell_pos)
		var was_inside: bool = _in_storm.get(n, false)
		var was_escaping: bool = _escaping.get(n, false)
		_in_storm[n] = inside
		_escaping[n] = n.current_action == "Escaping the storm"
		if was_inside and not inside:
			_left_storm_at[n] = t
		elif inside and not was_inside and not was_escaping and _moved_last(n) \
				and t - _left_storm_at.get(n, -INF) < BOUNCE_SECONDS:
			var recent: Array = _bounces.get(n, []).filter(func(at): return t - at < BOUNCE_WINDOW)
			recent.append(t)
			_bounces[n] = recent
			if recent.size() >= BOUNCE_LIMIT:
				_problem("bounce:%s" % n.npc_name, "%s keeps walking back into the storm (%d times in %ds)" % [
					n.npc_name, recent.size(), BOUNCE_WINDOW], [n], true)

## Not while fighting (a fight holds them in place, shuffling), nor once the
## storm's left too little safe ground to go anywhere.
func _check_pacing(living: Array) -> void:
	var storm: Storm = main.storm
	if _maze_cells < 0:
		_maze_cells = main.world.maze_cell_count()
	if _maze_cells - storm.unsafe.size() < PACING_MIN_SAFE_CELLS or storm.is_closed():
		return
	for n in living:
		if not n.is_party_leader or n.finished or n.is_in_combat():
			_steps.erase(n)
			continue
		var steps: Array = _steps.get(n, [])
		if steps.is_empty() or steps[-1][1] != n.cell_pos:
			steps.append([t, n.cell_pos])
		steps = steps.filter(func(step): return t - step[0] < PACING_SECONDS)
		_steps[n] = steps
		if steps.size() < PACING_MOVES or t < PACING_SECONDS:
			continue
		var cells := {}
		for step in steps:
			cells[step[1]] = true
		if cells.size() <= PACING_CELLS:
			_problem("pacing:%s" % n.npc_name, "%s has paced back and forth over %s for %ds" % [
				n.npc_name, cells.keys(), PACING_SECONDS], [n], true)

## Whether `n` stepped onto its cell this frame.
func _moved_last(n: NpcAgent) -> bool:
	var steps: Array = _steps.get(n, [])
	return steps.is_empty() or steps[-1][1] != n.cell_pos or steps[-1][0] == t

# ================================ Reporting ===============================

## Reports a problem once per `key`, with the recent history of `involved`
## -- as a LOOP line, not counted against the run, if it's `just_a_loop`.
func _problem(key: String, text: String, involved: Array, just_a_loop: bool = false) -> void:
	if _reported.has(key):
		return
	_reported[key] = true
	if not just_a_loop:
		problems += 1
	print("%s seed=%d speed=x%d t=%.1f: %s" % ["LOOP" if just_a_loop else "PROBLEM", game_seed, int(Engine.time_scale), t, text])
	for n in involved:
		if not is_instance_valid(n):
			continue
		print("  %s:" % n.npc_name)
		for line in _history.get(n, []):
			print("    ", line)

func _note_history(n: NpcAgent) -> void:
	var line := "cell=%s icon=%s moving=%s sliding=%s leader=%s pack=%s pvp=%s hp=%d/%d action='%s' party=%s" % [
		n.cell_pos, _icon_cell(n), n.is_moving, n.is_sliding(), n.is_party_leader, n.in_pack_combat,
		n.in_pvp_combat, n.stats.hp, n.stats.max_hp, n.current_action, n.party.map(func(m): return m.npc_name)]
	var lines: Array = _history.get(n, [])
	if lines.is_empty() or not lines[-1].ends_with(line):
		lines.append("t=%.2f %s" % [t, line])
		if lines.size() > HISTORY_LINES:
			lines.pop_front()
	_history[n] = lines

func _icon_cell(n: NpcAgent) -> Vector2i:
	var p: Vector2 = n.position - n.party_offset
	return Vector2i(floori(p.x / n.cell_size), floori(p.y / n.cell_size))

## Steps apart, king's-move style (diagonals count as one).
static func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
