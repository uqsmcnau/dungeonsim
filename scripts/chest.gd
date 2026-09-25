class_name ChestAgent
extends Node2D

var item_name: String = "Unknown Item"
var ability: String = "strength"
var amount: int = ItemCatalog.BONUS_AMOUNT

func setup(cell: Vector2i, cell_size: float) -> void:
	position = Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)
	var item: Dictionary = ItemCatalog.random_item()
	item_name = item["name"]
	ability = item["ability"]

## Hands over this chest's loot and removes it from the maze. Callers should
## have already removed it from any shared lookup dict before calling this.
func collect() -> Dictionary:
	var result := {"name": item_name, "ability": ability, "amount": amount}
	queue_free()
	return result
