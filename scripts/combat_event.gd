class_name CombatEvent
extends RefCounted

## One blow, spell, heal or escape in a fight: what GroupCombat reports on
## the combat_event signal of the player it involves, and what the battle
## window (BattleWindow) plays out. Sent the moment it happens -- before any
## death it causes is dealt with, while everyone's still who they were.

enum Kind { ACTION, ESCAPE }

var kind: Kind = Kind.ACTION
## Who did it, and to whom: the same one for a heal, and nobody for an
## escape (the actor is then the leader of the party getting away).
var actor: Node
var target: Node
## Their instance ids, which stay safe to use after a monster's been freed
## (the nodes themselves don't).
var actor_id: int = 0
var target_id: int = 0
## What they did: one of CombatRules' actions (ATTACK, SPARK, ...).
var action: String = CombatRules.ATTACK
## The damage dealt, or the HP healed (0 for a miss).
var amount: int = 0
## A plain attack that missed.
var missed := false
## A monster's critical hit.
var crit := false
## Where things stand after it.
var target_hp: int = 0
var target_max_hp: int = 0
var actor_mp: int = 0
## Whether it brought the target down.
var killed := false

## `actor` doing `action` to `target`, which has just dealt `amount` damage
## (or healed that much). A heal's always on the actor themselves, whoever
## they were facing.
static func of_action(actor: Node, target: Node, action: String, amount: int, missed: bool = false, crit: bool = false) -> CombatEvent:
	if CombatRules.is_heal(action):
		target = actor
	var ev := CombatEvent.new()
	ev.actor = actor
	ev.target = target
	ev.actor_id = actor.get_instance_id()
	ev.target_id = target.get_instance_id()
	ev.action = action
	ev.amount = amount
	ev.missed = missed
	ev.crit = crit
	ev.target_hp = maxi(0, target.stats.hp)
	ev.target_max_hp = target.stats.max_hp
	ev.actor_mp = actor.stats.mp
	ev.killed = target.stats.hp <= 0
	return ev

## `leader`'s party breaking off a fight.
static func escape(leader: NpcAgent) -> CombatEvent:
	var ev := CombatEvent.new()
	ev.kind = Kind.ESCAPE
	ev.actor = leader
	ev.actor_id = leader.get_instance_id()
	return ev

func is_heal() -> bool:
	return CombatRules.is_heal(action)
