class_name BattlePainter
extends RefCounted

## Everything the battle window (BattleWindow) draws, and nothing it decides:
## the dungeon hall, the figures in their gear, the monsters, spells,
## floating numbers and the blue boxes. Each function draws onto `canvas`
## (the window, mid-_draw) from what it's given -- the window works out
## where everyone is and how far through each animation.

const BOX_COLOR := Color(0.12, 0.16, 0.48)
const BOX_EDGE := Color(0.85, 0.88, 1.0)
const TEXT_COLOR := Color(1, 1, 1)
const LOW_HP_COLOR := Color(1.0, 0.85, 0.2)
const KO_COLOR := Color(1.0, 0.35, 0.35)
const HEAL_COLOR := Color(0.45, 1.0, 0.5)
const CRIT_COLOR := Color(1.0, 0.85, 0.2)
const MISS_COLOR := Color(0.75, 0.75, 0.8)
const MP_COLOR := Color(0.7, 0.8, 1.0)

const SKIN := Color(1.0, 0.85, 0.7)
const METAL := Color(0.72, 0.74, 0.8)
const LEATHER := Color(0.42, 0.26, 0.12)
const GOLD := Color(0.95, 0.8, 0.3)

# ================================ The hall ================================

## A dark dungeon hall `width` wide: a gradient wall lined with torch-lit
## pillars, and a stone floor running off towards the back. `scroll` (how
## far the party's walked) moves the floor past, and the pillars -- further
## off -- at half the speed; `time` flickers the torches.
static func draw_backdrop(canvas: CanvasItem, width: float, scroll: float, time: float) -> void:
	var wall_bottom := BattleWindow.FLOOR_TOP
	var field_height := BattleWindow.FIELD_HEIGHT
	var bands := 12
	for i in range(bands):
		var c := Color(0.05, 0.05, 0.12).lerp(Color(0.13, 0.1, 0.22), float(i) / bands)
		canvas.draw_rect(Rect2(0, wall_bottom * i / bands, width, wall_bottom / bands + 1.0), c)
	var pillar_gap := 110.0
	var x := -fmod(scroll * 0.5, pillar_gap)
	while x < width + pillar_gap:
		canvas.draw_rect(Rect2(x, 0, 16.0, wall_bottom), Color(0.09, 0.07, 0.15))
		canvas.draw_rect(Rect2(x + 16.0, 0, 3.0, wall_bottom), Color(0.06, 0.05, 0.1))
		var flicker := 1.0 + 0.2 * sin(time * 11.0 + x * 0.1)
		canvas.draw_circle(Vector2(x + 8.0, wall_bottom * 0.45), 6.0 * flicker, Color(1.0, 0.5, 0.1, 0.25))
		canvas.draw_circle(Vector2(x + 8.0, wall_bottom * 0.45), 2.5 * flicker, Color(1.0, 0.8, 0.3))
		x += pillar_gap
	canvas.draw_rect(Rect2(0, wall_bottom, width, field_height - wall_bottom), Color(0.17, 0.14, 0.2))
	var vanish := Vector2(width / 2.0, wall_bottom - 60.0)
	var line := Color(0.24, 0.2, 0.28)
	var shift := -fmod(scroll, 70.0)
	for i in range(-7, 8):
		var bottom := Vector2(width / 2.0 + i * 70.0 + shift, field_height)
		var top := vanish.lerp(bottom, (wall_bottom - vanish.y) / (field_height - vanish.y))
		canvas.draw_line(top, bottom, line, 1.0)
	var y := wall_bottom
	var gap := 6.0
	while y < field_height:
		canvas.draw_line(Vector2(0, y), Vector2(width, y), line, 1.0)
		y += gap
		gap *= 1.35

# ================================= Shops ==================================

## The trim on a shop's counter, by its rarity.
const SHOP_TRIM := {ItemCatalog.RARITY_BRONZE: Color(0.72, 0.4, 0.15), ItemCatalog.RARITY_SILVER: Color(0.9, 0.93, 1.0)}
const SHOPKEEPER_ROBE := Color(0.45, 0.25, 0.55)
const COUNTER_WOOD := Color(0.4, 0.25, 0.13)

