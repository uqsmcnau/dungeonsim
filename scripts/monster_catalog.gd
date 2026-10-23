class_name MonsterCatalog
extends RefCounted

## Every kind of monster in the dungeon (see MonsterKind), one per level:
## levels 1-10 roam the maze (weakest at its edge, strongest round the boss
## room), level 11 leads each of the stronger mid bosses' parties and level
## 12 is the boss. A monster's level is what makes it the kind it is (see
## EnemyAgent.setup) -- a pack's weaker members are the kind for their own,
## lower level -- bar the lesser mid bosses, the Orc Chieftains
## (orc_chieftain).

## The highest level a monster roaming the maze reaches (see
## WorldBuilder.enemy_level_for).
const MAZE_MAX_LEVEL := 10

## By level, from 1: name, colour, outline (sides, inner, turn, stretch),
## size in battle, and features.
static var kinds: Array[MonsterKind] = [
	MonsterKind.new("Rat", Color(0.62, 0.52, 0.42), 10, 1.0, 0.0, Vector2(1.0, 0.75), 0.75, ["tail", "ears"]),
	MonsterKind.new("Slime", Color(0.4, 0.85, 0.35), 12, 1.0, 0.0, Vector2(1.15, 0.7), 0.85, ["shine"]),
	MonsterKind.new("Bat", Color(0.5, 0.38, 0.6), 4, 0.55, 0.0, Vector2(1.3, 0.8), 0.8, ["wings", "ears"]),
	MonsterKind.new("Goblin", Color(0.6, 0.72, 0.25), 3, 1.0, -90.0, Vector2(1.0, 1.0), 0.9, ["ears", "teeth"]),
	MonsterKind.new("Skeleton", Color(0.9, 0.88, 0.78), 4, 1.0, -90.0, Vector2(0.8, 1.0), 1.0, ["sockets", "teeth"]),
	MonsterKind.new("Orc", Color(0.78, 0.45, 0.3), 4, 1.0, 45.0, Vector2(1.0, 1.0), 1.05, ["tusks"]),
	MonsterKind.new("Wraith", Color(0.6, 0.75, 0.95), 5, 1.0, 90.0, Vector2(0.9, 1.0), 1.0, ["ghostly"]),
	MonsterKind.new("Troll", Color(0.35, 0.62, 0.62), 6, 1.0, 0.0, Vector2(1.0, 1.0), 1.15, ["horns", "tusks"]),
	MonsterKind.new("Golem", Color(0.62, 0.62, 0.66), 8, 0.82, 0.0, Vector2(1.0, 1.0), 1.2, ["cracks"]),
	MonsterKind.new("Wyvern", Color(0.88, 0.25, 0.3), 5, 0.5, -90.0, Vector2(1.0, 1.0), 1.2, ["wings", "horns", "tail"]),
	MonsterKind.new("Ogre Warlord", Color(0.55, 0.15, 0.75), 6, 0.6, -90.0, Vector2(1.0, 1.0), 1.0, ["crown", "tusks"]),
	MonsterKind.new("Dragon", Color(0.55, 0.02, 0.05), 8, 0.55, -90.0, Vector2(1.0, 1.0), 1.0, ["wings", "horns", "tail"]),
]

## The lesser mid boss, out towards the maze's edge: a level 6 like the
## Orc, but its own kind (see WorldBuilder._place_mid_bosses).
static var orc_chieftain := MonsterKind.new("Orc Chieftain", Color(0.92, 0.62, 0.15), 7, 0.65, -90.0,
	Vector2(1.0, 1.0), 1.0, ["crown", "ears", "teeth"])

## The kind of monster of level `level` (clamped to the ones there are).
static func for_level(level: int) -> MonsterKind:
	return kinds[clampi(level, 1, kinds.size()) - 1]
