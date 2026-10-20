class_name BattleWindow
extends Control

## The battle window, bottom left: the selected character's party and
## whoever they're fighting, drawn as a Final Fantasy-style battle screen --
## the party lined up on the left, the monsters (or the other party) on the
## right, and the blue boxes below listing everyone with their HP and MP.
##
## Each blow, spell and heal of a fight (NpcAgent.combat_event; see
## GroupCombat._report) is queued and played out in turn: the attacker steps
## forward, spells fly, numbers pop up over whoever's hit, HP counts down as
## the blows land, monsters dissolve and fallen party members lie where they
## fell. Between fights the party marches along while they're on the move
## (the scenery scrolling past) and otherwise just stands there, with what
## they're up to in the box below.
##
## GameManager says who's in the scene every frame (show_fight) and hands
## over the events (play). Everything drawn is a snapshot taken from those
## -- names, colours, HP -- so a monster can still be shown dissolving after
## the game has freed it. Runs with the game: pausing freezes it mid-blow.

enum Side { PARTY, FOES }

const FIELD_HEIGHT := 200.0
## Where the back wall meets the floor. Everyone stands below it, and the
## further up the floor (the further back) they stand, the smaller they're
## drawn (see _depth_of).
const FLOOR_TOP := FIELD_HEIGHT * 0.42
const FAR_SCALE := 0.8
## Seconds between one action and the next. A whole turn's actions (one per
## fighter, every second) are squeezed closer together when they back up.
const ACTION_GAP := 0.3
const MIN_ACTION_GAP := 0.08
const LUNGE_SECONDS := 0.3
const LUNGE_DISTANCE := 16.0
const HIT_FLASH_SECONDS := 0.3
const POPUP_SECONDS := 0.9
const SPELL_SECONDS := 0.25
const DISSOLVE_SECONDS := 0.7
const ENTER_SECONDS := 0.4
const LEAVE_SECONDS := 0.5
const RUN_SECONDS := 1.0
const HOP_SECONDS := 1.0
const CAPTION_SECONDS := 0.9
const BANNER_SECONDS := 2.0
## How long a party member who fell stays lying there once the fight's over.
const FALLEN_LINGER_SECONDS := 2.0

## Where each spot on the field is: the party's from the left edge, the
## foes' from the right, all standing on the floor. The party's first spot,
## front and centre, is the leader's (see _sync_side); the others fan out
## above and below, a step further back each time.
const PARTY_SPOTS := [Vector2(104, 124), Vector2(88, 98), Vector2(88, 150), Vector2(72, 72), Vector2(72, 176)]
const FOE_SPOTS := [Vector2(100, 112), Vector2(150, 72), Vector2(150, 152), Vector2(50, 72), Vector2(50, 152), Vector2(200, 112)]
const FIGURE_SCALE := 1.5
## On the move between fights: the party marches on the spot while the
## floor and the pillars along the back wall scroll past. Steps come a
## frame or two apart, so walking carries on this long after the last one.
const WALK_HOLD_SECONDS := 0.3
const WALK_SPEED := 70.0
const STRIDES_PER_SECOND := 1.6

const SPELL_NAMES := {"fireball": "Fireball", "spark": "Spark", "recover": "Recover", "potion_hp": "Health Potion"}
const BOX_COLOR := Color(0.12, 0.16, 0.48)
const BOX_EDGE := Color(0.85, 0.88, 1.0)
const TEXT_COLOR := Color(1, 1, 1)
const LOW_HP_COLOR := Color(1.0, 0.85, 0.2)
const KO_COLOR := Color(1.0, 0.35, 0.35)
const HEAL_COLOR := Color(0.45, 1.0, 0.5)
const CRIT_COLOR := Color(1.0, 0.85, 0.2)
const MISS_COLOR := Color(0.75, 0.75, 0.8)

## Everyone in the scene, by instance id -- see _new_fighter.
var fighters: Dictionary = {}
## Numbers floating over whoever was hit or healed: {text, color, pos, t}
## (t counts up from a negative delay).
var popups: Array = []
## The spell name (or the like) shown at the top while it's cast.
var caption := ""
## "Victory!", "Escaped!" and the like, across the middle.
var banner := ""
## What the party's doing, for the box below when there's no fight.
var status := ""
## How many blows, spells and heals have been played out so far.
var actions_played := 0
## Whether the party's shown on the move (see show_fight).
var walking := false
var _walk_hold := 0.0
## How far they've walked, in seconds of walking -- drives the strides and
## the scrolling scenery.
var _walk_phase := 0.0
var _time := 0.0
var _queue: Array = []
var _next_action_in := 0.0
var _spells: Array = []
var _caption_left := 0.0
var _banner_left := 0.0
## A fight in the window: foes showing, or blows still to play.
var _in_fight := false
var _foes_defeated := 0
var _party_escaped := false
## Set by _reset: whoever's added next appears at once, without walking in.
var _fresh := true
## The ids GameManager listed last time, either side (see show_fight). One
## who's fallen but still listed -- the selected character -- stays.
var _listed: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# ============================== Who's there ===============================

