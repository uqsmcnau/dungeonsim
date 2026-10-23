extends SceneTree

## Balance report: plays one whole game headless and prints a line of what
## happened in it -- who won and how fast, what killed everyone, how many
## mid boss parties fell, the silver and gold chests that dropped, silver
## shop visits, the best gear anyone wore, the levels reached -- as
## "BALANCE {json}". With --summarise=FILE instead, reads those lines back
## from FILE and prints the averages over all the games, as a table.
## tools/balance.sh does both: plays a batch of games side by side, then
## sums them up.
##
## One game, from the project folder:
##   godot --headless --path . --fixed-fps 60 --time-scale 10 -s tools/balance.gd -- --seed=7
## Options (after the --): --seed=N (default 1), --seconds=N (game seconds
## before calling it a day; default 700, past the storm closing).

var main: GameManager
var game_seed := 1
var max_seconds := 700.0
var t := 0.0
## The mid boss rooms, by cell: the leader's kind's name.
var _mid_boss_kinds: Dictionary = {}
## Every silver or gold chest seen, by instance id: its rarity.
var _chests: Dictionary = {}
## Party leaders' silver shop visits, as "name@cell" -> the time they began.
var _shop_visits: Dictionary = {}
var _shopping: Dictionary = {}
## Each character's best rarity of gear worn at any point.
var _best_gear: Dictionary = {}
var _frames_to_quit := 5

## The bosses whose parties count as one cause of death (see killer_kind).
const BOSS_PARTIES := {
	"the Dragon": "the Dragon's party",
	"an Ogre Warlord": "Ogre Warlords' parties",
	"an Orc Chieftain": "Orc Chieftains' parties",
}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--summarise="):
			_summarise(arg.get_slice("=", 1))
			quit()
			return
		if arg.begins_with("--seed="):
			game_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--seconds="):
			max_seconds = float(arg.get_slice("=", 1))
	main = load("res://scenes/Main.tscn").instantiate()
	main.game_seed = game_seed
	root.add_child(main)

func _process(delta: float) -> bool:
	if main == null:
		_frames_to_quit -= 1
		if _frames_to_quit <= 0:
			quit()
		return false
	t += delta
	if _mid_boss_kinds.is_empty():
		for cell in main.mid_boss_cells:
			_mid_boss_kinds[cell] = main.enemy_map[cell].kind.name
	_watch_chests()
	_watch_shops()
	_watch_gear()
	var living: Array = main.npcs.filter(func(n): return not n.dead)
	if t >= max_seconds or main.winner != null or living.is_empty():
		print("BALANCE " + JSON.stringify(_report(living)))
		main.free()
		main = null
	return false

func _watch_chests() -> void:
	for cell in main.chest_map:
		var chest = main.chest_map[cell]
		if is_instance_valid(chest) and chest.rarity != ItemCatalog.RARITY_BRONZE:
			_chests[chest.get_instance_id()] = chest.rarity

func _watch_shops() -> void:
	for npc in main.npcs:
		if not npc.is_party_leader:
			continue
		var at_silver: bool = npc.current_action == "Shopping" and main.shop_map.get(npc.cell_pos) == ItemCatalog.RARITY_SILVER
		if at_silver and not _shopping.get(npc, false):
			_shop_visits["%s@%s@%.0f" % [npc.npc_name, npc.cell_pos, t]] = true
		_shopping[npc] = at_silver

func _watch_gear() -> void:
	var rank := {ItemCatalog.RARITY_BRONZE: 1, ItemCatalog.RARITY_SILVER: 2, ItemCatalog.RARITY_GOLD: 3}
	for npc in main.npcs:
		for slot in npc.stats.equipped:
			for item_name in npc.stats.equipped[slot]:
				var rarity: String = ItemCatalog.find(item_name).rarity
				if rank[rarity] > rank.get(_best_gear.get(npc.npc_name, ""), 0):
					_best_gear[npc.npc_name] = rarity

