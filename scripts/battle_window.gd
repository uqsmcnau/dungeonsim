class_name BattleWindow
extends Control

## The battle window, bottom left: the selected character's party and
## whoever they're fighting, drawn as a Final Fantasy-style battle screen --
## the party lined up on the left, the monsters (or the other party) on the
## right, and the blue boxes below listing everyone with their HP and MP.
##
## Each blow, spell and heal of a fight (a CombatEvent, from
## NpcAgent.combat_event) is queued and played out in turn: the attacker
## steps forward, spells fly, numbers pop up over whoever's hit, HP counts
## down as the blows land, monsters dissolve and fallen party members lie
## where they fell. Between fights the party marches along while they're on
## the move (the scenery scrolling past) and otherwise just stands there,
## with what they're up to in the box below.
##
## GameManager says who's in the scene every frame (show_fight) and hands
## over the events (play). Each figure is a BattleFighter -- a snapshot, so a
## monster can still be shown dissolving after the game has freed it -- and
## BattlePainter does the drawing. Runs with the game: pausing freezes it
## mid-blow.

## A name in the party menu was clicked: select them (see Hud).
signal member_clicked(npc: NpcAgent)

## Where the shopkeeper stands behind the counter, from the right like
## FOE_SPOTS, while the party's at a shop (see `shop`).
const SHOP_SPOT := Vector2(110, 120)

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
## Facing a boss, it stands at the back, and the rest stand at these spots
## (by their slot, the boss having the first) in front of it -- from the
## right, like FOE_SPOTS.
const BOSS_SPOT := Vector2(80, 112)
const BOSS_GUARD_SPOTS := [Vector2(165, 68), Vector2(165, 68), Vector2(165, 156), Vector2(225, 90), Vector2(225, 134)]
## On the move between fights: the party marches on the spot while the
## floor and the pillars along the back wall scroll past. Steps come a
## frame or two apart, so walking carries on this long after the last one.
const WALK_HOLD_SECONDS := 0.3
const WALK_SPEED := 70.0
const STRIDES_PER_SECOND := 1.6

## Everyone in the scene, by instance id.
var fighters: Dictionary = {}
## Numbers floating over whoever was hit or healed: {text, color, pos, t,
## target_id} (t counts up from a negative delay).
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
## CombatEvents still to be played out.
var _queue: Array = []
var _next_action_in := 0.0
## Spells in flight: {kind, from, to, t}.
var _spells: Array = []
var _caption_left := 0.0
var _banner_left := 0.0
## A fight in the window: foes showing, or blows still to play.
var _in_fight := false
var _foes_defeated := 0
var _party_escaped := false
## Set by _reset: whoever's added next appears at once, without walking in.
var _fresh := true
## The rarity of the shop the party's visiting (see NpcAgent.shopping_at),
## or "" -- GameManager sets it along with show_fight. While it's set, the
## shopkeeper stands behind their counter where the foes would, having slid
## in from the right (over ENTER_SECONDS); once it's "" again, they slide
## back out (over LEAVE_SECONDS). A scene just started over (see _reset)
## shows them in place, or not at all, straight away, as it does everyone.
var shop := "":
	set(value):
		if value != "":
			_shop_drawn = value
		if _shop_snaps:
			_shop_in = 1.0 if value != "" else 0.0
			_shop_snaps = false
		shop = value
## The shop on show -- `shop`, or the one just left, sliding out -- or "".
var _shop_drawn := ""
## How far it's slid in: 0 off to the right, 1 in place.
var _shop_in := 0.0
## Set by _reset: the next `shop` is shown straight away, without sliding.
var _shop_snaps := true
## The ids GameManager listed last time, either side (see show_fight). One
## who's fallen but still listed -- the selected character -- stays.
var _listed: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Clicks on the party menu, paused or not: the window itself pauses with
	# the game (its animations stop), so they're caught by a layer that
	# doesn't.
	var clicks := Control.new()
	clicks.name = "MenuClicks"
	clicks.set_anchors_preset(Control.PRESET_FULL_RECT)
	clicks.process_mode = Node.PROCESS_MODE_ALWAYS
	clicks.gui_input.connect(_on_menu_input.bind(clicks))
	add_child(clicks)

