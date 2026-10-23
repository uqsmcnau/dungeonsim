class_name CombatRules
extends RefCounted

const BASE_HIT_CHANCE := 0.8
const MIN_HIT_CHANCE := 0.3
const MAX_HIT_CHANCE := 0.98

## Chance an attack lands: a base chance, raised by the attacker's accuracy
## and lowered by the defender's evasion, and never certain either way.
static func hit_chance(accuracy: float, evasion: float) -> float:
	return clampf(BASE_HIT_CHANCE + accuracy - evasion, MIN_HIT_CHANCE, MAX_HIT_CHANCE)

## The actions a fighter can take on their turn (see
## CombatActions), as they're named in
## combat events (see CombatEvent). Use these rather than the bare
## strings: a misspelt constant fails when the script loads, where a
## misspelt string quietly turned into a plain attack.
const ATTACK := "attack"
const SPARK := "spark"
const FIREBALL := "fireball"
const POTION := "potion_hp"

## What each action's called when it's announced (the battle window's
## caption, a killing blow's description). A plain attack goes unannounced.
const ACTION_NAMES := {SPARK: "Spark", FIREBALL: "Fireball", POTION: "Health Potion"}

## Whether `action` heals whoever takes it, rather than hitting their foe.
## (Recover's no combat action: it's only cast between fights.)
static func is_heal(action: String) -> bool:
	return action == POTION

## Whether `action` is a spell cast at a foe (as opposed to a weapon blow).
static func is_offensive_spell(action: String) -> bool:
	return action == SPARK or action == FIREBALL
