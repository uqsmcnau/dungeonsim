class_name ItemCatalog
extends RefCounted

const BONUS_AMOUNT := 2
## Base prices; what a character actually pays or gets depends on their
## charisma (see NpcStats.buy_price / sell_price).
const BUY_PRICE := 40
const SELL_PRICE := 15

const ITEMS := [
	{"name": "Iron Sword", "ability": "strength"},
	{"name": "Leather Boots", "ability": "dexterity"},
	{"name": "Chainmail", "ability": "constitution"},
	{"name": "Arcane Tome", "ability": "intelligence"},
	{"name": "Sage's Amulet", "ability": "wisdom"},
	{"name": "Silver Ring", "ability": "charisma"},
]

static func names() -> Array:
	var result: Array = []
	for item in ITEMS:
		result.append(item["name"])
	return result

static func random_item() -> Dictionary:
	return ITEMS[randi() % ITEMS.size()]

static func find(item_name: String) -> Dictionary:
	for item in ITEMS:
		if item["name"] == item_name:
			return item
	return {}