## A shopkeeper, facing the party, behind their counter -- trimmed, and
## with a plaque on its front, to match the shop's `rarity` -- with wares on
## it: a red and a blue potion, a sword and a pile of coins. `at` is where the shopkeeper stands; `time`
## has them breathe.
static func draw_shop(canvas: CanvasItem, at: Vector2, rarity: String, time: float) -> void:
	var scale := BattleFighter.FIGURE_SCALE
	var keeper := at + Vector2(0, -(sin(time * 2.0) + 1.0) * 0.4)
	# Their shadow, then them -- a robed figure in a pointed hat.
	canvas.draw_set_transform(Vector2(at.x, at.y + 16.0 * scale), 0.0, Vector2(1.0, 0.3))
	canvas.draw_circle(Vector2.ZERO, 22.0, Color(0, 0, 0, 0.35))
	canvas.draw_set_transform(keeper, 0.0, Vector2.ONE * scale)
	draw_figure(canvas, Vector2.ZERO, SHOPKEEPER_ROBE, true, false, 1.0)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-6, -9), Vector2(6, -9), Vector2(1, -20)]), SHOPKEEPER_ROBE.darkened(0.2))
	canvas.draw_set_transform(Vector2.ZERO)
	# The counter, across their waist: its top, front and trim.
	var trim: Color = SHOP_TRIM.get(rarity, SHOP_TRIM[ItemCatalog.RARITY_BRONZE])
	var top_y := at.y + 7.0 * scale
	var front := Rect2(at.x - 40.0, top_y + 4.0, 80.0, 22.0)
	canvas.draw_rect(Rect2(at.x - 44.0, top_y, 88.0, 5.0), COUNTER_WOOD.lightened(0.15))
	canvas.draw_rect(front, COUNTER_WOOD)
	canvas.draw_rect(Rect2(front.position.x, front.position.y, front.size.x, 3.0), trim)
	canvas.draw_rect(Rect2(front.position.x, front.end.y - 3.0, front.size.x, 3.0), trim)
	for x in [front.position.x + 20.0, front.end.x - 20.0]:
		canvas.draw_line(Vector2(x, front.position.y + 5.0), Vector2(x, front.end.y - 5.0), COUNTER_WOOD.darkened(0.3), 1.5)
	var plaque := front.get_center()
	canvas.draw_circle(plaque, 6.0, trim)
	canvas.draw_circle(plaque, 4.0, trim.darkened(0.25))
	canvas.draw_circle(plaque, 2.0, trim)
	# The wares on top.
	_draw_potion(canvas, Vector2(at.x - 34.0, top_y), Color(0.9, 0.2, 0.2))
	_draw_potion(canvas, Vector2(at.x - 25.0, top_y), Color(0.3, 0.45, 1.0))
	canvas.draw_line(Vector2(at.x + 8.0, top_y - 2.0), Vector2(at.x + 26.0, top_y - 2.0), METAL, 2.0)
	canvas.draw_line(Vector2(at.x + 8.0, top_y - 5.0), Vector2(at.x + 8.0, top_y + 1.0), LEATHER, 2.0)
	for i in range(3):
		canvas.draw_circle(Vector2(at.x + 33.0 + i * 3.0, top_y - 2.0 - (1.5 if i == 1 else 0.0)), 2.5, GOLD)

## A little round potion bottle standing on `base`, full of `color`.
static func _draw_potion(canvas: CanvasItem, base: Vector2, color: Color) -> void:
	canvas.draw_rect(Rect2(base.x - 1.5, base.y - 10.0, 3.0, 4.0), Color(0.85, 0.9, 0.95, 0.8))
	canvas.draw_circle(base + Vector2(0, -4.0), 4.0, color)
	canvas.draw_circle(base + Vector2(-1.2, -5.2), 1.2, Color(1, 1, 1, 0.6))

# ================================ Fighters ================================