## Who's in the scene right now: `party` (the selected character's party,
## its leader first, any of them fallen included) and `foes` (whoever they're fighting, or
## nobody), plus `status_text`, what the party's up to, and `on_the_move`,
## whether they're taking a step right now. A different party starts the
## scene over; otherwise newcomers walk in, and foes who've gone (without
## being seen to fall) walk off -- once their part in any blows still to be
## played out is over.
func show_fight(party: Array, foes: Array, status_text: String, on_the_move: bool = false) -> void:
	status = status_text
	if on_the_move:
		_walk_hold = WALK_HOLD_SECONDS
	if party.is_empty() or not _shows_any(party, Side.PARTY):
		_reset()
	_listed.clear()
	for node in party + foes:
		_listed[node.get_instance_id()] = true
	_sync_side(party, Side.PARTY)
	_sync_side(foes, Side.FOES)
	_fresh = false
	if not foes.is_empty() and not _in_fight:
		_in_fight = true
		_foes_defeated = 0
		_party_escaped = false
	queue_redraw()

func _shows_any(nodes: Array, side: int) -> bool:
	for node in nodes:
		var f: Dictionary = fighters.get(node.get_instance_id(), {})
		if not f.is_empty() and f["side"] == side:
			return true
	return false

func _reset() -> void:
	fighters.clear()
	popups.clear()
	_spells.clear()
	_queue.clear()
	caption = ""
	banner = ""
	_in_fight = false
	_fresh = true

func _sync_side(nodes: Array, side: int) -> void:
	var listed: Dictionary = {}
	for node in nodes:
		var id: int = node.get_instance_id()
		listed[id] = true
		if not fighters.has(id):
			fighters[id] = _new_fighter(node, side)
			fighters[id]["slot"] = _free_slot(side)
	if side == Side.PARTY and not nodes.is_empty():
		_put_in_front(fighters[nodes[0].get_instance_id()])
	var pending := _pending_ids()
	for id in fighters.keys():
		var f: Dictionary = fighters[id]
		if f["side"] != side or listed.has(id) or pending.has(id):
			continue
		if f["ko"] or f["dissolve"] >= 0.0 or f["leave"] >= 0.0:
			continue  # fallen (they lie where they fell), or already on their way
		if side == Side.PARTY:
			fighters.erase(id)  # left the party
		else:
			f["leave"] = LEAVE_SECONDS
	if _queue.is_empty():
		for node in nodes:
			_take_stats(fighters[node.get_instance_id()], node)

## The first spot on `side` nobody's standing in. Everyone keeps the spot
## they were given for as long as they're in the scene, as in the games --
## no shuffling up when someone falls.
func _free_slot(side: int) -> int:
	var taken: Dictionary = {}
	for f in fighters.values():
		if f["side"] == side and f.has("slot"):
			taken[f["slot"]] = true
	var slot := 0
	while taken.has(slot):
		slot += 1
	return slot

## Gives the party's leader the front-and-centre spot (the first), swapping
## with whoever had it -- a new leader steps up, and a fallen one is left
## lying where the new one was.
func _put_in_front(leader: Dictionary) -> void:
	if leader["slot"] == 0:
		return
	for f in fighters_on(Side.PARTY):
		if f["slot"] == 0:
			f["slot"] = leader["slot"]
	leader["slot"] = 0

## A snapshot of `node` (a player or a monster) as it joins the scene.
func _new_fighter(node: Node, side: int) -> Dictionary:
	var f := {
		"id": node.get_instance_id(), "side": side, "ko": false,
		"color": node.visual.color, "level": node.stats.level,
		"lunge": 0.0, "flash": 0.0, "glow": 0.0, "dissolve": -1.0,
		"enter": 0.0 if _fresh or (node is NpcAgent and node.dead) else ENTER_SECONDS,
		"leave": -1.0, "linger": -1.0,
		"run": 0.0, "hop": 0.0,
	}
	if node is NpcAgent:
		f["kind"] = "player"
		f["name"] = node.npc_name
		f["ko"] = node.dead
	else:
		f["kind"] = "boss" if node.is_boss else ("mini_boss" if node.is_mini_boss else "monster")
		f["name"] = {"boss": "Boss", "mini_boss": "Mini Boss", "monster": "Monster"}[f["kind"]]
	_take_stats(f, node)
	return f

func _take_stats(f: Dictionary, node: Node) -> void:
	if node is NpcAgent:
		f["ko"] = node.dead
		f["look"] = look_of(node.stats)
	f["hp"] = maxi(0, node.stats.hp)
	f["max_hp"] = node.stats.max_hp
	f["mp"] = node.stats.mp
	f["max_mp"] = node.stats.max_mp

