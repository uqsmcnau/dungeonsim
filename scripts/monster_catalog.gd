class_name MonsterCatalog
extends RefCounted

## Every kind of monster in the dungeon, one per level: levels 1-10 roam
## the maze (weakest at its edge, strongest round the boss room), level 11
## leads each mini boss's party and level 12 is the boss. A monster's level
## is what makes it the kind it is (see EnemyAgent.setup) -- a pack's
## weaker members are the kind for their own, lower level.
##
## Each kind has a `name`; a `color`; an outline (see outline) for its map
## icon and its body in the battle window -- `sides` points round, every
## other one pulled in to `inner` of the way out for a star (1 for none),
## turned by `turn` degrees and stretched by `stretch`; a `size` for how big
## it's drawn in battle; and `features` (see BattlePainter.draw_monster).

const KINDS := [
	{"name": "Rat", "color": Color(0.62, 0.52, 0.42), "sides": 10, "inner": 1.0, "turn": 0.0,
		"stretch": Vector2(1.0, 0.75), "size": 0.75, "features": ["tail", "ears"]},
	{"name": "Slime", "color": Color(0.4, 0.85, 0.35), "sides": 12, "inner": 1.0, "turn": 0.0,
		"stretch": Vector2(1.15, 0.7), "size": 0.85, "features": ["shine"]},
	{"name": "Bat", "color": Color(0.5, 0.38, 0.6), "sides": 4, "inner": 0.55, "turn": 0.0,
		"stretch": Vector2(1.3, 0.8), "size": 0.8, "features": ["wings", "ears"]},
	{"name": "Goblin", "color": Color(0.6, 0.72, 0.25), "sides": 3, "inner": 1.0, "turn": -90.0,
		"stretch": Vector2(1.0, 1.0), "size": 0.9, "features": ["ears", "teeth"]},
	{"name": "Skeleton", "color": Color(0.9, 0.88, 0.78), "sides": 4, "inner": 1.0, "turn": -90.0,
		"stretch": Vector2(0.8, 1.0), "size": 1.0, "features": ["sockets", "teeth"]},
	{"name": "Orc", "color": Color(0.78, 0.45, 0.3), "sides": 4, "inner": 1.0, "turn": 45.0,
		"stretch": Vector2(1.0, 1.0), "size": 1.05, "features": ["tusks"]},
	{"name": "Wraith", "color": Color(0.6, 0.75, 0.95), "sides": 5, "inner": 1.0, "turn": 90.0,
		"stretch": Vector2(0.9, 1.0), "size": 1.0, "features": ["ghostly"]},
	{"name": "Troll", "color": Color(0.35, 0.62, 0.62), "sides": 6, "inner": 1.0, "turn": 0.0,
		"stretch": Vector2(1.0, 1.0), "size": 1.15, "features": ["horns", "tusks"]},
	{"name": "Golem", "color": Color(0.62, 0.62, 0.66), "sides": 8, "inner": 0.82, "turn": 0.0,
		"stretch": Vector2(1.0, 1.0), "size": 1.2, "features": ["cracks"]},
	{"name": "Wyvern", "color": Color(0.88, 0.25, 0.3), "sides": 5, "inner": 0.5, "turn": -90.0,
		"stretch": Vector2(1.0, 1.0), "size": 1.2, "features": ["wings", "horns", "tail"]},
	{"name": "Ogre Warlord", "color": Color(0.55, 0.15, 0.75), "sides": 6, "inner": 0.6, "turn": -90.0,
		"stretch": Vector2(1.0, 1.0), "size": 1.0, "features": ["crown", "tusks"]},
	{"name": "Dragon", "color": Color(0.55, 0.02, 0.05), "sides": 8, "inner": 0.55, "turn": -90.0,
		"stretch": Vector2(1.0, 1.0), "size": 1.0, "features": ["wings", "horns", "tail"]},
]

## The highest level a monster roaming the maze reaches (see
## WorldBuilder.enemy_level_for).
const MAZE_MAX_LEVEL := 10

## The kind of monster of level `level` (clamped to the ones there are).
static func for_level(level: int) -> Dictionary:
	return KINDS[clampi(level, 1, KINDS.size()) - 1]

## `kind`'s outline, as points round its middle at a radius of about 1.
static func outline(kind: Dictionary) -> PackedVector2Array:
	var inner: float = kind["inner"]
	var corners: int = kind["sides"] * (2 if inner < 1.0 else 1)
	var turn := deg_to_rad(kind["turn"])
	var stretch: Vector2 = kind["stretch"]
	var points := PackedVector2Array()
	for i in range(corners):
		var a := turn + TAU * i / corners
		var reach := inner if inner < 1.0 and i % 2 == 1 else 1.0
		points.append(Vector2(cos(a), sin(a)) * reach * stretch)
	return points

## "a Troll", "an Orc", "the Dragon" -- `kind`'s name with the article
## that goes with it.
static func called(kind: Dictionary, the: bool = false) -> String:
	var name: String = kind["name"]
	if the:
		return "the " + name
	return ("an " if "AEIOU".contains(name[0]) else "a ") + name