## `f` standing (or lying) at `at`, its shadow on the floor at `ground_y`,
## drawn `depth` times full size (smaller further back), facing left if
## `faces_left`; `stride` (-1 to 1) swings a walking player's legs.
static func draw_fighter(canvas: CanvasItem, f: BattleFighter, at: Vector2, ground_y: float, depth: float,
		faces_left: bool, stride: float, time: float) -> void:
	var color := f.color
	var alpha := 1.0
	if f.dissolve >= 0.0:
		alpha = clampf(f.dissolve / BattleWindow.DISSOLVE_SECONDS, 0.0, 1.0)
		color = color.lerp(Color(1, 0.3, 0.5), 1.0 - alpha)
	if f.leave >= 0.0:
		alpha = clampf(f.leave / BattleWindow.LEAVE_SECONDS, 0.0, 1.0)
	if f.linger >= 0.0:
		alpha = clampf(f.linger / BattleWindow.FALLEN_LINGER_SECONDS * 2.0, 0.0, 1.0)
	# Hit: blink white.
	if f.flash > 0.0 and f.flash < BattleWindow.HIT_FLASH_SECONDS and int(f.flash * 24.0) % 2 == 0:
		color = Color.WHITE
	color.a = alpha
	# A shadow on the floor underfoot -- staying put while they hop or bob.
	canvas.draw_set_transform(Vector2(at.x, ground_y), 0.0, Vector2(1.0, 0.3))
	canvas.draw_circle(Vector2.ZERO, f.height() * 0.4 * depth, Color(0, 0, 0, 0.35 * alpha))
	canvas.draw_set_transform(Vector2.ZERO)
	if f.is_player():
		canvas.draw_set_transform(at, 0.0, Vector2.ONE * BattleFighter.FIGURE_SCALE * depth)
		draw_figure(canvas, Vector2.ZERO, color, faces_left, f.ko, alpha, stride, f.look, time)
		canvas.draw_set_transform(Vector2.ZERO)
	else:
		draw_monster(canvas, at, color, f, alpha, depth)
	if f.glow > 0.0:
		var k: float = f.glow / (BattleWindow.SPELL_SECONDS * 2.0)
		for i in range(5):
			var a := TAU * i / 5.0 + k * 4.0
			canvas.draw_circle(at + Vector2(cos(a) * 12.0, -k * 18.0 + sin(a) * 4.0), 2.0, Color(HEAL_COLOR, k))