## How a player's figure looks in the gear they're wearing (see
## _draw_figure):
##   weapon -- "steel_sword", "iron_sword", or "" for bare hands;
##   off_hand -- "silver_shield", "shield", "tome", a second "iron_sword"
##     (two swords, nothing else), or "";
##   armor -- "chainmail", "leather" or "";
##   helmet, boots, amulet, ring -- whether they're wearing one.
static func look_of(stats: NpcStats) -> Dictionary:
	var hands: Array = stats.equipped_in("hand")
	var weapon := ""
	if hands.has("Steel Sword"):
		weapon = "steel_sword"
	elif hands.has("Iron Sword"):
		weapon = "iron_sword"
	var off_hand := ""
	if hands.has("Silver Shield"):
		off_hand = "silver_shield"
	elif hands.has("Shield"):
		off_hand = "shield"
	elif hands.has("Arcane Tome"):
		off_hand = "tome"
	elif hands.has("Steel Sword") and hands.has("Iron Sword"):
		off_hand = "iron_sword"
	var armor := ""
	if stats.equipped_in("armor").has("Chainmail"):
		armor = "chainmail"
	elif not stats.equipped_in("armor").is_empty():
		armor = "leather"
	var accessories: Array = stats.equipped_in("accessory")
	return {
		"weapon": weapon, "off_hand": off_hand, "armor": armor,
		"helmet": not stats.equipped_in("helmet").is_empty(),
		"boots": not stats.equipped_in("feet").is_empty(),
		"amulet": accessories.has("Sage's Amulet"),
		"ring": accessories.has("Silver Ring"),
	}

func _pending_ids() -> Dictionary:
	var ids: Dictionary = {}
	for ev in _queue:
		ids[ev.get("actor_id", 0)] = true
		ids[ev.get("target_id", 0)] = true
	return ids

## `node`'s snapshot, or an empty dictionary if it isn't in the scene.
func fighter_of(node: Node) -> Dictionary:
	return fighters.get(node.get_instance_id(), {})

func fighters_on(side: int) -> Array:
	var result: Array = []
	for f in fighters.values():
		if f["side"] == side:
			result.append(f)
	result.sort_custom(func(a, b): return a["slot"] < b["slot"])
	return result

# ================================ Events ==================================

## Queues one event of a fight (see GroupCombat._report) to be played out,
## if it involves anyone in the scene.
func play(event: Dictionary) -> void:
	var ev := event.duplicate()
	ev["actor_id"] = event["actor"].get_instance_id()
	ev["target_id"] = event["target"].get_instance_id() if event.has("target") else 0
	ev.erase("actor")
	ev.erase("target")
	if not fighters.has(ev["actor_id"]) and not fighters.has(ev["target_id"]):
		return
	_queue.append(ev)
	_in_fight = true

func _process(delta: float) -> void:
	advance(delta)

## Moves everything on by `delta` seconds: the next queued blow when its
## turn comes, and every animation.
func advance(delta: float) -> void:
	_next_action_in -= delta
	if _next_action_in <= 0.0 and not _queue.is_empty():
		_act(_queue.pop_front())
		_next_action_in = clampf(0.9 / (_queue.size() + 1), MIN_ACTION_GAP, ACTION_GAP)
	_time += delta
	_walk_hold = maxf(0.0, _walk_hold - delta)
	walking = _walk_hold > 0.0 and fighters_on(Side.FOES).is_empty() and not fighters_on(Side.PARTY).is_empty()
	if walking:
		_walk_phase += delta
	_animate(delta)
	_check_fight_over()
	queue_redraw()

func _act(ev: Dictionary) -> void:
	var actor: Dictionary = fighters.get(ev["actor_id"], {})
	if ev["kind"] == "escape":
		if actor.is_empty():
			return
		if actor["side"] == Side.PARTY:
			_party_escaped = true
			_show_banner("Escaped!")
			for f in fighters_on(Side.PARTY):
				if not f["ko"]:
					f["run"] = RUN_SECONDS
		else:
			_show_caption("%s fled!" % actor["name"])
		return

	actions_played += 1
	var target: Dictionary = fighters.get(ev["target_id"], {})
	var action: String = ev["action"]
	var healing := action == "recover" or action == "potion_hp"
	if SPELL_NAMES.has(action):
		_show_caption(SPELL_NAMES[action])
	if not actor.is_empty():
		actor["mp"] = ev["actor_mp"]
		if healing:
			actor["glow"] = SPELL_SECONDS * 2.0
		else:
			actor["lunge"] = LUNGE_SECONDS
	if target.is_empty():
		return
	var delay := 0.0
	if action == "fireball" or action == "spark":
		delay = SPELL_SECONDS
		if not actor.is_empty():
			_spells.append({"kind": action, "from": _place_of(actor), "to": _place_of(target), "t": 0.0})
	elif not healing:
		delay = LUNGE_SECONDS * 0.5
	target["hp"] = ev["target_hp"]
	target["max_hp"] = ev["target_max_hp"]
	var text := str(ev["amount"])
	var color := TEXT_COLOR
	if ev["missed"]:
		text = "Miss"
		color = MISS_COLOR
	elif healing:
		text = "+%d" % ev["amount"]
		color = HEAL_COLOR
	elif ev["crit"]:
		text = "%d!" % ev["amount"]
		color = CRIT_COLOR
	else:
		target["flash"] = HIT_FLASH_SECONDS + delay
	# Over the target's body, stacked above any number of theirs still showing.
	var pos := _home_of(target) + Vector2(0, -_height_of(target) * 0.2)
	pos.y -= 16.0 * popups.filter(func(p): return p["target_id"] == target["id"] and p["t"] < POPUP_SECONDS * 0.5).size()
	popups.append({"text": text, "color": color, "pos": pos, "t": -delay, "target_id": target["id"]})
	if ev["killed"]:
		# Monsters dissolve; players fall and lie where they fell.
		if target["kind"] == "player":
			target["ko"] = true
		else:
			target["dissolve"] = DISSOLVE_SECONDS + delay
		if target["side"] == Side.FOES:
			_foes_defeated += 1

