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

## Item name -> copies held.
var inventory: Dictionary = {}
var _mp_regen_accumulator: float = 0.0

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
	return strength + level

## Flat damage reduction against enemy hits.
func defense() -> int:
	return int(constitution / 2)

func move_speed() -> float:
	return 0.7 + dexterity * 0.03

## Dexterity makes attacks land more often and enemy attacks miss more often.
const DEX_HIT_STEP := 0.02

func accuracy() -> float:
	return dexterity * DEX_HIT_STEP

func evasion() -> float:
	return dexterity * DEX_HIT_STEP

## The Recover spell's healing power scales with wisdom.
func recover_power() -> int:
	return 2 + wisdom

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

func has_item(item_name: String) -> bool:
	return inventory.has(item_name)

## Copies held beyond the one that's equipped. Spares give no bonus.
func spare_count(item_name: String) -> int:
	return max(0, int(inventory.get(item_name, 0)) - 1)

func total_spares() -> int:
	var total := 0
	for item_name in inventory:
		total += spare_count(item_name)
	return total

func missing_items() -> Array:
	var result: Array = []
	for item_name in ItemCatalog.names():
		if not has_item(item_name):
			result.append(item_name)
	return result

## Takes a copy of an item into the inventory. Only one of each item can be
## equipped, so just the first copy grants its bonus; any further copy is
## held as a spare. Returns true if this copy was the one that took effect.
func acquire_item(item_name: String, ability: String, amount: int) -> bool:
	var first_copy := not has_item(item_name)
	inventory[item_name] = int(inventory.get(item_name, 0)) + 1
	if first_copy:
		_apply_bonus(ability, amount)
	return first_copy

## Sells every spare copy at the shop, keeping the equipped one of each.
## Returns how many were sold.
func sell_spares() -> int:
	var sold := 0
	for item_name in inventory.keys():
		var spares := spare_count(item_name)
		inventory[item_name] -= spares
		sold += spares
	gold += sold * sell_price()
	return sold

## Buys items that aren't owned yet, for as long as the gold lasts. Returns
## the names bought.
func buy_missing() -> Array:
	var bought: Array = []
	var missing := missing_items()
	missing.shuffle()
	for item_name in missing:
		var price := buy_price()
		if gold < price:
			break
		gold -= price
		var item := ItemCatalog.find(item_name)
		acquire_item(item_name, item["ability"], ItemCatalog.BONUS_AMOUNT)
		bought.append(item_name)
	return bought

## Whether a shop visit would accomplish anything right now.
func has_shop_business() -> bool:
	if total_spares() > 0:
		return true
	return gold >= buy_price() and not missing_items().is_empty()

## Constitution and intelligence also lift their derived pools (max HP / max
## MP) with a matching current top-up, the same way leveling does.
func _apply_bonus(ability: String, amount: int) -> void:
	match ability:
		"strength":
			strength += amount
		"dexterity":
			dexterity += amount
		"constitution":
			constitution += amount
			max_hp += amount * 2
			hp += amount * 2
		"intelligence":
			intelligence += amount
			max_mp += amount
			mp += amount
		"wisdom":
			wisdom += amount
		"charisma":
			charisma += amount

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
