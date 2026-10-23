class_name Shopping
extends RefCounted

## A party's dealings with the shops: spotting them, which one's worth the
## trip, and the visit itself. Bronze shops sell the bronze gear, the two
## silver ones near the middle the silver gear (see NpcStats.missing_items);
## every shop sells potions and buys spares. NpcAgent decides when (see
## NpcAgent._start_shopping); these, static functions taking the character
## like PartyOps and NpcRoutes, work out where and what.

## How far a route to a known shop is looked for, in steps.
const PATH_DEPTH := 80
## How long a visit takes, in game seconds.
const SECONDS := 1.0
## How many steps a shop with no way there round monsters (or without
## leaving safe ground) is set aside for -- as a chest is, see
## NpcAgent.CHEST_SKIP_STEPS.
const SKIP_STEPS := 12

## Remembers any shop `npc` can see right now.
static func notice(npc: NpcAgent) -> void:
	var seen := MazeQuery.nearest_visible(npc.grid, npc.cell_pos, NpcAgent.SIGHT_RANGE, npc.shops)
	if seen != MazeQuery.NONE:
		npc.known_shops[seen] = true

## Next step toward the nearest shop `npc` knows of with something to do
## there (spare items to sell, potions to stock up on, or gold for an item
## not owned yet -- a silver shop's dearer stock, at a silver one) -- or its
## own cell if there's none.
##
## Once it's picked a shop it keeps going for that one (NpcAgent.shop_goal)
## while it's still worth it: "nearest" is as the crow flies, and the
## winding ways there could otherwise have it turn from one shop to another
## and back with every step.
##
## Routes round monsters and the storm, as for a chest: a shop with no way
## there that avoids them is set aside for SKIP_STEPS steps. Otherwise the
## step that the shop wanted and a monster blocked would go to the next
## thing on the list, a chest say, whose step could lead straight back --
## back and forth for ever. Only the monsters in sight, though: a shop can
## be a long way off, and steering round monsters wandering about far away
## had the way there change with every step they took -- this way, then
## back that way... And a way there that turns straight back the way its
## last step came -- a monster pacing alongside, the far side of a wall,
## blocking one way round and then the other -- has the shop set aside too.
static func step(npc: NpcAgent) -> Vector2i:
	for c in npc.skipped_shops.keys():
		npc.skipped_shops[c] -= 1
		if npc.skipped_shops[c] <= 0:
			npc.skipped_shops.erase(c)
	if npc.shop_goal == MazeQuery.NONE or npc.shop_goal == npc.cell_pos or not _worth_going_to(npc, npc.shop_goal):
		npc.shop_goal = _nearest_worth_going_to(npc)
		npc.shop_step_from = MazeQuery.NONE
	var goal := npc.shop_goal
	if goal == MazeQuery.NONE or goal == npc.cell_pos:
		return npc.cell_pos
	var next := NpcRoutes.step_toward(npc, goal, PATH_DEPTH, NpcRoutes.live_enemy_cells(npc, NpcAgent.SIGHT_RANGE))
	if next == npc.cell_pos or NpcRoutes.leaves_safe_ground(npc, next) or next == npc.shop_step_from:
		npc.skipped_shops[goal] = SKIP_STEPS
		npc.shop_goal = MazeQuery.NONE
		npc.shop_step_from = MazeQuery.NONE
		return npc.cell_pos
	npc.shop_step_from = npc.cell_pos
	return next

## Whether the known shop on `cell` is worth `npc`'s heading for: out of the
## storm, not set aside, and with business there for its party.
static func _worth_going_to(npc: NpcAgent, cell: Vector2i) -> bool:
	if NpcRoutes.storm_cells(npc).has(cell) or npc.skipped_shops.has(cell):
		return false
	return npc.known_shops.has(cell) and party_has_business(npc, rarity_at(npc, cell))

static func _nearest_worth_going_to(npc: NpcAgent) -> Vector2i:
	return MazeQuery.nearest(npc.cell_pos, npc.known_shops.keys().filter(func(c): return _worth_going_to(npc, c)))

## Whether a visit to a shop of `rarity` would do anything for anyone in
## `npc`'s party -- the whole party shops together (see trade).
static func party_has_business(npc: NpcAgent, rarity: String = ItemCatalog.RARITY_BRONZE) -> bool:
	for member in npc.living_party():
		if member.stats.has_shop_business(rarity):
			return true
	return false

## What kind of shop is on `cell`, as `npc` knows the shops: bronze, or one
## of the silver shops near the middle.
static func rarity_at(npc: NpcAgent, cell: Vector2i) -> String:
	var rarity = npc.shops.get(cell)
	return rarity if rarity is String else ItemCatalog.RARITY_BRONZE

## A party's visit to a shop of `rarity`, `members` in the order they get
## first refusal: spares go to party-mates who'd wear them first, then
## everyone sells what's left and buys what their own gold stretches to.
## Returns how many items were sold and bought, as Vector2i(sold, bought).
static func trade(members: Array, rarity: String) -> Vector2i:
	PartyOps.pass_spares_around(members)
	var sold := 0
	var bought := 0
	for member in members:
		sold += member.stats.sell_spares()
		bought += member.stats.buy_missing(rarity).size()
		bought += member.stats.buy_potions().size()
	return Vector2i(sold, bought)