func _show_caption(text: String) -> void:
	caption = text
	_caption_left = CAPTION_SECONDS

func _show_banner(text: String) -> void:
	banner = text
	_banner_left = BANNER_SECONDS

func _animate(delta: float) -> void:
	for id in fighters.keys():
		var f: Dictionary = fighters[id]
		for key in ["lunge", "flash", "glow", "enter", "run", "hop"]:
			f[key] = maxf(0.0, f[key] - delta)
		if f["dissolve"] >= 0.0:
			f["dissolve"] -= delta
			if f["dissolve"] < 0.0:
				fighters.erase(id)
				continue
		if f["leave"] >= 0.0:
			f["leave"] -= delta
			if f["leave"] < 0.0:
				fighters.erase(id)
				continue
		if f["linger"] >= 0.0:
			f["linger"] -= delta
			if f["linger"] < 0.0:
				fighters.erase(id)
	for p in popups:
		p["t"] += delta
	popups = popups.filter(func(p): return p["t"] < POPUP_SECONDS)
	for s in _spells:
		s["t"] += delta
	_spells = _spells.filter(func(s): return s["t"] < SPELL_SECONDS + 0.2)
	_caption_left = maxf(0.0, _caption_left - delta)
	if _caption_left <= 0.0:
		caption = ""
	_banner_left = maxf(0.0, _banner_left - delta)
	if _banner_left <= 0.0:
		banner = ""

## Once the last foe's gone (or fallen) and every blow's been played: a
## victory if they were beaten (the party hops for joy), and the fallen on
## both sides are cleared away a little later.
func _check_fight_over() -> void:
	if not _in_fight or not _queue.is_empty():
		return
	if fighters_on(Side.FOES).any(func(f): return not f["ko"]):
		return
	_in_fight = false
	var standing := fighters_on(Side.PARTY).filter(func(f): return not f["ko"])
	if standing.is_empty():
		if not fighters.is_empty():
			_show_banner("Defeated...")
	elif _foes_defeated > 0 and not _party_escaped:
		_show_banner("Victory!")
		for f in standing:
			f["hop"] = HOP_SECONDS
	for f in fighters.values():
		if f["ko"] and f["linger"] < 0.0 and not _listed.has(f["id"]):
			f["linger"] = FALLEN_LINGER_SECONDS
	_foes_defeated = 0
	_party_escaped = false

# ================================ Layout ==================================

## Where `f` stands in the field, before any animation: its spot (see
## _free_slot), the first in the middle and the rest around it.
func _home_of(f: Dictionary) -> Vector2:
	var slot: int = f["slot"]
	if f["side"] == Side.PARTY:
		return PARTY_SPOTS[slot % PARTY_SPOTS.size()]
	if f["kind"] == "boss":
		return Vector2(size.x - 120.0, 112.0)
	var spot: Vector2 = FOE_SPOTS[slot % FOE_SPOTS.size()]
	return Vector2(size.x - spot.x, spot.y)

## Which way `f` faces: the party right, towards the foes; the foes left.
func _facing_of(f: Dictionary) -> float:
	return 1.0 if f["side"] == Side.PARTY else -1.0

## Where `f` is drawn right now, animations included.
func _place_of(f: Dictionary) -> Vector2:
	var p := _home_of(f)
	var facing := _facing_of(f)
	if f["lunge"] > 0.0:
		p.x += sin(PI * (1.0 - f["lunge"] / LUNGE_SECONDS)) * LUNGE_DISTANCE * facing
	if f["enter"] > 0.0:
		p.x -= facing * 80.0 * f["enter"] / ENTER_SECONDS
	if f["leave"] >= 0.0:
		p.x -= facing * 100.0 * (1.0 - f["leave"] / LEAVE_SECONDS)
	if f["run"] > 0.0:
		# Turn tail and dash off the way they came, then come back.
		p.x -= facing * sin(PI * (1.0 - f["run"] / RUN_SECONDS)) * 60.0
	if f["hop"] > 0.0:
		p.y -= absf(sin(f["hop"] / HOP_SECONDS * TAU * 1.5)) * 8.0
	if f["side"] == Side.PARTY and not f["ko"]:
		if walking:
			p.y -= absf(sin(_stride_of(f) * PI)) * 2.5  # a bob in step
		else:
			p.y -= (sin(_time * 2.0 + f["slot"]) + 1.0) * 0.4  # breathing
	return p

## Where `f` is in its stride while walking, in strides (each member a
## little out of step with the next).
func _stride_of(f: Dictionary) -> float:
	return _walk_phase * STRIDES_PER_SECOND + f["slot"] * 0.37

## How much smaller `f` is drawn for standing further back: FAR_SCALE at
## the back wall, full size at the front of the floor. Taken from its spot,
## so it doesn't shrink and grow as it bobs.
func _depth_of(f: Dictionary) -> float:
	var k := clampf((_home_of(f).y - FLOOR_TOP) / (FIELD_HEIGHT - FLOOR_TOP), 0.0, 1.0)
	return lerpf(FAR_SCALE, 1.0, k)

