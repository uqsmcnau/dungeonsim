class_name Upkeep
extends RefCounted

## What a character sees to between fights: reading a tome, recovering when
## hurt, topping up its mana. NpcAgent has its whole party do it together
## (see NpcAgent._see_to_ourselves); these, static functions on the
## character's stat block like CombatActions, work out what, and how it
## reads.

## What a character can see to besides an item (see what_to_see_to):
## casting Recover, or resting till it can.
const RECOVER := "Recover"
const REST := "Rest"
## Below this fraction of max HP, a character stops to recover rather than
## pressing on injured.
const HEAL_THRESHOLD := 0.9
## Below this fraction of max MP, it tops up with a Mana Potion if it has
## one.
const LOW_MANA_FRACTION := 0.3

## What `stats`' character would see to, if anything ("" if not): an
## unread tome to read; when hurt, RECOVER, else a Health Potion, else REST
## -- waiting for its mana to come back; a Mana Potion when low on mana.
## Nothing heals in the storm, so no use trying there.
static func what_to_see_to(stats: NpcStats) -> String:
	var tome := pending_tome(stats)
	if tome != "":
		return tome
	if stats.hp < int(stats.max_hp * HEAL_THRESHOLD) and stats.can_heal:
		if stats.mp >= NpcStats.RECOVER_MP_COST:
			return RECOVER
		if stats.has_item("Health Potion"):
			return "Health Potion"
		return REST
	if stats.mp < int(stats.max_mp * LOW_MANA_FRACTION) and stats.has_item("Mana Potion"):
		return "Mana Potion"
	return ""

## An unread tome `stats`' character is carrying, if any — Fireball takes
## priority over Spark since it's the stronger spell. Read at the next idle
## moment, since there's no reason to delay learning a permanent spell.
static func pending_tome(stats: NpcStats) -> String:
	for item_name in ["Tome of Fireball", "Tome of Spark"]:
		if not stats.has_item(item_name):
			continue
		var spell: String = ItemCatalog.find(item_name).spell
		if not stats.knows_spell(spell):
			return item_name
	return ""

## Does `what` (see what_to_see_to, bar REST) for `stats`' character.
static func see_to(stats: NpcStats, what: String) -> void:
	if what == RECOVER:
		stats.cast_recover()
	else:
		stats.use_item(what)

## How long `what` takes: a full action, as in a fight.
static func seconds_for(what: String) -> float:
	return NpcAgent.RECOVER_CAST_SECONDS if what == RECOVER else NpcAgent.CONSUME_SECONDS

## "Casting Recover", "Drinking Health Potion", "Reading Tome of Spark".
static func doing(what: String) -> String:
	if what == RECOVER:
		return "Casting Recover"
	var verb := "Reading" if ItemCatalog.find(what).effect == "learn_spell" else "Drinking"
	return "%s %s" % [verb, what]

## How it shows on the party's map label: "✨ Recover", "Drinking Health
## Potion".
static func label(what: String) -> String:
	return "✨ Recover" if what == RECOVER else doing(what)
