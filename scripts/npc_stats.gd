class_name NpcStats
extends Resource

@export var level: int = 1
@export var xp: int = 0
@export var xp_to_next: int = 10

@export var max_hp: int = 20
@export var hp: int = 20
@export var max_mp: int = 10
@export var mp: int = 10

@export var strength: int = 10
@export var dexterity: int = 10
@export var constitution: int = 10
@export var intelligence: int = 10
@export var wisdom: int = 10
@export var charisma: int = 10

@export var gold: int = 0

## Item name -> copies held (worn or not).
var inventory: Dictionary = {}

## Slot name -> names of the items currently worn in it. Only worn items
## grant their effects; everything else held is a spare.
var equipped: Dictionary = {}

## Flat boosts to the derived combat stats, from equipped items.
var attack_bonus: int = 0
var defense_bonus: int = 0
var evasion_bonus: float = 0.0

## Spell names this character has learned from a tome (permanent).
var known_spells: Dictionary = {}

var _mp_regen_accumulator: float = 0.0
var _hp_regen_accumulator: float = 0.0

## Rolls fresh ability scores and derives HP/MP from them.
func roll_ability_scores() -> void:
	strength = randi_range(3, 5)
	dexterity = randi_range(3, 5)
	constitution = randi_range(3, 5)
	intelligence = randi_range(3, 5)
	wisdom = randi_range(3, 5)
	charisma = randi_range(3, 5)
	max_hp = 15 + 2 * constitution
	hp = max_hp
	max_mp = 5 + intelligence
	mp = max_mp

## The stat block for an enemy of the given level — the same categories as a
## character, filled in from its level. The ability scores are chosen so the
## shared formulas (attack = strength + level, defense = constitution / 2,
## accuracy and evasion from dexterity) give the same strength enemies had
## before they used this block. Max HP is set directly rather than derived
## from constitution, since that's what's tuned per level.
##
## For an enemy, `gold` and `xp` are what it pays out to whoever defeats it.
static func for_enemy(enemy_level: int) -> NpcStats:
	var s := NpcStats.new()
	s.level = enemy_level
	s.strength = 2 + enemy_level
	s.dexterity = (enemy_level + 1) / 2
	s.constitution = enemy_level
	s.intelligence = 2 + enemy_level / 2
	s.wisdom = 2 + enemy_level / 2
	s.charisma = 2 + enemy_level / 2
	s.max_hp = 8 + 4 * enemy_level
	s.hp = s.max_hp
	s.max_mp = 5 + s.intelligence
	s.mp = s.max_mp
	s.gold = 2 + 3 * enemy_level
	s.xp = 6 + 3 * enemy_level
	return s

## Attack grows with level as well as strength, so characters keep pace with
## the tougher enemies nearer the center as they level.
func attack_power() -> int:
	return strength + level + attack_bonus

## Flat damage reduction against enemy hits.
func defense() -> int:
	return int(constitution / 2) + defense_bonus

func move_speed() -> float:
	return 0.7 + dexterity * 0.03

## Dexterity makes attacks land more often and enemy attacks miss more often.
const DEX_HIT_STEP := 0.02

func accuracy() -> float:
	return dexterity * DEX_HIT_STEP

func evasion() -> float:
	return dexterity * DEX_HIT_STEP + evasion_bonus

## The Recover spell's healing power scales with wisdom.
func recover_power() -> int:
	return 2 + wisdom

## Spark and Fireball are attack spells taught by their tomes (see
## ItemCatalog's "learn_spell" effect). Both scale with intelligence and, as
## pure magic, ignore the target's defense entirely — the tradeoff for that
## is the MP cost and needing to have learned them in the first place.
const SPARK_MP_COST := 3
const FIREBALL_MP_COST := 7

func knows_spell(spell: String) -> bool:
	return known_spells.has(spell)

func learn_spell(spell: String) -> void:
	known_spells[spell] = true

func spark_power() -> int:
	return 2 + intelligence

func fireball_power() -> int:
	return 4 + intelligence * 2

## Each point of charisma moves shop prices this much in the character's
## favor — cheaper to buy, better paid when selling — up to the caps below.
const CHARISMA_PRICE_STEP := 0.03
const MAX_BUY_DISCOUNT := 0.5
const MAX_SELL_BONUS := 1.0

func buy_price() -> int:
	var discount: float = minf(charisma * CHARISMA_PRICE_STEP, MAX_BUY_DISCOUNT)
	return max(1, roundi(ItemCatalog.BUY_PRICE * (1.0 - discount)))