## Where `f`'s feet touch the floor, at its spot.
func _feet_of(f: Dictionary) -> float:
	var below := 14.0 * FIGURE_SCALE if f["kind"] == "player" else _height_of(f) * 0.6
	return _home_of(f).y + below * _depth_of(f)

func _height_of(f: Dictionary) -> float:
	match f["kind"]:
		"player":
			return 22.0 * FIGURE_SCALE
		"boss":
			return 64.0
		"mini_boss":
			return 44.0
	return 30.0

# ================================ Drawing =================================

func _draw() -> void:
	_draw_backdrop()
	var drawn := fighters.values()
	drawn.sort_custom(func(a, b): return _place_of(a).y < _place_of(b).y)
	for f in drawn:
		_draw_fighter(f)
	for s in _spells:
		_draw_spell(s)
	var font := ThemeDB.fallback_font
	for p in popups:
		if p["t"] < 0.0:
			continue
		var k: float = p["t"] / POPUP_SECONDS
		var rise := minf(p["t"] / 0.25, 1.0) * 14.0
		var color: Color = p["color"]
		color.a = 1.0 if k < 0.7 else (1.0 - k) / 0.3
		_draw_text_outlined(p["pos"] - Vector2(0, rise), p["text"], 16, color, HORIZONTAL_ALIGNMENT_CENTER)
	if caption != "":
		var w := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 24.0
		_draw_box(Rect2((size.x - w) / 2.0, 6.0, w, 24.0))
		_draw_text(Vector2(size.x / 2.0, 23.0), caption, 14, TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	if banner != "":
		_draw_text_outlined(Vector2(size.x / 2.0, FIELD_HEIGHT * 0.5), banner, 26, Color(1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	_draw_menus()
	draw_rect(Rect2(Vector2.ZERO, size), BOX_EDGE, false, 2.0)

## A dark dungeon hall: a gradient wall lined with torch-lit pillars, and a
## stone floor running off towards the back. On the move, the floor and
## (more slowly, being further off) the pillars scroll past.
func _draw_backdrop() -> void:
	var bands := 12
	var wall_bottom := FLOOR_TOP
	var scroll := _walk_phase * WALK_SPEED
	for i in range(bands):
		var y0 := wall_bottom * i / bands
		var c := Color(0.05, 0.05, 0.12).lerp(Color(0.13, 0.1, 0.22), float(i) / bands)
		draw_rect(Rect2(0, y0, size.x, wall_bottom / bands + 1.0), c)
	var pillar_gap := 110.0
	var x := -fmod(scroll * 0.5, pillar_gap)
	while x < size.x + pillar_gap:
		draw_rect(Rect2(x, 0, 16.0, wall_bottom), Color(0.09, 0.07, 0.15))
		draw_rect(Rect2(x + 16.0, 0, 3.0, wall_bottom), Color(0.06, 0.05, 0.1))
		var flicker := 1.0 + 0.2 * sin(_time * 11.0 + x * 0.1)
		draw_circle(Vector2(x + 8.0, wall_bottom * 0.45), 6.0 * flicker, Color(1.0, 0.5, 0.1, 0.25))
		draw_circle(Vector2(x + 8.0, wall_bottom * 0.45), 2.5 * flicker, Color(1.0, 0.8, 0.3))
		x += pillar_gap
	draw_rect(Rect2(0, wall_bottom, size.x, FIELD_HEIGHT - wall_bottom), Color(0.17, 0.14, 0.2))
	var vanish := Vector2(size.x / 2.0, wall_bottom - 60.0)
	var line := Color(0.24, 0.2, 0.28)
	var shift := -fmod(scroll, 70.0)
	for i in range(-7, 8):
		var bottom := Vector2(size.x / 2.0 + i * 70.0 + shift, FIELD_HEIGHT)
		var top := vanish.lerp(bottom, (wall_bottom - vanish.y) / (FIELD_HEIGHT - vanish.y))
		draw_line(top, bottom, line, 1.0)
	var y := wall_bottom
	var gap := 6.0
	while y < FIELD_HEIGHT:
		draw_line(Vector2(0, y), Vector2(size.x, y), line, 1.0)
		y += gap
		gap *= 1.35

func _draw_fighter(f: Dictionary) -> void:
	var p := _place_of(f)
	var color: Color = f["color"]
	var alpha := 1.0
	if f["dissolve"] >= 0.0:
		alpha = clampf(f["dissolve"] / DISSOLVE_SECONDS, 0.0, 1.0)
		color = color.lerp(Color(1, 0.3, 0.5), 1.0 - alpha)
	if f["leave"] >= 0.0:
		alpha = clampf(f["leave"] / LEAVE_SECONDS, 0.0, 1.0)
	if f["linger"] >= 0.0:
		alpha = clampf(f["linger"] / FALLEN_LINGER_SECONDS * 2.0, 0.0, 1.0)
	# Hit: blink white.
	if f["flash"] > 0.0 and f["flash"] < HIT_FLASH_SECONDS and int(f["flash"] * 24.0) % 2 == 0:
		color = Color.WHITE
	color.a = alpha
	var depth := _depth_of(f)
	# A shadow on the floor underfoot -- staying put while they hop or bob.
	var ground := Vector2(p.x, _feet_of(f))
	draw_set_transform(ground, 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, _height_of(f) * 0.4 * depth, Color(0, 0, 0, 0.35 * alpha))
	draw_set_transform(Vector2.ZERO)
	if f["kind"] == "player":
		var stride := 0.0
		if walking and f["side"] == Side.PARTY:
			stride = sin(_stride_of(f) * TAU)
		draw_set_transform(p, 0.0, Vector2.ONE * FIGURE_SCALE * depth)
		_draw_figure(Vector2.ZERO, color, _facing_of(f) < 0.0, f["ko"], alpha, stride, f.get("look", {}))
		draw_set_transform(Vector2.ZERO)
	else:
		_draw_monster(p, color, f, alpha, depth)
	if f["glow"] > 0.0:
		var k: float = f["glow"] / (SPELL_SECONDS * 2.0)
		for i in range(5):
			var a := TAU * i / 5.0 + k * 4.0
			var spark := p + Vector2(cos(a) * 12.0, -k * 18.0 + sin(a) * 4.0)
			draw_circle(spark, 2.0, Color(HEAL_COLOR, k))

## A little adventurer facing the enemy (the party faces right, a rival
## party left), dressed in whatever they're wearing -- `look`, from look_of:
## sword in the front hand (or bare-fisted), shield or tome in the other,
## armor over their tunic, helmet, boots, amulet and ring. Fallen, they lie
## flat. `stride` (-1 to 1) swings the legs, mid-walk.
func _draw_figure(p: Vector2, color: Color, faces_left: bool, ko: bool, alpha: float, stride: float = 0.0, look: Dictionary = {}) -> void:
	var skin := Color(1.0, 0.85, 0.7, alpha)
	var metal := Color(0.72, 0.74, 0.8, alpha)
	var leather := Color(0.42, 0.26, 0.12, alpha)
	if ko:
		var grey := Color(color.lerp(Color(0.4, 0.4, 0.4), 0.6), alpha)
		draw_rect(Rect2(p.x - 7.0, p.y + 6.0, 16.0, 7.0), grey)
		var head := Vector2(p.x - 11.0 if faces_left else p.x + 13.0, p.y + 9.0)
		draw_circle(head, 4.5, Color(skin.lerp(Color(0.5, 0.5, 0.5), 0.5), alpha))
		if look.get("helmet", false):
			draw_circle(head + Vector2(-2.0 if faces_left else 2.0, 0), 3.0, metal)
		return
	var dir := -1.0 if faces_left else 1.0
	var front_hand := p + Vector2(dir * 5.0, 2.0)
	var back_hand := p + Vector2(-dir * 6.0, 3.0)
	var weapon: String = look.get("weapon", "")
	var off_hand: String = look.get("off_hand", "")

	# Behind the body: a second sword, its tip over the shoulder.
	if off_hand == "iron_sword":
		draw_line(back_hand, p + Vector2(-dir * 9.0, -13.0), metal, 1.8)

	# Legs: one forward, one back, the raised one lifted off the ground --
	# in boots, if they have them.
	var swing := stride * 2.5
	var leg_color := leather if look.get("boots", false) else color.darkened(0.4)
	draw_rect(Rect2(p.x - 5.0 + swing, p.y + 10.0 - maxf(stride, 0.0) * 1.5, 4.0, 4.0), leg_color)
	draw_rect(Rect2(p.x + 1.0 - swing, p.y + 10.0 - maxf(-stride, 0.0) * 1.5, 4.0, 4.0), leg_color)
	if look.get("boots", false):
		draw_rect(Rect2(p.x - 5.5 + swing, p.y + 10.0 - maxf(stride, 0.0) * 1.5, 5.0, 1.0), leather.lightened(0.3))
		draw_rect(Rect2(p.x + 0.5 - swing, p.y + 10.0 - maxf(-stride, 0.0) * 1.5, 5.0, 1.0), leather.lightened(0.3))

	# Body: their tunic, under any armor.
	draw_rect(Rect2(p.x - 6.0, p.y - 3.0, 12.0, 13.0), color)
	match look.get("armor", ""):
		"leather":
			draw_rect(Rect2(p.x - 5.0, p.y - 2.0, 10.0, 9.0), Color(0.55, 0.36, 0.18, alpha))
			draw_rect(Rect2(p.x - 6.0, p.y + 6.0, 12.0, 1.6), leather)
			draw_rect(Rect2(p.x - 1.0, p.y + 5.8, 2.0, 2.0), Color(0.95, 0.8, 0.3, alpha))
		"chainmail":
			draw_rect(Rect2(p.x - 6.0, p.y - 3.0, 12.0, 11.0), metal)
			for row in range(4):
				for col in range(4):
					var link := p + Vector2(-4.5 + col * 3.0 + (row % 2) * 1.5, -1.0 + row * 2.5)
					draw_circle(link, 0.6, Color(0.4, 0.42, 0.48, alpha))
	if look.get("amulet", false):
		draw_line(p + Vector2(-2.5, -3.0), p + Vector2(0, 1.0), Color(0.95, 0.8, 0.3, alpha), 0.6)
		draw_line(p + Vector2(2.5, -3.0), p + Vector2(0, 1.0), Color(0.95, 0.8, 0.3, alpha), 0.6)
		draw_circle(p + Vector2(0, 1.6), 1.6, Color(0.3, 0.8, 1.0, alpha))

	# Head, under any helmet: a steel cap with a nose guard.
	draw_circle(p + Vector2(0, -9.0), 5.5, skin)
	var eye_y := -10.0
	if look.get("helmet", false):
		var cap := PackedVector2Array()
		for i in range(9):
			var a := PI + PI * i / 8.0
			cap.append(p + Vector2(0, -9.5) + Vector2(cos(a), sin(a)) * 6.2)
		draw_colored_polygon(cap, metal)
		draw_line(p + Vector2(-6.4, -9.5), p + Vector2(6.4, -9.5), metal.darkened(0.3), 1.2)
		draw_rect(Rect2(p.x + dir * 2.0 - 0.6, p.y - 9.5, 1.2, 3.0), metal.darkened(0.2))
		eye_y = -8.5
	draw_circle(p + Vector2(dir * 2.5, eye_y), 1.2, Color(0.1, 0.1, 0.15, alpha))

	# The back hand: a tome (if there's a sword in the other), a ring.
	if off_hand == "tome" and weapon != "":
		_draw_tome(back_hand + Vector2(-dir * 1.0, -1.0), alpha)
	if look.get("ring", false):
		var glint := back_hand + Vector2(0, 1.0)
		var k := 1.0 + 0.4 * sin(_time * 6.0)
		draw_line(glint - Vector2(1.6 * k, 0), glint + Vector2(1.6 * k, 0), Color(1, 1, 1, alpha), 0.6)
		draw_line(glint - Vector2(0, 1.6 * k), glint + Vector2(0, 1.6 * k), Color(1, 1, 1, alpha), 0.6)

	# The front hand: a sword (steel longer and brighter, with a gilt
	# crossguard), else a tome held out, else a bare fist.
	match weapon:
		"steel_sword":
			_draw_sword(front_hand, front_hand + Vector2(dir * 11.0, -13.0), Color(0.88, 0.95, 1.0, alpha), Color(0.95, 0.78, 0.25, alpha), 2.4)
		"iron_sword":
			_draw_sword(front_hand, front_hand + Vector2(dir * 9.0, -10.0), Color(0.78, 0.78, 0.82, alpha), Color(0.45, 0.3, 0.15, alpha), 2.0)
		_:
			if off_hand == "tome":
				_draw_tome(front_hand + Vector2(dir * 1.5, -2.0), alpha)
			else:
				draw_circle(front_hand, 1.6, skin)

	# A shield, held in front of the body.
	var boss := p + Vector2(dir * 3.5, 3.5)
	match off_hand:
		"shield":
			draw_circle(boss, 4.3, Color(0.55, 0.35, 0.15, alpha))
			draw_arc(boss, 4.3, 0.0, TAU, 16, metal, 0.9)
			draw_circle(boss, 1.1, metal)
		"silver_shield":
			var kite := PackedVector2Array([
				boss + Vector2(-3.6, -4.5), boss + Vector2(3.6, -4.5),
				boss + Vector2(3.6, 0.5), boss + Vector2(0, 5.5), boss + Vector2(-3.6, 0.5),
			])
			draw_colored_polygon(kite, Color(0.84, 0.86, 0.92, alpha))
			kite.append(kite[0])
			draw_polyline(kite, Color(0.55, 0.58, 0.66, alpha), 0.8)
			draw_line(boss + Vector2(0, -3.5), boss + Vector2(0, 3.5), Color(0.25, 0.45, 0.9, alpha), 1.0)
			draw_line(boss + Vector2(-2.5, -1.0), boss + Vector2(2.5, -1.0), Color(0.25, 0.45, 0.9, alpha), 1.0)

func _draw_sword(hilt: Vector2, tip: Vector2, blade: Color, guard: Color, width: float) -> void:
	draw_line(hilt, tip, blade, width)
	var across := (tip - hilt).normalized().orthogonal() * 2.5
	var guard_at := hilt + (tip - hilt).normalized() * 1.5
	draw_line(guard_at - across, guard_at + across, guard, 1.4)

## A purple spellbook with pale page edges.
func _draw_tome(at: Vector2, alpha: float) -> void:
	draw_rect(Rect2(at.x - 2.0, at.y - 2.5, 4.0, 5.0), Color(0.45, 0.2, 0.65, alpha))
	draw_line(at + Vector2(2.0, -2.0), at + Vector2(2.0, 2.0), Color(0.95, 0.92, 0.8, alpha), 0.8)

## A monster like the ones on the map, only bigger and with a face: a
## many-sided blob, glaring towards the party.
func _draw_monster(p: Vector2, color: Color, f: Dictionary, alpha: float, depth: float) -> void:
	var r := _height_of(f) * 0.6 * depth
	if f["dissolve"] >= 0.0:
		r *= 0.8 + 0.2 * alpha
	var points := PackedVector2Array()
	for i in range(10):
		var a := TAU * i / 10.0
		var wobble := 1.0 + 0.08 * sin(a * 3.0)
		points.append(p + Vector2(cos(a), sin(a)) * r * wobble)
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, Color(color.darkened(0.5), alpha), 1.5)
	var eye := Color(1.0, 0.95, 0.3, alpha)
	if f["kind"] == "boss":
		eye = Color(1.0, 0.2, 0.2, alpha)
	elif f["kind"] == "mini_boss":
		eye = Color(0.75, 0.4, 1.0, alpha)
	draw_circle(p + Vector2(-r * 0.35, -r * 0.25), r * 0.14, eye)
	draw_circle(p + Vector2(-r * 0.65, -r * 0.2), r * 0.12, eye)
	draw_line(p + Vector2(-r * 0.25, r * 0.25), p + Vector2(-r * 0.7, r * 0.2), Color(0.1, 0.0, 0.0, alpha), 1.5)

func _draw_spell(s: Dictionary) -> void:
	var k: float = clampf(s["t"] / SPELL_SECONDS, 0.0, 1.0)
	if s["kind"] == "fireball":
		if k < 1.0:
			var at: Vector2 = s["from"].lerp(s["to"], k)
			draw_circle(at, 6.0, Color(1.0, 0.45, 0.1))
			draw_circle(at, 3.0, Color(1.0, 0.9, 0.4))
		else:
			var burst: float = (s["t"] - SPELL_SECONDS) / 0.2
			draw_arc(s["to"], 6.0 + burst * 16.0, 0.0, TAU, 20, Color(1.0, 0.5, 0.1, 1.0 - burst), 3.0)
	else:
		# Spark: a bolt of lightning down onto the target, flickering.
		if int(s["t"] * 30.0) % 2 == 1:
			return
		var top: Vector2 = s["to"] + Vector2(0, -60.0)
		var bolt := PackedVector2Array([top])
		for i in range(1, 6):
			var y := top.y + 60.0 * i / 5.0
			bolt.append(Vector2(top.x + (8.0 if i % 2 == 0 else -8.0) * (1.0 if i < 5 else 0.0), y))
		draw_polyline(bolt, Color(1.0, 1.0, 0.5), 2.5)

## The blue boxes along the bottom: the party's HP and MP on the left, under
## them, and who they're up against (or what they're up to) on the right.
func _draw_menus() -> void:
	var top := FIELD_HEIGHT + 4.0
	var height := size.y - top - 4.0
	var party_w := size.x * 0.62
	var party_box := Rect2(4.0, top, party_w - 6.0, height)
	var foe_box := Rect2(party_w + 2.0, top, size.x - party_w - 6.0, height)
	_draw_box(party_box)
	_draw_box(foe_box)
	var row := 18.0
	var foes := fighters_on(Side.FOES)
	if foes.is_empty():
		var text := status if not fighters.is_empty() else "Select a player to watch their battles."
		_draw_text_wrapped(foe_box.grow(-8.0), text, 13)
	else:
		var y := top + 18.0
		for f in foes:
			if y > top + height - 4.0:
				break
			var name: String = f["name"] if f["kind"] == "player" else "%s Lv.%d" % [f["name"], f["level"]]
			_draw_text(Vector2(foe_box.position.x + 8.0, y), name, 13, MISS_COLOR if f["dissolve"] >= 0.0 or f["ko"] else TEXT_COLOR)
			y += row
	var party := fighters_on(Side.PARTY)
	if not party.is_empty():
		_draw_text(Vector2(party_box.position.x + 100.0, top + 14.0), "HP", 10, MISS_COLOR)
		_draw_text(Vector2(party_box.position.x + 178.0, top + 14.0), "MP", 10, MISS_COLOR)
	var y2 := top + 30.0
	for f in party:
		if y2 > top + height - 4.0:
			break
		var color := TEXT_COLOR
		if f["ko"]:
			color = KO_COLOR
		elif f["hp"] * 4 <= f["max_hp"]:
			color = LOW_HP_COLOR
		var x := party_box.position.x + 8.0
		_draw_text(Vector2(x, y2), f["name"], 13, color)
		_draw_text(Vector2(x + 92.0, y2), "%d/%d" % [f["hp"], f["max_hp"]], 13, color)
		_draw_text(Vector2(x + 170.0, y2), "%d" % f["mp"], 13, Color(0.7, 0.8, 1.0))
		y2 += row

func _draw_box(rect: Rect2) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = BOX_COLOR
	style.border_color = BOX_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	draw_style_box(style, rect)

func _draw_text(pos: Vector2, text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font := ThemeDB.fallback_font
	var width := -1.0
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		width = 300.0
		pos.x -= 150.0
	draw_string(font, pos, text, align, width, font_size, color)

func _draw_text_outlined(pos: Vector2, text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font := ThemeDB.fallback_font
	var width := -1.0
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		width = 300.0
		pos.x -= 150.0
	draw_string_outline(font, pos, text, align, width, font_size, 4, Color(0, 0, 0, color.a))
	draw_string(font, pos, text, align, width, font_size, color)

func _draw_text_wrapped(rect: Rect2, text: String, font_size: int) -> void:
	var font := ThemeDB.fallback_font
	draw_multiline_string(font, rect.position + Vector2(0, font_size), text, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, font_size, 4, TEXT_COLOR)
