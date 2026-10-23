class_name Item
extends RefCounted

## One item (see ItemCatalog): a piece of equipment, worn in a slot for its
## effects for as long as it's worn, or a consumable, used up on the spot
## for a one-off effect and never taking a slot.

var name: String
## ItemCatalog.KIND_EQUIPMENT or ItemCatalog.KIND_CONSUMABLE.
var kind: String
## ItemCatalog.RARITY_BRONZE, _SILVER or _GOLD.
var rarity: String
## Equipment: the slot it's worn in (see ItemCatalog.SLOT_CAPACITY), and
## what it grants while it's worn -- ability scores (strength, dexterity,
## constitution, intelligence, wisdom, charisma) or combat stats boosted
## directly (attack, defense, evasion -- a fraction, so 0.05 is +5%).
var slot := ""
var effects: Dictionary = {}
## A consumable: "heal_hp" or "restore_mp" (by `amount`), or "learn_spell"
## (`spell`, for good -- see NpcStats.knows_spell).
var effect := ""
var amount := 0
var spell := ""
## Whether it can turn up in a chest (see ItemCatalog.random_item), and
## whether a shop sells any number of it rather than just one (potions --
## see ItemCatalog.stockable_names).
var in_chests := true
var shop_stock := false

## A piece of equipment, worn in `item_slot` for `item_effects`.
static func gear(item_name: String, item_slot: String, item_rarity: String, item_effects: Dictionary) -> Item:
	var item := Item.new()
	item.name = item_name
	item.kind = ItemCatalog.KIND_EQUIPMENT
	item.slot = item_slot
	item.rarity = item_rarity
	item.effects = item_effects
	return item

## A consumable that does `item_effect` -- with `amount` or `spell` as that
## needs -- and that `shop_only` (potions) a shop sells any number of, and
## never turns up in a chest.
static func consumable(item_name: String, item_rarity: String, item_effect: String, item_amount: int = 0,
		item_spell: String = "", shop_only: bool = false) -> Item:
	var item := Item.new()
	item.name = item_name
	item.kind = ItemCatalog.KIND_CONSUMABLE
	item.rarity = item_rarity
	item.effect = item_effect
	item.amount = item_amount
	item.spell = item_spell
	item.in_chests = not shop_only
	item.shop_stock = shop_only
	return item

func is_equipment() -> bool:
	return kind == ItemCatalog.KIND_EQUIPMENT