## A little adventurer facing the enemy (the party faces right, a rival
## party left), dressed in whatever they're wearing -- `look`, from
## BattleFighter.look_of: sword in the front hand (or bare-fisted), shield
## or tome in the other, armor over their tunic, helmet, boots, amulet and
## ring. Fallen, they lie flat. `stride` (-1 to 1) swings the legs, mid-walk.
static func draw_figure(canvas: CanvasItem, p: Vector2, color: Color, faces_left: bool, ko: bool, alpha: float,
		stride: float = 0.0, look: Dictionary = {}, time: float = 0.0) -> void:
	var skin := Color(SKIN, alpha)
	var metal := Color(METAL, alpha)
	var leather := Color(LEATHER, alpha)
	var gold := Color(GOLD, alpha)
	if ko:
		var grey := Color(color.lerp(Color(0.4, 0.4, 0.4), 0.6), alpha)
		canvas.draw_rect(Rect2(p.x - 7.0, p.y + 6.0, 16.0, 7.0), grey)
		var head := Vector2(p.x - 11.0 if faces_left else p.x + 13.0, p.y + 9.0)
		canvas.draw_circle(head, 4.5, Color(skin.lerp(Color(0.5, 0.5, 0.5), 0.5), alpha))
		if look.get("helmet", false):
			canvas.draw_circle(head + Vector2(-2.0 if faces_left else 2.0, 0), 3.0, gold if look.get("gold_helm", false) else metal)
		return
	var dir := -1.0 if faces_left else 1.0
	var front_hand := p + Vector2(dir * 5.0, 2.0)
	var back_hand := p + Vector2(-dir * 6.0, 3.0)
	var weapon: String = look.get("weapon", "")
	var off_hand: String = look.get("off_hand", "")

	# Behind the body: a second sword, its tip over the shoulder, or a staff
	# with a glowing orb.
	if off_hand == "iron_sword":
		canvas.draw_line(back_hand, p + Vector2(-dir * 9.0, -13.0), metal, 1.8)
	elif off_hand == "staff":
		var orb := back_hand + Vector2(-dir * 1.0, -17.0)
		canvas.draw_line(back_hand + Vector2(0, 5.0), orb, Color(0.45, 0.28, 0.12, alpha), 1.6)
		canvas.draw_circle(orb, 2.6 + 0.4 * sin(time * 4.0), Color(0.65, 0.45, 1.0, alpha))
		canvas.draw_circle(orb, 1.2, Color(1, 1, 1, 0.8 * alpha))

	# Legs: one forward, one back, the raised one lifted off the ground --
	# in boots, if they have them.
	var swing := stride * 2.5
	var boots: bool = look.get("boots", false)
	var leg_color := leather if boots else color.darkened(0.4)
	for leg in [[-5.0 + swing, maxf(stride, 0.0)], [1.0 - swing, maxf(-stride, 0.0)]]:
		var leg_top: float = p.y + 10.0 - leg[1] * 1.5
		canvas.draw_rect(Rect2(p.x + leg[0], leg_top, 4.0, 4.0), leg_color)
		if boots:
			canvas.draw_rect(Rect2(p.x + leg[0] - 0.5, leg_top, 5.0, 1.0), leather.lightened(0.3))
		if look.get("winged", false):
			var heel := Vector2(p.x + leg[0] + (4.0 if faces_left else 0.0), leg_top + 1.0)
			canvas.draw_colored_polygon(PackedVector2Array([heel, heel + Vector2(-dir * 4.0, -3.0), heel + Vector2(-dir * 3.0, 0.5)]),
				Color(1, 1, 1, alpha))

	# Body: their tunic, under any armor.
	canvas.draw_rect(Rect2(p.x - 6.0, p.y - 3.0, 12.0, 13.0), color)
	match look.get("armor", ""):
		"leather":
			canvas.draw_rect(Rect2(p.x - 5.0, p.y - 2.0, 10.0, 9.0), Color(0.55, 0.36, 0.18, alpha))
			canvas.draw_rect(Rect2(p.x - 6.0, p.y + 6.0, 12.0, 1.6), leather)
			canvas.draw_rect(Rect2(p.x - 1.0, p.y + 5.8, 2.0, 2.0), gold)
		"plate":
			canvas.draw_rect(Rect2(p.x - 6.0, p.y - 3.0, 12.0, 11.0), Color(0.86, 0.88, 0.94, alpha))
			canvas.draw_rect(Rect2(p.x - 6.0, p.y + 2.0, 12.0, 1.0), gold)
			canvas.draw_rect(Rect2(p.x - 0.5, p.y - 3.0, 1.0, 11.0), gold)
			for side in [-1.0, 1.0]:
				canvas.draw_circle(p + Vector2(side * 6.0, -2.0), 2.6, Color(0.78, 0.8, 0.88, alpha))
		"chainmail":
			canvas.draw_rect(Rect2(p.x - 6.0, p.y - 3.0, 12.0, 11.0), metal)
			for row in range(4):
				for col in range(4):
					var link := p + Vector2(-4.5 + col * 3.0 + (row % 2) * 1.5, -1.0 + row * 2.5)
					canvas.draw_circle(link, 0.6, Color(0.4, 0.42, 0.48, alpha))
	if look.get("amulet", false):
		canvas.draw_line(p + Vector2(-2.5, -3.0), p + Vector2(0, 1.0), gold, 0.6)
		canvas.draw_line(p + Vector2(2.5, -3.0), p + Vector2(0, 1.0), gold, 0.6)
		canvas.draw_circle(p + Vector2(0, 1.6), 1.6, Color(0.3, 0.8, 1.0, alpha))

	# Head, under any helmet: a steel cap with a nose guard.
	canvas.draw_circle(p + Vector2(0, -9.0), 5.5, skin)
	var eye_y := -10.0
	if look.get("helmet", false):
		var cap := PackedVector2Array()
		for i in range(9):
			var a := PI + PI * i / 8.0
			cap.append(p + Vector2(0, -9.5) + Vector2(cos(a), sin(a)) * 6.2)
		var helm := gold if look.get("gold_helm", false) else metal
		if look.get("gold_helm", false):
			# A red plume, streaming back.
			canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -15.5), p + Vector2(-dir * 7.0, -17.0),
				p + Vector2(-dir * 5.0, -13.5)]), Color(0.85, 0.15, 0.15, alpha))
		canvas.draw_colored_polygon(cap, helm)
		canvas.draw_line(p + Vector2(-6.4, -9.5), p + Vector2(6.4, -9.5), helm.darkened(0.3), 1.2)
		canvas.draw_rect(Rect2(p.x + dir * 2.0 - 0.6, p.y - 9.5, 1.2, 3.0), helm.darkened(0.2))
		eye_y = -8.5
	canvas.draw_circle(p + Vector2(dir * 2.5, eye_y), 1.2, Color(0.1, 0.1, 0.15, alpha))

	# The back hand: a tome (if there's a sword in the other), a ring.
	if off_hand == "tome" and weapon != "":
		_draw_tome(canvas, back_hand + Vector2(-dir * 1.0, -1.0), alpha)
	if look.get("ring", false):
		var glint := back_hand + Vector2(0, 1.0)
		var k := 1.0 + 0.4 * sin(time * 6.0)
		canvas.draw_line(glint - Vector2(1.6 * k, 0), glint + Vector2(1.6 * k, 0), Color(1, 1, 1, alpha), 0.6)
		canvas.draw_line(glint - Vector2(0, 1.6 * k), glint + Vector2(0, 1.6 * k), Color(1, 1, 1, alpha), 0.6)

	# The front hand: a sword (steel longer and brighter, with a gilt
	# crossguard), else a tome held out, else a bare fist.
	if look.get("might", false):
		canvas.draw_circle(front_hand + Vector2(0, 1.0), 1.1, Color(0.95, 0.15, 0.2, alpha))
	match weapon:
		"mithril_sword":
			var tip := front_hand + Vector2(dir * 12.0, -15.0)
			_draw_sword(canvas, front_hand, tip, Color(0.72, 0.95, 1.0, alpha), gold, 2.6)
			var k := 1.2 + 0.6 * sin(time * 5.0)
			canvas.draw_line(tip - Vector2(k, 0), tip + Vector2(k, 0), Color(1, 1, 1, alpha), 0.7)
			canvas.draw_line(tip - Vector2(0, k), tip + Vector2(0, k), Color(1, 1, 1, alpha), 0.7)
		"steel_sword":
			_draw_sword(canvas, front_hand, front_hand + Vector2(dir * 11.0, -13.0),
				Color(0.88, 0.95, 1.0, alpha), Color(0.95, 0.78, 0.25, alpha), 2.4)
		"iron_sword":
			_draw_sword(canvas, front_hand, front_hand + Vector2(dir * 9.0, -10.0),
				Color(0.78, 0.78, 0.82, alpha), Color(0.45, 0.3, 0.15, alpha), 2.0)
		_:
			if off_hand == "tome":
				_draw_tome(canvas, front_hand + Vector2(dir * 1.5, -2.0), alpha)
			else:
				canvas.draw_circle(front_hand, 1.6, skin)

	# A shield, held in front of the body.
	var boss := p + Vector2(dir * 3.5, 3.5)
	match off_hand:
		"shield":
			canvas.draw_circle(boss, 4.3, Color(0.55, 0.35, 0.15, alpha))
			canvas.draw_arc(boss, 4.3, 0.0, TAU, 16, metal, 0.9)
			canvas.draw_circle(boss, 1.1, metal)
		"silver_shield":
			var kite := PackedVector2Array([
				boss + Vector2(-3.6, -4.5), boss + Vector2(3.6, -4.5),
				boss + Vector2(3.6, 0.5), boss + Vector2(0, 5.5), boss + Vector2(-3.6, 0.5),
			])
			canvas.draw_colored_polygon(kite, Color(0.84, 0.86, 0.92, alpha))
			kite.append(kite[0])
			canvas.draw_polyline(kite, Color(0.55, 0.58, 0.66, alpha), 0.8)
			canvas.draw_line(boss + Vector2(0, -3.5), boss + Vector2(0, 3.5), Color(0.25, 0.45, 0.9, alpha), 1.0)
			canvas.draw_line(boss + Vector2(-2.5, -1.0), boss + Vector2(2.5, -1.0), Color(0.25, 0.45, 0.9, alpha), 1.0)
		"aegis":
			var aegis := PackedVector2Array([
				boss + Vector2(-4.2, -5.2), boss + Vector2(4.2, -5.2),
				boss + Vector2(4.2, 0.6), boss + Vector2(0, 6.4), boss + Vector2(-4.2, 0.6),
			])
			canvas.draw_colored_polygon(aegis, gold)
			aegis.append(aegis[0])
			canvas.draw_polyline(aegis, Color(0.6, 0.42, 0.1, alpha), 0.9)
			canvas.draw_circle(boss + Vector2(0, -0.5), 1.8, Color(0.85, 0.15, 0.15, alpha))