func sell_price() -> int:
	var bonus: float = minf(charisma * CHARISMA_PRICE_STEP, MAX_SELL_BONUS)
	return roundi(ItemCatalog.SELL_PRICE * (1.0 + bonus))

func potion_buy_price() -> int:
	var discount: float = minf(charisma * CHARISMA_PRICE_STEP, MAX_BUY_DISCOUNT)
	return max(1, roundi(ItemCatalog.POTION_BUY_PRICE * (1.0 - discount)))

## How many of each potion a character tries to keep on hand.
const POTION_RESERVE_TARGET := 2

## Potions below the reserve target, worth topping up at a shop.
func understocked_potions() -> Array:
	var result: Array = []
	for item_name in ItemCatalog.stockable_names(ItemCatalog.RARITY_BRONZE):
		if int(inventory.get(item_name, 0)) < POTION_RESERVE_TARGET:
			result.append(item_name)
	return result

## Buys potions up to the reserve target, for as long as the gold lasts.
## Unlike equipment, a shop will sell any number of a given potion. Returns
## the names bought (one entry per potion purchased, so duplicates appear).
func buy_potions() -> Array:
	var bought: Array = []
	var wanted := understocked_potions()
	wanted.shuffle()
	for item_name in wanted:
		while int(inventory.get(item_name, 0)) < POTION_RESERVE_TARGET:
			var price := potion_buy_price()
			if gold < price:
				return bought
			gold -= price
			acquire_item(item_name)
			bought.append(item_name)
	return bought

func has_item(item_name: String) -> bool:
	return inventory.has(item_name)

func is_equipped(item_name: String) -> bool:
	for slot in equipped:
		if equipped[slot].has(item_name):
			return true
	return false

## Names of the items worn in a slot (empty if none).
func equipped_in(slot: String) -> Array:
	return equipped.get(slot, [])

## Copies held that aren't being worn — duplicates, or items that didn't fit
## in a full slot. They give no bonus and can be sold. Consumables are never
## "spare"; they're held on purpose until used, not sold off.
func spare_count(item_name: String) -> int:
	if ItemCatalog.find(item_name).get("kind") != ItemCatalog.KIND_EQUIPMENT:
		return 0
	return max(0, int(inventory.get(item_name, 0)) - (1 if is_equipped(item_name) else 0))

func total_spares() -> int:
	var total := 0
	for item_name in inventory:
		total += spare_count(item_name)
	return total

## Bronze-tier equipment not yet owned — the shop's whole stock. Consumables
## are never sold there, and silver items never appear here; they only ever
## come from a silver chest.
func missing_items() -> Array:
	var result: Array = []
	for item_name in ItemCatalog.names(ItemCatalog.RARITY_BRONZE, ItemCatalog.KIND_EQUIPMENT):
		if not has_item(item_name):
			result.append(item_name)
	return result

## Whether this item would end up worn if we got it now: either its slot has
## room, or it's worth more than the weakest thing currently in that slot.
## Always false for a consumable — it doesn't have a slot to wear into.
func would_equip(item_name: String) -> bool:
	if ItemCatalog.find(item_name).get("kind") != ItemCatalog.KIND_EQUIPMENT:
		return false
	if is_equipped(item_name):
		return false
	var slot: String = ItemCatalog.find(item_name)["slot"]
	if equipped_in(slot).size() < int(ItemCatalog.SLOT_CAPACITY[slot]):
		return true
	return ItemCatalog.value_of(item_name) > ItemCatalog.value_of(_weakest_in(slot))

## Takes a copy of an item into the inventory and tries to wear it. Only one
## of each item can be worn, and each slot holds a limited number: a free slot
## takes it, a full slot swaps out its weakest item if this one is better, and
## otherwise it's kept as a spare. Returns true only if this copy is the one
## that got worn (a duplicate of something already worn returns false).
func acquire_item(item_name: String) -> bool:
	inventory[item_name] = int(inventory.get(item_name, 0)) + 1
	if not would_equip(item_name):
		return false
	var slot: String = ItemCatalog.find(item_name)["slot"]
	if equipped_in(slot).size() >= int(ItemCatalog.SLOT_CAPACITY[slot]):
		_unequip(_weakest_in(slot))
	_equip(item_name)
	return true

## Uses up one copy of a consumable (a potion drunk or a tome read).
func consume_item(item_name: String) -> void:
	if not inventory.has(item_name):
		return
	inventory[item_name] -= 1
	if inventory[item_name] <= 0:
		inventory.erase(item_name)