## A click on a name in the party menu asks for that character to be
## selected (see member_clicked); over one, the pointer shows it can be.
func _on_menu_input(event: InputEvent, clicks: Control) -> void:
	if not event is InputEventMouse:
		return
	var party := fighters_on(Side.PARTY)
	var row := BattlePainter.party_row_at(size, event.position, party.size())
	clicks.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if row >= 0 else Control.CURSOR_ARROW
	if row < 0 or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var npc = instance_from_id(party[row].id)
	if npc is NpcAgent:
		member_clicked.emit(npc)

# ============================== Who's there ===============================

## Who's in the scene right now: `party` (the selected character's party,
## its leader first, any of them fallen included) and `foes` (whoever
## they're fighting, or nobody), plus `status_text`, what the party's up to,
## and `on_the_move`, whether they're taking a step right now. A different
## party starts the scene over; otherwise newcomers walk in, and foes who've
## gone (without being seen to fall) walk off -- once their part in any
## blows still to be played out is over.
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
		var f := fighter_of(node)
		if f != null and f.side == side:
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
	_shop_snaps = true

func _sync_side(nodes: Array, side: int) -> void:
	var listed: Dictionary = {}
	for node in nodes:
		var id: int = node.get_instance_id()
		listed[id] = true
		if not fighters.has(id):
			var at_once: bool = _fresh or (node is NpcAgent and node.dead)
			var f := BattleFighter.of(node, side, 0.0 if at_once else ENTER_SECONDS)
			f.slot = _free_slot(side)
			fighters[id] = f
	if side == Side.PARTY and not nodes.is_empty():
		_put_in_front(fighter_of(nodes[0]))
	var pending := _pending_ids()
	for id in fighters.keys():
		var f: BattleFighter = fighters[id]
		if f.side != side or listed.has(id) or pending.has(id):
			continue
		if f.is_down() or f.leave >= 0.0:
			continue  # fallen (they lie where they fell), or already on their way
		if side == Side.PARTY:
			fighters.erase(id)  # left the party
		else:
			f.leave = LEAVE_SECONDS
	if _queue.is_empty():
		for node in nodes:
			fighter_of(node).take_stats(node)

## The first spot on `side` nobody's standing in. Everyone keeps the spot
## they were given for as long as they're in the scene, as in the games --
## no shuffling up when someone falls.
func _free_slot(side: int) -> int:
	var taken: Dictionary = {}
	for f in fighters.values():
		if f.side == side and f.slot >= 0:
			taken[f.slot] = true
	var slot := 0
	while taken.has(slot):
		slot += 1
	return slot

## Gives the party's leader the front-and-centre spot (the first), swapping
## with whoever had it -- a new leader steps up, and a fallen one is left
## lying where the new one was.
func _put_in_front(leader: BattleFighter) -> void:
	if leader.slot == 0:
		return
	for f in fighters_on(Side.PARTY):
		if f.slot == 0:
			f.slot = leader.slot
	leader.slot = 0

func _pending_ids() -> Dictionary:
	var ids: Dictionary = {}
	for ev in _queue:
		ids[ev.actor_id] = true
		ids[ev.target_id] = true
	return ids

## `node`'s figure, or null if it isn't in the scene.
func fighter_of(node: Node) -> BattleFighter:
	return fighters.get(node.get_instance_id())

## Everyone on `side`, in spot order.
func fighters_on(side: int) -> Array:
	var result: Array = fighters.values().filter(func(f): return f.side == side)
	result.sort_custom(func(a, b): return a.slot < b.slot)
	return result

# ================================ Events ==================================

## Queues one event of a fight to be played out, if it involves anyone in
## the scene.
func play(event: CombatEvent) -> void:
	if not fighters.has(event.actor_id) and not fighters.has(event.target_id):
		return
	_queue.append(event)
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
	if shop != "":
		_shop_in = minf(1.0, _shop_in + delta / ENTER_SECONDS)
	else:
		_shop_in = maxf(0.0, _shop_in - delta / LEAVE_SECONDS)
		if _shop_in == 0.0:
			_shop_drawn = ""
	walking = _walk_hold > 0.0 and fighters_on(Side.FOES).is_empty() and not fighters_on(Side.PARTY).is_empty()
	if walking:
		_walk_phase += delta
	_animate(delta)
	_check_fight_over()
	queue_redraw()