static func _draw_sword(canvas: CanvasItem, hilt: Vector2, tip: Vector2, blade: Color, guard: Color, width: float) -> void:
	canvas.draw_line(hilt, tip, blade, width)
	var along := (tip - hilt).normalized()
	var across := along.orthogonal() * 2.5
	var guard_at := hilt + along * 1.5
	canvas.draw_line(guard_at - across, guard_at + across, guard, 1.4)

## A purple spellbook with pale page edges.
static func _draw_tome(canvas: CanvasItem, at: Vector2, alpha: float) -> void:
	canvas.draw_rect(Rect2(at.x - 2.0, at.y - 2.5, 4.0, 5.0), Color(0.45, 0.2, 0.65, alpha))
	canvas.draw_line(at + Vector2(2.0, -2.0), at + Vector2(2.0, 2.0), Color(0.95, 0.92, 0.8, alpha), 0.8)

## A monster like the ones on the map -- its kind's outline and colour (see
## MonsterCatalog) -- only bigger and with a face, glaring left towards the
## party, and whatever marks its kind out: wings, a tail, horns, a crown...
## Bosses' eyes glow red, mid bosses' purple. Shrinks a little as it
## dissolves.
static func draw_monster(canvas: CanvasItem, p: Vector2, color: Color, f: BattleFighter, alpha: float, depth: float) -> void:
	var r := f.height() * 0.6 * depth
	if f.dissolve >= 0.0:
		r *= 0.8 + 0.2 * alpha
	var kind: MonsterKind = f.monster if f.monster != null else MonsterCatalog.for_level(f.level)
	var features: Array[String] = kind.features
	if features.has("ghostly"):
		color.a *= 0.7
	var edge := Color(color.darkened(0.5), alpha)
	# Behind the body.
	if features.has("wings"):
		for side in [-1.0, 1.0]:
			var root := p + Vector2(side * r * 0.3, -r * 0.2)
			canvas.draw_colored_polygon(PackedVector2Array([root, root + Vector2(side * r * 1.3, -r * 0.9),
				root + Vector2(side * r * 1.0, -r * 0.1), root + Vector2(side * r * 0.9, r * 0.3)]), Color(color.darkened(0.25), color.a))
	if features.has("tail"):
		canvas.draw_polyline(PackedVector2Array([p + Vector2(r * 0.8, r * 0.3), p + Vector2(r * 1.3, r * 0.1),
			p + Vector2(r * 1.55, -r * 0.35)]), edge, maxf(1.5, r * 0.12))
	# The body.
	var points := PackedVector2Array()
	for point in kind.outline():
		points.append(p + point * r)
	canvas.draw_colored_polygon(points, color)
	points.append(points[0])
	canvas.draw_polyline(points, edge, 1.5)
	# On top.
	if features.has("ears"):
		for x in [-0.55, -0.15]:
			var base := p + Vector2(r * x, -r * 0.55)
			canvas.draw_colored_polygon(PackedVector2Array([base, base + Vector2(r * 0.3, 0), base + Vector2(r * 0.1, -r * 0.45)]), color)
	if features.has("horns"):
		for x in [-0.5, 0.1]:
			var base := p + Vector2(r * x, -r * 0.6)
			canvas.draw_colored_polygon(PackedVector2Array([base, base + Vector2(r * 0.25, 0), base + Vector2(-r * 0.05, -r * 0.55)]),
				Color(0.95, 0.9, 0.75, alpha))
	if features.has("crown"):
		var top := p + Vector2(-r * 0.45, -r * 0.75)
		canvas.draw_colored_polygon(PackedVector2Array([top, top + Vector2(r * 0.9, 0), top + Vector2(r * 0.9, -r * 0.35),
			top + Vector2(r * 0.68, -r * 0.15), top + Vector2(r * 0.45, -r * 0.4), top + Vector2(r * 0.22, -r * 0.15),
			top + Vector2(0, -r * 0.35)]), Color(GOLD, alpha))
	if features.has("shine"):
		canvas.draw_circle(p + Vector2(-r * 0.25, -r * 0.35), r * 0.12, Color(1, 1, 1, 0.6 * alpha))
	if features.has("cracks"):
		canvas.draw_polyline(PackedVector2Array([p + Vector2(r * 0.1, -r * 0.7), p + Vector2(r * 0.3, -r * 0.2),
			p + Vector2(r * 0.05, r * 0.15), p + Vector2(r * 0.35, r * 0.6)]), edge, 1.2)
	_draw_face(canvas, p, r, f, features, alpha)

