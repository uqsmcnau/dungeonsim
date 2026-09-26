class_name ItemCatalog
extends RefCounted

## Base prices; what a character actually pays or gets depends on their
## charisma (see NpcStats.buy_price / sell_price).
const BUY_PRICE := 40
const SELL_PRICE := 15
## Potions are cheaper and, unlike equipment, a shop will sell any number of
## them (see NpcStats.potion_buy_price / buy_potions).
const POTION_BUY_PRICE := 15

## Equipment slots, in display order, with how many items each can hold.
const SLOT_ORDER := ["hand", "armor", "helmet", "feet", "accessory"]
const SLOT_CAPACITY := {"hand": 2, "armor": 1, "helmet": 1, "feet": 1, "accessory": 2}
const SLOT_LABELS := {"hand": "Hands", "armor": "Armor", "helmet": "Helmet", "feet": "Feet", "accessory": "Accessories"}

## Bronze items turn up in shops and ordinary chests. Silver items are
## upgraded variants that only drop from silver chests (dropped by mini
## bosses), and never appear in a shop's stock or a normal chest.
const RARITY_BRONZE := "bronze"
const RARITY_SILVER := "silver"

## Equipment sits in a slot and grants its effects for as long as it's worn.
## A consumable is used up on the spot for a one-off effect (see "effect"
## below) and never occupies a slot.
const KIND_EQUIPMENT := "equipment"
const KIND_CONSUMABLE := "consumable"

## Each equipment item goes in one slot, has a rarity, and grants a set of
## effects while equipped. An effect key is either an ability score
## (strength, dexterity, constitution, intelligence, wisdom, charisma) or a
## combat stat boosted directly (attack, defense, evasion — evasion is a
## fraction, so 0.05 is +5%).
##
## A consumable instead has an "effect" of its own: "heal_hp" or
## "restore_mp" (with an "amount"), or "learn_spell" (with a "spell" name,
## permanently unlocking that spell — see NpcStats.knows_spell).
const ITEMS := [
	{"name": "Iron Sword", "kind": "equipment", "slot": "hand", "rarity": "bronze", "effects": {"attack": 2}},
	{"name": "Shield", "kind": "equipment", "slot": "hand", "rarity": "bronze", "effects": {"defense": 1, "evasion": 0.03}},
	{"name": "Arcane Tome", "kind": "equipment", "slot": "hand", "rarity": "bronze", "effects": {"intelligence": 2}},
	{"name": "Leather Armor", "kind": "equipment", "slot": "armor", "rarity": "bronze", "effects": {"defense": 2}},
	{"name": "Helmet", "kind": "equipment", "slot": "helmet", "rarity": "bronze", "effects": {"defense": 1}},
	{"name": "Leather Boots", "kind": "equipment", "slot": "feet", "rarity": "bronze", "effects": {"defense": 1, "evasion": 0.05}},
	{"name": "Sage's Amulet", "kind": "equipment", "slot": "accessory", "rarity": "bronze", "effects": {"wisdom": 2}},
	{"name": "Silver Ring", "kind": "equipment", "slot": "accessory", "rarity": "bronze", "effects": {"charisma": 2}},

	# Silver-tier upgrades of the sword, armor and shield above.
	{"name": "Steel Sword", "kind": "equipment", "slot": "hand", "rarity": "silver", "effects": {"attack": 4}},
	{"name": "Chainmail", "kind": "equipment", "slot": "armor", "rarity": "silver", "effects": {"defense": 4}},
	{"name": "Silver Shield", "kind": "equipment", "slot": "hand", "rarity": "silver", "effects": {"defense": 2, "evasion": 0.06}},

	# Consumables. Potions don't drop from chests (see random_item) — a shop
	# is their only source, and unlike equipment it'll sell any number of them
	# (see "shop_stock" / NpcStats.buy_potions).
	{"name": "Health Potion", "kind": "consumable", "rarity": "bronze", "effect": "heal_hp", "amount": 15, "in_chests": false, "shop_stock": true},
	{"name": "Mana Potion", "kind": "consumable", "rarity": "bronze", "effect": "restore_mp", "amount": 10, "in_chests": false, "shop_stock": true},
	{"name": "Tome of Spark", "kind": "consumable", "rarity": "bronze", "effect": "learn_spell", "spell": "spark"},
	{"name": "Tome of Fireball", "kind": "consumable", "rarity": "silver", "effect": "learn_spell", "spell": "fireball"},
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
	for item in ITEMS:
		if rarity != "" and item["rarity"] != rarity:
			continue
		if kind != "" and item["kind"] != kind:
			continue
		result.append(item["name"])
	return result

## Consumables a shop keeps in stock and will sell any number of (potions),
## as opposed to equipment, which it only ever sells one of.
static func stockable_names(rarity: String = RARITY_BRONZE) -> Array:
	var result: Array = []
	for item in ITEMS:
		if item["rarity"] == rarity and item.get("shop_stock", false):
			result.append(item["name"])
	return result

## A random item of the given rarity, from whatever can drop in a chest
## (some consumables, like potions, are opted out via "in_chests": false).
static func random_item(rarity: String = RARITY_BRONZE) -> Dictionary:
	var pool: Array = []
	for item in ITEMS:
		if item["rarity"] == rarity and item.get("in_chests", true):
			pool.append(item)
	return pool[randi() % pool.size()]

static func find(item_name: String) -> Dictionary:
	for item in ITEMS:
		if item["name"] == item_name:
			return item
	return {}

static func value_of(item_name: String) -> float:
	var total := 0.0
	var effects: Dictionary = find(item_name).get("effects", {})
	for stat in effects:
		total += float(effects[stat]) * float(EFFECT_WEIGHTS.get(stat, 0.0))
	return total
