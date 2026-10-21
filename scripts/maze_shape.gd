class_name MazeShape
extends RefCounted

## The maze's outline: a circle in the middle of its width x height grid.
## Cells inside are the maze; cells outside are solid rock (see
## MazeGenerator.OUTSIDE). Everything is in cell units, measured from the
## centre of the middle cell.

## The middle of the middle cell (the boss room's centre).
var center := Vector2.ZERO
var radius := 0.0

## The biggest circle that fits a `width` x `height` grid with a cell's
## margin to the grid's edge.
static func circle(width: int, height: int) -> MazeShape:
	var shape := MazeShape.new()
	shape.center = Vector2(width / 2, height / 2) + Vector2(0.5, 0.5)
	shape.radius = minf(width, height) / 2.0 - 1.0
	return shape

## Whether `cell` is part of the maze: its centre lies inside the outline.
func contains(cell: Vector2i) -> bool:
	return (Vector2(cell) + Vector2(0.5, 0.5)).distance_to(center) <= radius

## The cell `inset` cells in from the edge in direction `angle` (radians)
## -- e.g. for spacing start zones around the edge.
func cell_toward(angle: float, inset: float) -> Vector2i:
	var at := center + Vector2.from_angle(angle) * (radius - inset)
	return Vector2i(floori(at.x), floori(at.y))

## The outline `beyond` cells outside the edge, as `points` points going
## round -- what the border's drawn along.
func outline(points: int, beyond: float = 0.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(points):
		result.append(center + Vector2.from_angle(TAU * i / points) * (radius + beyond))
	return result