## Eyes and a mouth on the left of a monster's body (see draw_monster).
static func _draw_face(canvas: CanvasItem, p: Vector2, r: float, f: BattleFighter, features: Array, alpha: float) -> void:
	var eye := Color(1.0, 0.95, 0.3, alpha)
	if f.kind == "boss":
		eye = Color(1.0, 0.2, 0.2, alpha)
	elif f.kind == "mid_boss":
		eye = Color(0.75, 0.4, 1.0, alpha)
	var eyes := [p + Vector2(-r * 0.35, -r * 0.25), p + Vector2(-r * 0.65, -r * 0.2)]
	if features.has("sockets"):
		for e in eyes:
			canvas.draw_circle(e, r * 0.17, Color(0.1, 0.05, 0.05, alpha))
			canvas.draw_circle(e, r * 0.06, Color(1.0, 0.3, 0.2, alpha))
	else:
		canvas.draw_circle(eyes[0], r * 0.14, eye)
		canvas.draw_circle(eyes[1], r * 0.12, eye)
	var mouth_left := p + Vector2(-r * 0.7, r * 0.2)
	var mouth_right := p + Vector2(-r * 0.25, r * 0.25)
	canvas.draw_line(mouth_left, mouth_right, Color(0.1, 0.0, 0.0, alpha), 1.5)
	var tooth := Color(1.0, 1.0, 0.95, alpha)
	if features.has("teeth"):
		for k in [0.2, 0.5, 0.8]:
			var at := mouth_left.lerp(mouth_right, k)
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-r * 0.05, 0), at + Vector2(r * 0.05, 0), at + Vector2(0, r * 0.1)]), tooth)
	if features.has("tusks"):
		for at in [mouth_left + Vector2(r * 0.05, 0), mouth_right - Vector2(r * 0.05, 0)]:
			canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(-r * 0.06, 0), at + Vector2(r * 0.06, 0),
				at + Vector2(0, -r * 0.22)]), tooth)

