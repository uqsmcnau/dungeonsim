class_name BattleFighter
extends RefCounted

## One figure in the battle window (BattleWindow): a snapshot of a player or
## monster taken from the game -- so it can still be drawn after a monster's
## been freed -- plus its spot on the field and the animations it's part
## way through. The window decides what happens to it; BattlePainter draws
## it.

## Players are drawn at this scale (their sprite's 22 pixels tall at 1).
const FIGURE_SCALE := 1.5

var id: int = 0
## BattleWindow.Side.PARTY or FOES.
var side: int = 0
## Its spot on its side of the field (see BattleWindow._free_slot), or -1
## until it's given one.
var slot: int = -1
## "player", "monster", "mid_boss" or "boss".
var kind := "player"
var name := ""
var color := Color.WHITE
var level: int = 1
var hp: int = 0
var max_hp: int = 0
var mp: int = 0
var max_mp: int = 0
## A player who's fallen (they lie where they fell; monsters dissolve).
var ko := false
## How a player looks in their gear.
var look := FigureLook.new()
## A monster's kind (see MonsterCatalog): how it's drawn, and its name.
var monster: MonsterKind = null

## Animations, in seconds left, counting down to 0: stepping forward to
## strike, blinking from a hit, a heal's sparkle, walking in, running away
## (and back), hopping for joy.
var lunge := 0.0
var flash := 0.0
var glow := 0.0
var enter := 0.0
var run := 0.0
var hop := 0.0
## On the way out, in seconds left, or -1 if not: dissolving (a slain
## monster), walking off (a foe leaving unbeaten), lying a while longer (one
## fallen, after the fight).
var dissolve := -1.0
var leave := -1.0
var linger := -1.0

## A snapshot of `node` (a player or a monster) joining the window on
## `side` -- walking in over `enter_seconds` (0 to just be there).
static func of(node: Node, fighter_side: int, enter_seconds: float) -> BattleFighter:
	var f := BattleFighter.new()
	f.id = node.get_instance_id()
	f.side = fighter_side
	f.color = node.visual.color
	f.level = node.stats.level
	f.enter = enter_seconds
	if node is NpcAgent:
		f.kind = "player"
		f.name = node.npc_name
	else:
		f.kind = "boss" if node.is_boss else ("mid_boss" if node.is_mid_boss else "monster")
		f.monster = node.kind
		f.name = node.kind.name
	f.take_stats(node)
	return f

## Brings HP, MP, gear and whether they've fallen up to date from `node`.
func take_stats(node: Node) -> void:
	if node is NpcAgent:
		ko = node.dead
		look = FigureLook.of(node.stats)
	hp = maxi(0, node.stats.hp)
	max_hp = node.stats.max_hp
	mp = node.stats.mp
	max_mp = node.stats.max_mp

func is_player() -> bool:
	return kind == "player"

## Fallen, or dissolving: out of the fight.
func is_down() -> bool:
	return ko or dissolve >= 0.0

## How tall it's drawn, at full size (see BattleWindow._depth_of).
func height() -> float:
	match kind:
		"player":
			return 22.0 * FIGURE_SCALE
		"boss":
			return 64.0
		"mid_boss":
			return 44.0
	return 30.0 * (monster.size if monster != null else 1.0)

## Moves its animations on by `delta` seconds. False once it's gone from
## the scene: dissolved, walked off, or done lying there.
func tick(delta: float) -> bool:
	lunge = maxf(0.0, lunge - delta)
	flash = maxf(0.0, flash - delta)
	glow = maxf(0.0, glow - delta)
	enter = maxf(0.0, enter - delta)
	run = maxf(0.0, run - delta)
	hop = maxf(0.0, hop - delta)
	for timer in ["dissolve", "leave", "linger"]:
		var left: float = get(timer)
		if left >= 0.0:
			set(timer, left - delta)
			if left - delta < 0.0:
				return false
	return true
