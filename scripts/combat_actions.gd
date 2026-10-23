class_name CombatActions
extends RefCounted

## What a character does with its turn in a fight -- a plain attack, a
## spell, a potion (see CombatRules for their names) -- and what comes of
## it. Shared between a monster fight and a player-vs-player one (see
## GroupCombat): only what each side does with the result differs. Static
## functions on the character's stat block, like CombatMath.

## Below this fraction of max HP, a character mid-fight drinks a Health
## Potion if it has one.
const HEAL_THRESHOLD := 0.5

## Survival first (a Health Potion, if it has one -- Recover can't be cast
## mid-fight, only between fights: see Upkeep), then whichever of `me`'s
## attack spells or a plain attack actually deals the most damage to
## `opponent` right now. A spell's damage is fixed by intelligence while a
## plain attack scales with strength, level and weapon bonuses, so a spell
## that out-damages a fresh character is often no longer the better choice
## once they've leveled up or found a sword — this compares them fresh each
## turn rather than always preferring magic once it's known.
static func choose(me: NpcStats, opponent: NpcStats) -> String:
	var hurt := me.hp < int(me.max_hp * HEAL_THRESHOLD)
	if hurt and me.can_heal and me.has_item("Health Potion"):
		return CombatRules.POTION

	var best_action := CombatRules.ATTACK
	var best_damage: float = CombatMath.expected_damage_dealt(me, opponent)
	if me.knows_spell("spark") and me.mp >= NpcStats.SPARK_MP_COST and me.spark_power() > best_damage:
		best_action = CombatRules.SPARK
		best_damage = me.spark_power()
	if me.knows_spell("fireball") and me.mp >= NpcStats.FIREBALL_MP_COST and me.fireball_power() > best_damage:
		best_action = CombatRules.FIREBALL
		best_damage = me.fireball_power()
	return best_action

## Applies `action` (see choose), taken by `me`, against `opponent`.
## Returns what happened, for the battle window: {"amount": the damage dealt
## or HP healed, "missed": whether a plain attack missed}.
static func apply(me: NpcStats, action: String, opponent: NpcStats) -> Dictionary:
	var hp_before: int = me.hp
	var damage := 0
	match action:
		CombatRules.POTION:
			me.use_item("Health Potion")
		CombatRules.FIREBALL:
			me.mp -= NpcStats.FIREBALL_MP_COST
			damage = max(1, me.fireball_power())
		CombatRules.SPARK:
			me.mp -= NpcStats.SPARK_MP_COST
			damage = max(1, me.spark_power())
		_:
			if randf() >= CombatMath.hit_chance_against(me, opponent):
				return {"amount": 0, "missed": true}
			damage = max(1, me.attack_power() + randi() % 4 - opponent.defense())
	if CombatRules.is_heal(action):
		return {"amount": me.hp - hp_before, "missed": false}
	opponent.hp -= damage
	return {"amount": damage, "missed": false}

## `action` (see apply), taken by `me`, as a killing blow: the spell cast,
## or whatever weapon they're wielding -- "Fireball for 12 damage", "Iron
## Sword for 6 damage", "Bare hands for 3 damage".
static func killing_blow(me: NpcStats, action: String, damage: int) -> String:
	var weapon := "Bare hands"
	if CombatRules.is_offensive_spell(action):
		weapon = CombatRules.ACTION_NAMES[action]
	else:
		for item_name in me.equipped_in("hand"):
			if ItemCatalog.find(item_name).effects.has("attack"):
				weapon = item_name
				break
	return "%s for %d damage" % [weapon, damage]
