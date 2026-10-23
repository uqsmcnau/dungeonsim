class_name ItemCatalog
extends RefCounted

## Base prices; what a character actually pays or gets depends on their
## charisma (see NpcStats.buy_price / sell_price). A silver shop's gear (see
## NpcStats.missing_items) costs more than a bronze shop's.
const BUY_PRICE := 40
const SILVER_BUY_PRICE := 90
const SELL_PRICE := 15
## Potions are cheaper and, unlike equipment, a shop will sell any number of
## them (see NpcStats.potion_buy_price / buy_potions).
const POTION_BUY_PRICE := 15

## Equipment slots, in display order, with how many items each can hold.
const SLOT_ORDER := ["hand", "armor", "helmet", "feet", "accessory"]
const SLOT_CAPACITY := {"hand": 2, "armor": 1, "helmet": 1, "feet": 1, "accessory": 2}
const SLOT_LABELS := {"hand": "Hands", "armor": "Armor", "helmet": "Helmet", "feet": "Feet", "accessory": "Accessories"}

## Bronze items turn up in shops and ordinary chests. Silver items are
## upgraded variants found in silver chests (left by an Orc Chieftain's
## party, once it's beaten) and sold only at the two silver shops; gold
## items, the best of all, only in gold chests (left by an Ogre Warlord's
## party) -- neither ever turns up in a normal chest.
const RARITY_BRONZE := "bronze"
const RARITY_SILVER := "silver"
const RARITY_GOLD := "gold"

## Equipment sits in a slot and grants its effects for as long as it's worn.
## A consumable is used up on the spot for a one-off effect and never
## occupies a slot (see Item).
const KIND_EQUIPMENT := "equipment"
const KIND_CONSUMABLE := "consumable"

## Every item there is.
static var items: Array[Item] = [
	Item.gear("Iron Sword", "hand", RARITY_BRONZE, {"attack": 2}),
	Item.gear("Shield", "hand", RARITY_BRONZE, {"defense": 1, "evasion": 0.03}),
	Item.gear("Arcane Tome", "hand", RARITY_BRONZE, {"intelligence": 2}),
	Item.gear("Leather Armor", "armor", RARITY_BRONZE, {"defense": 2}),
	Item.gear("Helmet", "helmet", RARITY_BRONZE, {"defense": 1}),
	Item.gear("Leather Boots", "feet", RARITY_BRONZE, {"defense": 1, "evasion": 0.05}),
	Item.gear("Sage's Amulet", "accessory", RARITY_BRONZE, {"wisdom": 2}),
	Item.gear("Silver Ring", "accessory", RARITY_BRONZE, {"charisma": 2}),

	# Silver tier: an upgrade of each bronze piece above.
	Item.gear("Steel Sword", "hand", RARITY_SILVER, {"attack": 4}),
	Item.gear("Chainmail", "armor", RARITY_SILVER, {"defense": 4}),
	Item.gear("Silver Shield", "hand", RARITY_SILVER, {"defense": 2, "evasion": 0.06}),
	Item.gear("Enchanted Tome", "hand", RARITY_SILVER, {"intelligence": 3, "wisdom": 1}),
	Item.gear("Steel Helm", "helmet", RARITY_SILVER, {"defense": 2}),
	Item.gear("Swift Boots", "feet", RARITY_SILVER, {"defense": 1, "evasion": 0.07, "dexterity": 1}),
	Item.gear("Moonstone Amulet", "accessory", RARITY_SILVER, {"wisdom": 3, "intelligence": 1}),
	Item.gear("Ring of Vigor", "accessory", RARITY_SILVER, {"constitution": 2, "charisma": 1}),

	# Gold tier: upgrades of the silver gear, and the best of every other slot.
	Item.gear("Mithril Sword", "hand", RARITY_GOLD, {"attack": 6}),
	Item.gear("Aegis Shield", "hand", RARITY_GOLD, {"defense": 3, "evasion": 0.1}),
	Item.gear("Archmage's Staff", "hand", RARITY_GOLD, {"intelligence": 4, "wisdom": 2}),
	Item.gear("Plate Armor", "armor", RARITY_GOLD, {"defense": 6}),
	Item.gear("Golden Helm", "helmet", RARITY_GOLD, {"defense": 2, "constitution": 2}),
	Item.gear("Winged Boots", "feet", RARITY_GOLD, {"defense": 2, "evasion": 0.1, "dexterity": 2}),
	Item.gear("Ring of Might", "accessory", RARITY_GOLD, {"strength": 3, "constitution": 2}),

	# Consumables. Potions never turn up in a chest -- a shop is their only
	# source, and unlike equipment it'll sell any number of them (see
	# NpcStats.buy_potions).
	Item.consumable("Health Potion", RARITY_BRONZE, "heal_hp", 15, "", true),
	Item.consumable("Mana Potion", RARITY_BRONZE, "restore_mp", 10, "", true),
	Item.consumable("Tome of Spark", RARITY_BRONZE, "learn_spell", 0, "spark"),
	Item.consumable("Tome of Fireball", RARITY_SILVER, "learn_spell", 0, "fireball"),
]

## How much each kind of effect is worth when deciding which of two items
## deserves a contested slot. Combat stats count for the most.
const EFFECT_WEIGHTS := {
	"attack": 1.0, "defense": 1.0, "evasion": 20.0,
	"strength": 1.0, "dexterity": 1.0, "constitution": 1.0,
	"intelligence": 0.5, "wisdom": 0.5, "charisma": 0.5,
}

## All item names, optionally narrowed by rarity and/or kind (e.g. a shop's
## stock is bronze-tier equipment only).
static func names(rarity: String = "", kind: String = "") -> Array:
	var result: Array = []
	for item in items:
		if rarity != "" and item.rarity != rarity:
			continue
		if kind != "" and item.kind != kind:
			continue
		result.append(item.name)
	return result

## Consumables a shop keeps in stock and will sell any number of (potions),
## as opposed to equipment, which it only ever sells one of.
static func stockable_names(rarity: String = RARITY_BRONZE) -> Array:
	var result: Array = []
	for item in items:
		if item.rarity == rarity and item.shop_stock:
			result.append(item.name)
	return result

## A random item of the given rarity, from whatever can drop in a chest
## (not potions -- see Item.in_chests).
static func random_item(rarity: String = RARITY_BRONZE) -> Item:
	var pool: Array = items.filter(func(item): return item.rarity == rarity and item.in_chests)
	return pool[randi() % pool.size()]

## The item called `item_name`, or null if there's no such item.
static func find(item_name: String) -> Item:
	for item in items:
		if item.name == item_name:
			return item
	return null

static func value_of(item_name: String) -> float:
	var total := 0.0
	var effects: Dictionary = find(item_name).effects
	for stat in effects:
		total += float(effects[stat]) * float(EFFECT_WEIGHTS.get(stat, 0.0))
	return total
