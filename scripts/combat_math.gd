class_name CombatMath
extends RefCounted

## Pure combat-odds math shared by monster fights and PvP fights. Every
## function takes both sides' stat blocks explicitly rather than reading
## from a specific character, so the same code works identically whether
## it's a player attacking a monster, a monster retaliating, or one player
## fighting another.

## The attacker's own expected output gets a slightly higher bonus than the
## defender's counter-attack does (1.5 vs 1.0) — a deliberate asymmetry, not
## a mistake. It's why two IDENTICAL characters come out just barely above a
## 50/50 win chance against each other rather than landing on an exact tie
## (see test_win_chance_against_an_identical_opponent_is_just_above_half).
const OUTGOING_DAMAGE_BONUS := 1.5
const INCOMING_DAMAGE_BONUS := 1.0

## Chance `attacker`'s plain attack lands on `defender`.
static func hit_chance_against(attacker: NpcStats, defender: NpcStats) -> float:
	return CombatRules.hit_chance(attacker.accuracy(), defender.evasion())

## Average damage of one of `me`'s own hits on `opponent`, assuming it lands.
static func damage_dealt_per_hit(me: NpcStats, opponent: NpcStats) -> float:
	return max(1.0, me.attack_power() + OUTGOING_DAMAGE_BONUS - opponent.defense())

## Average damage of one of `opponent`'s hits on `me`, assuming it lands.
static func damage_taken_per_hit(me: NpcStats, opponent: NpcStats) -> float:
	return max(1.0, opponent.attack_power() + INCOMING_DAMAGE_BONUS - me.defense())

## Average damage per turn `me` deals to `opponent`, counting the turns an
## attack misses.
static func expected_damage_dealt(me: NpcStats, opponent: NpcStats) -> float:
	return hit_chance_against(me, opponent) * damage_dealt_per_hit(me, opponent)

static func expected_damage_taken(me: NpcStats, opponent: NpcStats) -> float:
	return hit_chance_against(opponent, me) * damage_taken_per_hit(me, opponent)

## Compares how many turns it'd take `me` to kill `opponent` against how
## many it would take to be killed first — the same estimate both a
## monster fight's coin-flip and a player's "can I win this" judgment (PvP
## initiation, party-merge confidence) are based on.
static func win_chance_against(me: NpcStats, opponent: NpcStats) -> float:
	var turns_to_kill: float = max(opponent.hp, 1) / expected_damage_dealt(me, opponent)
	var turns_to_die: float = max(me.hp, 1) / expected_damage_taken(me, opponent)
	return clampf(turns_to_die / (turns_to_die + turns_to_kill), 0.05, 0.95)

## win_chance_against for two sides of several fighters each (NpcStats
## both): a party against a boss's party, say. Each side's damage is pooled,
## as though spread evenly over the other side, and its HP too -- so one
## against one, it's win_chance_against.
static func group_win_chance(mine: Array, theirs: Array) -> float:
	var our_hp := 0.0
	var their_hp := 0.0
	var our_damage := 0.0
	var their_damage := 0.0
	for me in mine:
		our_hp += max(me.hp, 1)
	for foe in theirs:
		their_hp += max(foe.hp, 1)
	for me in mine:
		for foe in theirs:
			our_damage += expected_damage_dealt(me, foe) / theirs.size()
			their_damage += expected_damage_taken(me, foe) / mine.size()
	var turns_to_kill := their_hp / our_damage
	var turns_to_die := our_hp / their_damage
	return clampf(turns_to_die / (turns_to_die + turns_to_kill), 0.05, 0.95)

## Fights with a probability that reflects the odds — even a long-shot
## occasionally gets taken.
static func decide_fight(me: NpcStats, opponent: NpcStats) -> bool:
	return randf() < win_chance_against(me, opponent)
