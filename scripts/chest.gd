class_name ChestAgent
extends Node2D

## Item name -> copies this chest holds. A normal find holds exactly one;
## a chest dropped by a fallen character can hold everything they carried.
var loot: Dictionary = {}
var gold: int = 0
var rarity: String = ItemCatalog.RARITY_BRONZE

@onready var box: Polygon2D = $Box
@onready var band: Polygon2D = $Band

## A single random item of the given rarity, scattered through the maze.
func setup(cell: Vector2i, cell_size: float, item_rarity: String = ItemCatalog.RARITY_BRONZE) -> void:
	position = Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)
	rarity = item_rarity
	loot[ItemCatalog.random_item(rarity).name] = 1
	if rarity == ItemCatalog.RARITY_SILVER:
		box.color = Color(0.55, 0.58, 0.65, 1.0)
		band.color = Color(0.85, 0.88, 0.95, 1.0)
	elif rarity == ItemCatalog.RARITY_GOLD:
		box.color = Color(0.8, 0.58, 0.12, 1.0)
		band.color = Color(1.0, 0.9, 0.45, 1.0)

## Everything a fallen character was carrying, dropped on the cell they died in.
func setup_from_death(cell: Vector2i, cell_size: float, dropped_loot: Dictionary, dropped_gold: int) -> void:
	position = Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)
	loot = dropped_loot.duplicate()
	gold = dropped_gold
	box.color = Color(0.25, 0.08, 0.08, 1.0)
	band.color = Color(0.65, 0.15, 0.15, 1.0)

## Adds more loot/gold to a chest already sitting on this cell, for the rare
## case of two characters dying in the same spot.
func merge_in(dropped_loot: Dictionary, dropped_gold: int) -> void:
	for item_name in dropped_loot:
		loot[item_name] = int(loot.get(item_name, 0)) + int(dropped_loot[item_name])
	gold += dropped_gold

## Hands over everything this chest holds and removes it from the maze.
## Callers should have already removed it from any shared lookup dict before
## calling this.
func collect() -> Dictionary:
	var result := {"loot": loot, "gold": gold}
	queue_free()
	return result
