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

## Remembers any shop `npc` can see right now.
static func notice(npc: NpcAgent) -> void:
	var seen := MazeQuery.nearest_visible(npc.grid, npc.cell_pos, NpcAgent.SIGHT_RANGE, npc.shops)
	if seen != MazeQuery.NONE:
		npc.known_shops[seen] = true

## Next step toward the nearest shop `npc` knows of with something to do
## there (spare items to sell, potions to stock up on, or gold for an item
## not owned yet -- a silver shop's dearer stock, at a silver one) -- or its
## own cell if there's none.
static func step(npc: NpcAgent) -> Vector2i:
	var nearest := MazeQuery.NONE
	var nearest_dist := 1 << 30
	for c in npc.known_shops:
		if NpcRoutes.storm_cells(npc).has(c):
			continue  # not worth a trip into the storm
		if not party_has_business(npc, rarity_at(npc, c)):
			continue
		var d: int = abs(c.x - npc.cell_pos.x) + abs(c.y - npc.cell_pos.y)
		if d < nearest_dist:
			nearest = c
			nearest_dist = d
	if nearest == MazeQuery.NONE:
		return npc.cell_pos
	return NpcRoutes.step_toward(npc, nearest, PATH_DEPTH)

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
