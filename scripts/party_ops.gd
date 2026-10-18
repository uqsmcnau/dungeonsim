class_name PartyOps
extends RefCounted

## Party-merge mechanics shared by NpcAgent: deciding whether two parties
## can band together instead of fighting, actually merging them, and
## promoting a new leader if one falls. These take the NpcAgent(s) involved
## as explicit parameters rather than living as instance methods, since
## "self" would otherwise be ambiguous between (for example) the character
## joining a party and the party it's joining.

const MAX_PARTY_SIZE := 5
## A meaningfully higher bar than the 50/50 "thinks it can probably win" used
## to decide whether to throw a punch at all — "confident" means a clear
## edge, not a coin flip. This also matters because of CombatMath's
## attacker/defender damage asymmetry, which means even two IDENTICAL
## characters compute themselves as having a razor-thin edge over one
## another; a bar of 0.5 would make this check nearly always true and the
## "form a party" rule nearly vacuous.
const SOLO_CONFIDENCE_THRESHOLD := 0.65
const PARTY_OFFSETS := [Vector2.ZERO, Vector2(10, -10), Vector2(-10, 10), Vector2(10, 10), Vector2(-10, -10)]

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
##
## Works the same if `host` is mid-fight: both fight loops re-read the
## host's shared party array every turn, so the newcomers simply start
## taking turns (and taking hits) from the next one on, and the fight
## itself carries on uninterrupted. They just need the same combat flags
## as everyone already in it.
##
## Naming the merged party (see _merged_party_name): a lone player meeting
## an existing party takes on that party's name, whichever of the two is
## hosting; two named parties combine their names.
static func join_party_of(joiner: NpcAgent, host: NpcAgent) -> void:
	var merged_name := _merged_party_name(joiner, host)
	var joining: Array = joiner.party.duplicate()
	joiner.unregister()
	# If the two shared a cell (e.g. both stepped onto the same one at once),
	# whichever arrived second overwrote the other's registration -- make
	# sure it's the host who's left on the map.
	host.players[host.cell_pos] = host
	for member in joining:
		if not is_instance_valid(member) or member.dead:
			continue
		member.is_party_leader = false
		member.guidance_target = MazeQuery.NONE  # the host's party isn't ours to steer
		member.party = host.party
		member.in_pvp_combat = host.in_pvp_combat
		member.in_pack_combat = host.in_pack_combat
		if not host.party.has(member):
			host.party.append(member)
	for member in host.party:
		if is_instance_valid(member):
			member.party_name = merged_name
	pool_seen_cells(host.party)
	assign_party_offsets(host)
	for member in host.party:
		if is_instance_valid(member):
			member.sync_label()
	for member in joining:
		if is_instance_valid(member) and not member.dead:
			relocate_to_party(member, host)
	# Mid-fight, the host's label is busy showing the fight -- don't clobber it.
	if host.is_in_combat():
		return
	host.current_action = "%s grew to %d" % [host.party_name, host.party.size()]
	host.show_label("%s grew to %d!" % [host.party_name, host.party.size()], NpcAgent.LABEL_MESSAGE_SECONDS)

## Everyone in `members` ends up with the combined map of all of them --
## including what each had seen before they ever met. Each keeps their own
## copy, so it isn't lost if they later die or the party breaks up.
static func pool_seen_cells(members: Array) -> void:
	var combined: Dictionary = {}
	for member in members:
		if is_instance_valid(member) and not member.dead:
			combined.merge(member.seen_cells)
	for member in members:
		if is_instance_valid(member) and not member.dead:
			member.seen_cells.merge(combined)

## The name the party formed by `joiner` joining `host` should go by,
## worked out before the merge while the two sides can still be told apart:
## - a lone host joined by an existing party (2+ members) keeps *their*
##   name -- one player tagging along shouldn't rename an established party;
## - two named parties (2+ members each) merging get a combination of both
##   names (PartyNames.combine) -- "Order of the Silver Ring" and "The
##   Crimson Vanguard" become "Order of the Crimson Ring" -- or, if the
##   names can't be combined, the host's;
## - otherwise the host's name (when a lone player joins an existing party,
##   that's the party's own name);
## - and if that side never had one (two loners teaming up for the first
##   time), a fresh name in keeping with the host's alignment.
## A lone host's name can be non-empty: a survivor whose party fell keeps
## it, and carries it on if another loner joins them.
static func _merged_party_name(joiner: NpcAgent, host: NpcAgent) -> String:
	var merged_name: String = host.party_name
	var host_size := host.living_party().size()
	var joiner_size := joiner.living_party().size()
	if host_size == 1 and joiner_size > 1:
		merged_name = joiner.party_name
	elif host_size > 1 and joiner_size > 1 and host.party_name != "" and joiner.party_name != "":
		var combined := PartyNames.combine(host.party_name, joiner.party_name)
		if combined != "":
			merged_name = combined
	if merged_name == "":
		merged_name = PartyNames.generate(host.stats.alignment)
	return merged_name

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
		# Joined a monster fight in progress: stay locked like the rest of
		# the party (see GroupCombat.engage_pack) -- checked now, not at join time,
		# in case the fight already ended during the walk over.
		member.is_moving = member.in_pack_combat
		member.cell_pos = host.cell_pos
		member.visited[member.cell_pos] = true
		member.reset_label()
	)

