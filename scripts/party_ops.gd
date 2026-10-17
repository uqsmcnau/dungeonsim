class_name PartyOps
extends RefCounted

## Party-merge mechanics shared by NpcAgent: deciding whether two parties
## can band together instead of fighting, actually merging them, and
## promoting a new leader if one falls. These take the NpcAgent(s) involved
## as explicit parameters rather than living as instance methods, since
## "self" would otherwise be ambiguous between (for example) the character
## joining a party and the party it's joining.

const MAX_PARTY_SIZE := 4
## A meaningfully higher bar than the 50/50 "thinks it can probably win" used
## to decide whether to throw a punch at all — "confident" means a clear
## edge, not a coin flip. This also matters because of CombatMath's
## attacker/defender damage asymmetry, which means even two IDENTICAL
## characters compute themselves as having a razor-thin edge over one
## another; a bar of 0.5 would make this check nearly always true and the
## "form a party" rule nearly vacuous.
const SOLO_CONFIDENCE_THRESHOLD := 0.65
const PARTY_OFFSETS := [Vector2.ZERO, Vector2(10, -10), Vector2(-10, 10), Vector2(10, 10)]

static func assign_party_offsets(leader: NpcAgent) -> void:
	for i in range(leader.party.size()):
		if is_instance_valid(leader.party[i]):
			leader.party[i].party_offset = PARTY_OFFSETS[i % PARTY_OFFSETS.size()]

## Whether `npc` (Evil) is confident it could take on everyone else in a
## prospective merge all by itself — checked against the toughest of them
## by level, since if it can't beat the strongest, it can't beat them all.
static func confident_solo_against(npc: NpcAgent, others: Array) -> bool:
	if others.is_empty():
		return false
	var toughest: NpcAgent = others[0]
	for o in others:
		if o.stats.level > toughest.stats.level:
			toughest = o
	return CombatMath.win_chance_against(npc.stats, toughest.stats) > SOLO_CONFIDENCE_THRESHOLD

## Whether `npc`'s party and `opponent`'s party can merge instead of
## fighting. Good and Neutral characters always band together with each
## other (and with each other's parties); Good and Evil never band together,
## matching the fact that Good actively hunts Evil; Evil only bands together
## with other Evil, and only if nobody in the combined group is confident it
## could take everyone else by itself — otherwise it'd rather go it alone (or
## try its luck fighting) than share the spoils.
static func can_form_party_with(npc: NpcAgent, opponent: NpcAgent) -> bool:
	if npc.party.size() + opponent.party.size() > MAX_PARTY_SIZE:
		return false

	var i_am_evil := npc.stats.alignment == NpcStats.ALIGNMENT_EVIL
	var they_are_evil := opponent.stats.alignment == NpcStats.ALIGNMENT_EVIL
	if i_am_evil != they_are_evil:
		return false

	if i_am_evil:
		var everyone: Array = npc.party + opponent.party
		for member in everyone:
			var others: Array = everyone.filter(func(m): return m != member)
			if confident_solo_against(member, others):
				return false

	return true

## Merges `joiner`'s whole party into `host`'s (host remains the leader) —
## used when the two decide not to fight, instead.
static func join_party_of(joiner: NpcAgent, host: NpcAgent) -> void:
	var joining: Array = joiner.party.duplicate()
	joiner.players.erase(joiner.cell_pos)
	for member in joining:
		if not is_instance_valid(member) or member.dead:
			continue
		member.is_party_leader = false
		member.party = host.party
		if not host.party.has(member):
			host.party.append(member)
	assign_party_offsets(host)
	for member in joining:
		if is_instance_valid(member) and not member.dead:
			relocate_to_party(member, host)
	host.current_action = "Party formed (%d members)" % host.party.size()
	host.name_label.text = "%s's party grew to %d!" % [host.npc_name, host.party.size()]
	var timer := joiner.get_tree().create_timer(1.5)
	timer.timeout.connect(host._update_label)

## A one-time relocation onto a new host's cell for a character that just
## joined that party, as opposed to NpcAgent._follow_to's every-step
## tagging along.
static func relocate_to_party(member: NpcAgent, host: NpcAgent) -> void:
	member.is_moving = true
	var duration: float = member.move_seconds_base / max(member.stats.move_speed(), 0.1)
	var target_world: Vector2 = host.position + member.party_offset
	var tween := member.create_tween()
	tween.tween_property(member, "position", target_world, duration)
	tween.finished.connect(func():
		member.is_moving = false
		member.cell_pos = host.cell_pos
		member.visited[member.cell_pos] = true
		member._update_label()
	)

## If the party leader falls but others survive, one of them is promoted
## so the party keeps acting rather than freezing with no one driving it.
static func promote_next_leader(former_leader: NpcAgent) -> void:
	for member in former_leader.party:
		if is_instance_valid(member) and not member.dead:
			member.is_party_leader = true
			member.cell_pos = former_leader.cell_pos
			member.position = former_leader.position
			former_leader.players[former_leader.cell_pos] = member
			return