func _act(ev: CombatEvent) -> void:
	var actor: BattleFighter = fighters.get(ev.actor_id)
	if ev.kind == CombatEvent.Kind.ESCAPE:
		_escape(actor)
		return

	actions_played += 1
	var target: BattleFighter = fighters.get(ev.target_id)
	if CombatRules.ACTION_NAMES.has(ev.action):
		_show_caption(CombatRules.ACTION_NAMES[ev.action])
	if actor != null:
		actor.mp = ev.actor_mp
		if ev.is_heal():
			actor.glow = SPELL_SECONDS * 2.0
		else:
			actor.lunge = LUNGE_SECONDS
	if target == null:
		return
	# A spell has to fly and a blow to land before the target feels it.
	var delay := 0.0
	if CombatRules.is_offensive_spell(ev.action):
		delay = SPELL_SECONDS
		if actor != null:
			_spells.append({"kind": ev.action, "from": _place_of(actor), "to": _place_of(target), "t": 0.0})
	elif not ev.is_heal():
		delay = LUNGE_SECONDS * 0.5
	target.hp = ev.target_hp
	target.max_hp = ev.target_max_hp
	_pop_number(ev, target, delay)
	if ev.killed:
		_fall(target, delay)

## `actor` gets away: the whole party runs for it, or a foe's said to have
## fled.
func _escape(actor: BattleFighter) -> void:
	if actor == null:
		return
	if actor.side == Side.PARTY:
		_party_escaped = true
		_show_banner("Escaped!")
		for f in fighters_on(Side.PARTY):
			if not f.ko:
				f.run = RUN_SECONDS
	else:
		_show_caption("%s fled!" % actor.name)

## What `ev` did to `target`, floating up over them `delay` seconds from
## now: "Miss", a heal ("+5"), a critical hit ("9!"), or the damage -- which
## also has them blink white.
func _pop_number(ev: CombatEvent, target: BattleFighter, delay: float) -> void:
	var text := str(ev.amount)
	var color := BattlePainter.TEXT_COLOR
	if ev.missed:
		text = "Miss"
		color = BattlePainter.MISS_COLOR
	elif ev.is_heal():
		text = "+%d" % ev.amount
		color = BattlePainter.HEAL_COLOR
	elif ev.crit:
		text = "%d!" % ev.amount
		color = BattlePainter.CRIT_COLOR
	else:
		target.flash = HIT_FLASH_SECONDS + delay
	# Over the target's body, stacked above any number of theirs still showing.
	var pos := _home_of(target) + Vector2(0, -target.height() * 0.2)
	pos.y -= 16.0 * popups.filter(func(p): return p["target_id"] == target.id and p["t"] < POPUP_SECONDS * 0.5).size()
	popups.append({"text": text, "color": color, "pos": pos, "t": -delay, "target_id": target.id})

## `target` falls, `delay` seconds from now: monsters dissolve; players fall
## and lie where they fell.
func _fall(target: BattleFighter, delay: float) -> void:
	if target.is_player():
		target.ko = true
	else:
		target.dissolve = DISSOLVE_SECONDS + delay
	if target.side == Side.FOES:
		_foes_defeated += 1

func _show_caption(text: String) -> void:
	caption = text
	_caption_left = CAPTION_SECONDS

func _show_banner(text: String) -> void:
	banner = text
	_banner_left = BANNER_SECONDS

func _animate(delta: float) -> void:
	for id in fighters.keys():
		if not fighters[id].tick(delta):
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
	if fighters_on(Side.FOES).any(func(f): return not f.ko):
		return
	_in_fight = false
	var standing := fighters_on(Side.PARTY).filter(func(f): return not f.ko)
	if standing.is_empty():
		if not fighters.is_empty():
			_show_banner("Defeated...")
	elif _foes_defeated > 0 and not _party_escaped:
		_show_banner("Victory!")
		for f in standing:
			f.hop = HOP_SECONDS
	for f in fighters.values():
		if f.ko and f.linger < 0.0 and not _listed.has(f.id):
			f.linger = FALLEN_LINGER_SECONDS
	_foes_defeated = 0
	_party_escaped = false

# ================================ Layout ==================================

## Where `f` stands in the field, before any animation: its spot (see
## _free_slot).
func _home_of(f: BattleFighter) -> Vector2:
	if f.side == Side.PARTY:
		return PARTY_SPOTS[f.slot % PARTY_SPOTS.size()]
	var spot: Vector2 = FOE_SPOTS[f.slot % FOE_SPOTS.size()]
	if f.kind == "boss":
		spot = BOSS_SPOT
	elif _facing_a_boss():
		spot = BOSS_GUARD_SPOTS[f.slot % BOSS_GUARD_SPOTS.size()]
	return Vector2(size.x - spot.x, spot.y)