## Sells every item that isn't being worn. Returns how many were sold.
func sell_spares() -> int:
	var sold := 0
	for item_name in inventory.keys():
		var spares := spare_count(item_name)
		if spares <= 0:
			continue
		inventory[item_name] -= spares
		sold += spares
		if inventory[item_name] <= 0:
			inventory.erase(item_name)
	gold += sold * sell_price()
	return sold

## Buys items it doesn't have, for as long as the gold lasts — but only ones
## that would actually be worn, so it doesn't pay for something useless.
## Returns the names bought.
func buy_missing() -> Array:
	var bought: Array = []
	var missing := missing_items()
	missing.shuffle()
	for item_name in missing:
		if not would_equip(item_name):
			continue
		var price := buy_price()
		if gold < price:
			break
		gold -= price
		acquire_item(item_name)
		bought.append(item_name)
	return bought

## Whether a shop visit would accomplish anything right now.
func has_shop_business() -> bool:
	if total_spares() > 0:
		return true
	if gold >= potion_buy_price() and not understocked_potions().is_empty():
		return true
	if gold < buy_price():
		return false
	for item_name in missing_items():
		if would_equip(item_name):
			return true
	return false

func _weakest_in(slot: String) -> String:
	var weakest := ""
	var weakest_value := INF
	for item_name in equipped_in(slot):
		var v := ItemCatalog.value_of(item_name)
		if v < weakest_value:
			weakest = item_name
			weakest_value = v
	return weakest

func _equip(item_name: String) -> void:
	var item := ItemCatalog.find(item_name)
	if not equipped.has(item["slot"]):
		equipped[item["slot"]] = []
	equipped[item["slot"]].append(item_name)
	_apply_effects(item["effects"], 1)

func _unequip(item_name: String) -> void:
	var item := ItemCatalog.find(item_name)
	equipped[item["slot"]].erase(item_name)
	_apply_effects(item["effects"], -1)

## Applies (sign 1) or takes back (sign -1) an item's effects. An effect is
## either an ability score or one of the combat stats boosted directly
## (attack, defense, evasion). Constitution and intelligence also move their
## derived pools (max HP / max MP) — raising them tops up the current value
## like leveling does, and lowering them never drops current HP below 1.
func _apply_effects(effects: Dictionary, sign: int) -> void:
	for stat in effects:
		var amount: int = int(effects[stat]) * sign
		match stat:
			"strength":
				strength += amount
			"dexterity":
				dexterity += amount
			"constitution":
				constitution += amount
				max_hp += amount * 2
				hp = clampi(hp + (amount * 2 if sign > 0 else 0), 1, max_hp)
			"intelligence":
				intelligence += amount
				max_mp += amount
				mp = clampi(mp + (amount if sign > 0 else 0), 0, max_mp)
			"wisdom":
				wisdom += amount
			"charisma":
				charisma += amount
			"attack":
				attack_bonus += amount
			"defense":
				defense_bonus += amount
			"evasion":
				evasion_bonus += float(effects[stat]) * sign

## MP regenerates passively over time at a baseline of 1 per second, scaled
## by intelligence (an INT of 5 — the top of the starting range — gives
## exactly that baseline rate; higher INT from leveling regens faster).
func regen_mp(delta: float) -> void:
	if mp >= max_mp:
		_mp_regen_accumulator = 0.0
		return
	var rate: float = intelligence / 5.0
	_mp_regen_accumulator += rate * delta
	while _mp_regen_accumulator >= 1.0 and mp < max_mp:
		_mp_regen_accumulator -= 1.0
		mp += 1

## Passive HP regeneration for monsters recovering outside combat, at a
## baseline of 1 per second scaled by constitution — the same shape as
## regen_mp. Callers are expected to only invoke this while not in combat.
func regen_hp(delta: float) -> void:
	if hp >= max_hp:
		_hp_regen_accumulator = 0.0
		return
	var rate: float = constitution / 5.0
	_hp_regen_accumulator += rate * delta
	while _hp_regen_accumulator >= 1.0 and hp < max_hp:
		_hp_regen_accumulator -= 1.0
		hp += 1

## Adds xp, applying as many level-ups as the amount covers. Returns true
## if at least one level-up occurred.
func add_xp(amount: int) -> bool:
	xp += amount
	var leveled_up := false
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = int(xp_to_next * 1.5)
		max_hp += 6
		hp = max_hp
		max_mp += 2
		mp = max_mp
		_boost_random_ability()
		leveled_up = true
	return leveled_up

func _boost_random_ability() -> void:
	match randi() % 6:
		0: strength += 1
		1: dexterity += 1
		2: constitution += 1
		3: intelligence += 1
		4: wisdom += 1
		5: charisma += 1