## Whoever in `party_ref` (a party's shared array) is currently its leader
## -- re-checked fresh each call, since a fallen leader is replaced by a
## promoted party-mate (see promote_next_leader). Falls back to any living
## member defensively, though promotion should mean that's never actually
## needed; null once they've all fallen.
static func leader_of(party_ref: Array) -> NpcAgent:
	for member in party_ref:
		if is_instance_valid(member) and not member.dead and member.is_party_leader:
			return member
	for member in party_ref:
		if is_instance_valid(member) and not member.dead:
			return member
	return null

## If the party leader falls but others survive, one of them is promoted
## so the party keeps acting rather than freezing with no one driving it.
static func promote_next_leader(former_leader: NpcAgent) -> void:
	for member in former_leader.party:
		if is_instance_valid(member) and not member.dead:
			member.is_party_leader = true
			member.guidance_target = former_leader.guidance_target  # carry on with any standing Guidance
			member.cell_pos = former_leader.cell_pos
			member.position = former_leader.position
			member.take_over_label(former_leader)  # it may be showing a fight
			# Take over the cell's registration -- unless some *other* party's
			# leader holds it (the two were sharing a cell), which mustn't be
			# knocked off the map in turn.
			var owner = former_leader.players.get(former_leader.cell_pos)
			if owner == null or owner == former_leader:
				former_leader.players[former_leader.cell_pos] = member
			return

# ============================ Sharing items ===============================

## Which of `members` an item should go to, rather than always to whoever
## happened to open the chest. `members[0]` is the opener and the fallback
## when nobody stands out; ties go to whoever comes first in the list.
## - Equipment: whoever it's the biggest upgrade for (see best_wearer).
## - A spell tome: whoever doesn't know that spell yet and isn't already
##   holding a copy, smartest first -- spell damage scales with
##   intelligence.
## - Anything else (potions): whoever holds the fewest of it.
static func best_recipient(members: Array, item_name: String) -> NpcAgent:
	var item := ItemCatalog.find(item_name)
	if item.get("kind") == ItemCatalog.KIND_EQUIPMENT:
		var wearer := best_wearer(members, item_name)
		return wearer if wearer != null else members[0]
	if item.get("effect") == "learn_spell":
		var reader: NpcAgent = null
		for m in members:
			if m.stats.knows_spell(item["spell"]) or m.stats.has_item(item_name):
				continue
			if reader == null or m.stats.intelligence > reader.stats.intelligence:
				reader = m
		return reader if reader != null else members[0]
	var keeper: NpcAgent = members[0]
	for m in members:
		if int(m.stats.inventory.get(item_name, 0)) < int(keeper.stats.inventory.get(item_name, 0)):
			keeper = m
	return keeper

## Whichever of `members` would gain the most from wearing this item (see
## NpcStats.upgrade_value), or null if none of them would wear it at all.
static func best_wearer(members: Array, item_name: String) -> NpcAgent:
	var best: NpcAgent = null
	var best_gain := 0.0
	for m in members:
		var gain: float = m.stats.upgrade_value(item_name)
		if gain > best_gain:
			best = m
			best_gain = gain
	return best

## At a shop, before anyone sells: hands each spare piece of equipment a
## member is carrying to whichever party-mate would actually wear it, so
## the party doesn't sell off something one of its own could use. Returns
## how many items changed hands.
static func pass_spares_around(members: Array) -> int:
	var passed := 0
	for giver in members:
		for item_name in giver.stats.inventory.keys():
			while giver.stats.spare_count(item_name) > 0:
				var others: Array = members.filter(func(m): return m != giver)
				var taker := best_wearer(others, item_name)
				if taker == null:
					break
				giver.stats.consume_item(item_name)
				taker.receive_item(item_name)
				passed += 1
	return passed
