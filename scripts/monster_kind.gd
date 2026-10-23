class_name MonsterKind
extends RefCounted

## One kind of monster (see MonsterCatalog): what it's called, and how it's
## drawn -- on the map, its outline in its colour; in the battle window, a
## bigger body of the same outline, with a face and its features.

var name: String
var color: Color
## Its outline (see outline): `sides` points round, every other one pulled
## in to `inner` of the way out for a star (1 for none), turned by `turn`
## degrees and stretched by `stretch`.
var sides: int
var inner: float
var turn: float
var stretch: Vector2
## How big it's drawn in battle, against an ordinary monster's 1.
var size: float
## What marks it out in battle (see BattlePainter.draw_monster): "wings",
## "tail", "ears", "horns", "crown", "shine", "cracks", "teeth", "tusks",
## "sockets", "ghostly".
var features: Array[String] = []

func _init(kind_name: String, kind_color: Color, kind_sides: int, kind_inner: float, kind_turn: float,
		kind_stretch: Vector2, kind_size: float, kind_features: Array) -> void:
	name = kind_name
	color = kind_color
	sides = kind_sides
	inner = kind_inner
	turn = kind_turn
	stretch = kind_stretch
	size = kind_size
	features.assign(kind_features)

## Its outline, as points round its middle at a radius of about 1.
func outline() -> PackedVector2Array:
	var corners: int = sides * (2 if inner < 1.0 else 1)
	var points := PackedVector2Array()
	for i in range(corners):
		var a := deg_to_rad(turn) + TAU * i / corners
		var reach := inner if inner < 1.0 and i % 2 == 1 else 1.0
		points.append(Vector2(cos(a), sin(a)) * reach * stretch)
	return points

## "a Troll", "an Orc", "the Dragon" -- its name with the article that goes
## with it.
func called(the: bool = false) -> String:
	if the:
		return "the " + name
	return ("an " if "AEIOU".contains(name[0]) else "a ") + name

func has(feature: String) -> bool:
	return features.has(feature)