# ============================ Spells and text =============================

## A spell in flight: `s` is {kind, from, to, t}. A fireball flies across
## and bursts; a spark strikes the target as a flickering bolt.
static func draw_spell(canvas: CanvasItem, s: Dictionary) -> void:
	var flight := BattleWindow.SPELL_SECONDS
	var k: float = clampf(s["t"] / flight, 0.0, 1.0)
	if s["kind"] == CombatRules.FIREBALL:
		if k < 1.0:
			var at: Vector2 = s["from"].lerp(s["to"], k)
			canvas.draw_circle(at, 6.0, Color(1.0, 0.45, 0.1))
			canvas.draw_circle(at, 3.0, Color(1.0, 0.9, 0.4))
		else:
			var burst: float = (s["t"] - flight) / 0.2
			canvas.draw_arc(s["to"], 6.0 + burst * 16.0, 0.0, TAU, 20, Color(1.0, 0.5, 0.1, 1.0 - burst), 3.0)
	else:
		if int(s["t"] * 30.0) % 2 == 1:
			return
		var top: Vector2 = s["to"] + Vector2(0, -60.0)
		var bolt := PackedVector2Array([top])
		for i in range(1, 6):
			var y := top.y + 60.0 * i / 5.0
			bolt.append(Vector2(top.x + (8.0 if i % 2 == 0 else -8.0) * (1.0 if i < 5 else 0.0), y))
		canvas.draw_polyline(bolt, Color(1.0, 1.0, 0.5), 2.5)

## A number floating up over whoever was hit or healed: `p` is {text,
## color, pos, t}; it rises, holds, then fades.
static func draw_popup(canvas: CanvasItem, p: Dictionary) -> void:
	if p["t"] < 0.0:
		return
	var k: float = p["t"] / BattleWindow.POPUP_SECONDS
	var rise := minf(p["t"] / 0.25, 1.0) * 14.0
	var color: Color = p["color"]
	color.a = 1.0 if k < 0.7 else (1.0 - k) / 0.3
	draw_text_outlined(canvas, p["pos"] - Vector2(0, rise), p["text"], 16, color, true)

## The spell (or the like) being cast, in a box along the top.
static func draw_caption(canvas: CanvasItem, width: float, text: String) -> void:
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 24.0
	draw_box(canvas, Rect2((width - w) / 2.0, 6.0, w, 24.0))
	draw_text(canvas, Vector2(width / 2.0, 23.0), text, 14, TEXT_COLOR, true)

## "Victory!" and the like, big across the middle of the field.
static func draw_banner(canvas: CanvasItem, width: float, text: String) -> void:
	draw_text_outlined(canvas, Vector2(width / 2.0, BattleWindow.FIELD_HEIGHT * 0.5), text, 26, Color(1, 1, 0.85), true)

## A menu line's height, and how far below the top of the menus the party
## menu's first name sits (its baseline).
const MENU_ROW := 18.0
const PARTY_FIRST_ROW := 30.0

