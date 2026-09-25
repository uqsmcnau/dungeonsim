class_name CombatRules
extends RefCounted

const BASE_HIT_CHANCE := 0.8
const MIN_HIT_CHANCE := 0.3
const MAX_HIT_CHANCE := 0.98

## Chance an attack lands: a base chance, raised by the attacker's accuracy
## and lowered by the defender's evasion, and never certain either way.
static func hit_chance(accuracy: float, evasion: float) -> float:
	return clampf(BASE_HIT_CHANCE + accuracy - evasion, MIN_HIT_CHANCE, MAX_HIT_CHANCE)