func _facing_a_boss() -> bool:
	for f in fighters.values():
		if f.kind == "boss":
			return true
	return false

## Which way `f` faces: the party right, towards the foes; the foes left.
func _facing_of(f: BattleFighter) -> float:
	return 1.0 if f.side == Side.PARTY else -1.0

## Where `f` is drawn right now, animations included.
func _place_of(f: BattleFighter) -> Vector2:
	var p := _home_of(f)
	var facing := _facing_of(f)
	if f.lunge > 0.0:
		p.x += sin(PI * (1.0 - f.lunge / LUNGE_SECONDS)) * LUNGE_DISTANCE * facing
	if f.enter > 0.0:
		p.x -= facing * 80.0 * f.enter / ENTER_SECONDS
	if f.leave >= 0.0:
		p.x -= facing * 100.0 * (1.0 - f.leave / LEAVE_SECONDS)
	if f.run > 0.0:
		# Turn tail and dash off the way they came, then come back.
		p.x -= facing * sin(PI * (1.0 - f.run / RUN_SECONDS)) * 60.0
	if f.hop > 0.0:
		p.y -= absf(sin(f.hop / HOP_SECONDS * TAU * 1.5)) * 8.0
	if f.side == Side.PARTY and not f.ko:
		if walking:
			p.y -= absf(sin(_stride_of(f) * PI)) * 2.5  # a bob in step
		else:
			p.y -= (sin(_time * 2.0 + f.slot) + 1.0) * 0.4  # breathing
	return p

## Where the shopkeeper stands (see `shop`): at SHOP_SPOT once slid in, and
## off past the window's right edge, counter and all, before.
func shop_position() -> Vector2:
	var home := Vector2(size.x - SHOP_SPOT.x, SHOP_SPOT.y)
	var out_of_sight := SHOP_SPOT.x + 50.0  # the counter reaches 44 either side
	return home + Vector2((1.0 - smoothstep(0.0, 1.0, _shop_in)) * out_of_sight, 0.0)

## Where `f` is in its stride while walking, in strides (each member a
## little out of step with the next).
func _stride_of(f: BattleFighter) -> float:
	return _walk_phase * STRIDES_PER_SECOND + f.slot * 0.37

## How much smaller `f` is drawn for standing further back: FAR_SCALE at
## the back wall, full size at the front of the floor. Taken from its spot,
## so it doesn't shrink and grow as it bobs.
func _depth_of(f: BattleFighter) -> float:
	var k := clampf((_home_of(f).y - FLOOR_TOP) / (FIELD_HEIGHT - FLOOR_TOP), 0.0, 1.0)
	return lerpf(FAR_SCALE, 1.0, k)

## Where `f`'s feet touch the floor, at its spot.
func _feet_of(f: BattleFighter) -> float:
	var below := 14.0 * BattleFighter.FIGURE_SCALE if f.is_player() else f.height() * 0.6
	return _home_of(f).y + below * _depth_of(f)

# ================================ Drawing =================================

func _draw() -> void:
	BattlePainter.draw_backdrop(self, size.x, _walk_phase * WALK_SPEED, _time)
	if _shop_drawn != "" and fighters_on(Side.FOES).is_empty():
		BattlePainter.draw_shop(self, shop_position(), _shop_drawn, _time)
	var drawn := fighters.values()
	drawn.sort_custom(func(a, b): return _place_of(a).y < _place_of(b).y)
	for f in drawn:
		var stride := sin(_stride_of(f) * TAU) if walking and f.side == Side.PARTY else 0.0
		BattlePainter.draw_fighter(self, f, _place_of(f), _feet_of(f), _depth_of(f), _facing_of(f) < 0.0, stride, _time)
	for s in _spells:
		BattlePainter.draw_spell(self, s)
	for p in popups:
		BattlePainter.draw_popup(self, p)
	if caption != "":
		BattlePainter.draw_caption(self, size.x, caption)
	if banner != "":
		BattlePainter.draw_banner(self, size.x, banner)
	BattlePainter.draw_menus(self, size, fighters_on(Side.PARTY), fighters_on(Side.FOES), status)
	draw_rect(Rect2(Vector2.ZERO, size), BattlePainter.BOX_EDGE, false, 2.0)