## The blue boxes along the bottom of a window `size`: the party's HP and MP
## on the left, under them, and who they're up against on the right -- or,
## with nobody to fight, `status` (what they're up to).
static func draw_menus(canvas: CanvasItem, size: Vector2, party: Array, foes: Array, status: String) -> void:
	var top := _menus_top()
	var height := size.y - top - 4.0
	var party_box := _party_box(size)
	var foe_box := Rect2(size.x * 0.62 + 2.0, top, size.x * 0.38 - 6.0, height)
	draw_box(canvas, party_box)
	draw_box(canvas, foe_box)
	var row := MENU_ROW
	if foes.is_empty():
		var text := status if not party.is_empty() else "Select a player to watch their battles."
		var inner := foe_box.grow(-8.0)
		canvas.draw_multiline_string(ThemeDB.fallback_font, inner.position + Vector2(0, 13), text,
			HORIZONTAL_ALIGNMENT_LEFT, inner.size.x, 13, 4, TEXT_COLOR)
	else:
		var y := top + 18.0
		for f in foes:
			if y > top + height - 4.0:
				break
			var label: String = f.name if f.is_player() else "%s Lv.%d" % [f.name, f.level]
			draw_text(canvas, Vector2(foe_box.position.x + 8.0, y), label, 13, MISS_COLOR if f.is_down() else TEXT_COLOR)
			y += row
	if not party.is_empty():
		draw_text(canvas, Vector2(party_box.position.x + 100.0, top + 14.0), "HP", 10, MISS_COLOR)
		draw_text(canvas, Vector2(party_box.position.x + 178.0, top + 14.0), "MP", 10, MISS_COLOR)
	var y2 := top + PARTY_FIRST_ROW
	for f in party:
		if y2 > top + height - 4.0:
			break
		var color := TEXT_COLOR
		if f.ko:
			color = KO_COLOR
		elif f.hp * 4 <= f.max_hp:
			color = LOW_HP_COLOR
		var x := party_box.position.x + 8.0
		draw_text(canvas, Vector2(x, y2), f.name, 13, color)
		draw_text(canvas, Vector2(x + 92.0, y2), "%d/%d" % [f.hp, f.max_hp], 13, color)
		draw_text(canvas, Vector2(x + 170.0, y2), "%d" % f.mp, 13, MP_COLOR)
		y2 += row

## Which line of the party menu (see draw_menus) `pos` is on, in a window
## `size` listing `count` of the party -- 0 for the first -- or -1 if none.
static func party_row_at(size: Vector2, pos: Vector2, count: int) -> int:
	var box := _party_box(size)
	if not box.has_point(pos):
		return -1
	var first_line_top := _menus_top() + PARTY_FIRST_ROW - MENU_ROW + 4.0  # a name's top, just above its baseline
	var i := floori((pos.y - first_line_top) / MENU_ROW)
	var baseline := _menus_top() + PARTY_FIRST_ROW + i * MENU_ROW
	if i < 0 or i >= count or baseline > box.end.y - 4.0:  # (below the last line drawn)
		return -1
	return i

static func _menus_top() -> float:
	return BattleWindow.FIELD_HEIGHT + 4.0

static func _party_box(size: Vector2) -> Rect2:
	var top := _menus_top()
	return Rect2(4.0, top, size.x * 0.62 - 6.0, size.y - top - 4.0)

static func draw_box(canvas: CanvasItem, rect: Rect2) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = BOX_COLOR
	style.border_color = BOX_EDGE
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	canvas.draw_style_box(style, rect)

## Text at `pos` (its baseline), or centred on `pos.x` if `centred`.
static func draw_text(canvas: CanvasItem, pos: Vector2, text: String, font_size: int, color: Color, centred: bool = false) -> void:
	var width := -1.0
	var align := HORIZONTAL_ALIGNMENT_LEFT
	if centred:
		width = 300.0
		pos.x -= 150.0
		align = HORIZONTAL_ALIGNMENT_CENTER
	canvas.draw_string(ThemeDB.fallback_font, pos, text, align, width, font_size, color)

## The same, with a dark outline, to read over the scene.
static func draw_text_outlined(canvas: CanvasItem, pos: Vector2, text: String, font_size: int, color: Color, centred: bool = false) -> void:
	var width := -1.0
	var align := HORIZONTAL_ALIGNMENT_LEFT
	if centred:
		width = 300.0
		pos.x -= 150.0
		align = HORIZONTAL_ALIGNMENT_CENTER
	canvas.draw_string_outline(ThemeDB.fallback_font, pos, text, align, width, font_size, 4, Color(0, 0, 0, color.a))
	canvas.draw_string(ThemeDB.fallback_font, pos, text, align, width, font_size, color)
