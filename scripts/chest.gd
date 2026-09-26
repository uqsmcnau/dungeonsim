class_name ChestAgent
extends Node2D

var item_name: String = "Unknown Item"
var rarity: String = ItemCatalog.RARITY_BRONZE

@onready var box: Polygon2D = $Box
@onready var band: Polygon2D = $Band

func setup(cell: Vector2i, cell_size: float, item_rarity: String = ItemCatalog.RARITY_BRONZE) -> void:
	position = Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)
	rarity = item_rarity
	item_name = ItemCatalog.random_item(rarity)["name"]
	if rarity == ItemCatalog.RARITY_SILVER:
		box.color = Color(0.55, 0.58, 0.65, 1.0)
		band.color = Color(0.85, 0.88, 0.95, 1.0)

## Hands over this chest's item and removes it from the maze. Callers should
## have already removed it from any shared lookup dict before calling this.
func collect() -> String:
	var result := item_name
	queue_free()
	return result