func _report(living: Array) -> Dictionary:
	# main.npcs is only the living; the fallen each have a gravestone.
	var everyone: Array = main.npcs + main.graves.keys()
	var deaths := {}
	for npc in main.graves:
		var cause := killer_kind(npc.killed_by)
		deaths[cause] = deaths.get(cause, 0) + 1
	var beaten := {}
	for cell in _mid_boss_kinds:
		if not main.enemy_map.has(cell):
			beaten[_mid_boss_kinds[cell]] = beaten.get(_mid_boss_kinds[cell], 0) + 1
	var levels: Array = everyone.map(func(n): return n.stats.level)
	return {
		"seed": game_seed, "speed": int(Engine.time_scale), "seconds": snappedf(t, 1.0),
		"won": main.winner != null, "alive": living.size(), "deaths": deaths, "mid_bosses_beaten": beaten,
		"silver_chests": _chests.values().count(ItemCatalog.RARITY_SILVER),
		"gold_chests": _chests.values().count(ItemCatalog.RARITY_GOLD),
		"silver_shop_visits": _shop_visits.size(),
		"wore_silver": _best_gear.values().count(ItemCatalog.RARITY_SILVER),
		"wore_gold": _best_gear.values().count(ItemCatalog.RARITY_GOLD),
		"average_level": snappedf(levels.reduce(func(a, b): return a + b, 0) / float(levels.size()), 0.1),
	}

## What a character's killer (NpcAgent.killed_by) was, broadly: the storm,
## another player ("Name (Lv.5 Good)"), the Dragon's party, a mid boss's
## party (its leader, "an Orc Chieftain (Lv.6)", or a guard, "a Bat (Lv.3),
## guarding an Orc Chieftain"), or a monster roaming the maze.
static func killer_kind(killed_by: String) -> String:
	if killed_by == "the storm":
		return "the storm"
	for boss in BOSS_PARTIES:
		if killed_by.begins_with(boss + " (") or killed_by.ends_with("guarding " + boss):
			return BOSS_PARTIES[boss]
	if RegEx.create_from_string("\\(Lv\\.\\d+ (Good|Evil|Neutral)\\)").search(killed_by) != null:
		return "other players"
	return "maze monsters"

# ================================ Summing up ==============================

func _summarise(path: String) -> void:
	var games: Array = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("No such file: ", path)
		return
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("BALANCE "):
			games.append(JSON.parse_string(line.trim_prefix("BALANCE ")))
	if games.is_empty():
		print("No games to sum up.")
		return
	var n := float(games.size())
	var won: Array = games.filter(func(g): return g["won"])
	var lengths: Array = won.map(func(g): return g["seconds"])
	print("Balance: %d games, at x%d" % [games.size(), games[0]["speed"]])
	print("  Won:                 %d of %d (%d%%)%s" % [won.size(), games.size(), roundi(won.size() / n * 100.0),
		"" if lengths.is_empty() else ", in %d-%ds (average %ds)" % [lengths.min(), lengths.max(), _average(lengths)]])
	print("  Players left:        %.1f on average (%d-%d)" % [
		_average(games.map(func(g): return g["alive"])), games.map(func(g): return g["alive"]).min(),
		games.map(func(g): return g["alive"]).max()])
	print("  Deaths, per game:")
	for cause in _keys_of(games, "deaths"):
		print("    %-25s %.1f" % [cause, _average(games.map(func(g): return g["deaths"].get(cause, 0)))])
	print("  Mid bosses beaten, per game:")
	for kind_name in ["Orc Chieftain", "Ogre Warlord"]:
		var count: int = WorldBuilder.CHIEFTAIN_COUNT if kind_name == "Orc Chieftain" else WorldBuilder.WARLORD_COUNT
		print("    %-25s %.1f of %d" % [kind_name, _average(games.map(func(g): return g["mid_bosses_beaten"].get(kind_name, 0))), count])
	print("  Chests, per game:    %.1f silver, %.1f gold" % [
		_average(games.map(func(g): return g["silver_chests"])), _average(games.map(func(g): return g["gold_chests"]))])
	print("  Silver shop visits:  %.1f per game" % _average(games.map(func(g): return g["silver_shop_visits"])))
	print("  Players who wore:    %.1f silver at best, %.1f gold, per game" % [
		_average(games.map(func(g): return g["wore_silver"])), _average(games.map(func(g): return g["wore_gold"]))])
	print("  Average level:       %.1f at the end" % _average(games.map(func(g): return g["average_level"])))

static func _average(values: Array) -> float:
	return 0.0 if values.is_empty() else values.reduce(func(a, b): return a + b, 0.0) / float(values.size())

## Every key of `field` across all `games`, sorted.
static func _keys_of(games: Array, field: String) -> Array:
	var keys := {}
	for g in games:
		for k in g[field]:
			keys[k] = true
	var result := keys.keys()
	result.sort()
	return result
