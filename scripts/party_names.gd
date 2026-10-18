class_name PartyNames
extends RefCounted

## Random party names in the style of "Fellowship of the Ring", "Order of
## the Stick" or "The Rose Brigade", flavoured by alignment so a name hints
## at what kind of party it is -- with a good helping of sillier words
## mixed in ("The Soggy Turnip Committee"). Built from three templates:
##   [Group] of the [Descriptor?] [Object]   -- "Order of the Broken Key"
##   The [Descriptor] [Group]                -- "The Crimson Vanguard"
##   The [Descriptor] [Object] [Group]       -- "The Iron Lantern Company"
## Every word is a single word, so a name can be taken apart again (see
## parse) when two named parties merge (see combine). With sixteen-odd words
## per list that's tens of thousands of names per alignment, so repeats
## within one run are rare (and harmless).

const WORDS := {
	NpcStats.ALIGNMENT_GOOD: {
		"groups": ["Order", "Fellowship", "Wardens", "Guardians", "Brotherhood", "Company", "Knights", "League", "Vanguard", "Circle",
			"Squad", "Pals", "Huggers", "Buddies", "Choir", "Picnic"],
		"descriptors": ["Silver", "Golden", "Radiant", "Valiant", "White", "Rose", "Gilded", "Sunlit", "Steadfast", "Shining",
			"Fluffy", "Sparkly", "Polite", "Cheerful", "Snuggly", "Wholesome"],
		"objects": ["Ring", "Shield", "Lantern", "Dawn", "Star", "Oath", "Crown", "Lily", "Bell", "Hearth",
			"Teapot", "Muffin", "Kitten", "Pudding", "Duckling", "Biscuit"],
	},
	NpcStats.ALIGNMENT_NEUTRAL: {
		"groups": ["Company", "Band", "League", "Guild", "Circle", "Wanderers", "Fellowship", "Society", "Crew", "Brigade",
			"Gang", "Bunch", "Committee", "Mob", "Posse", "Club"],
		"descriptors": ["Iron", "Grey", "Copper", "Dusty", "Silent", "Amber", "Rustic", "Hidden", "Weathered", "Oaken",
			"Soggy", "Wobbly", "Confused", "Sleepy", "Lukewarm", "Mediocre"],
		"objects": ["Stick", "Key", "Compass", "Coin", "Road", "Lantern", "Map", "Anvil", "Acorn", "Barrel",
			"Sandwich", "Spoon", "Turnip", "Sock", "Potato", "Goose", "Pickle"],
	},
	NpcStats.ALIGNMENT_EVIL: {
		"groups": ["Cabal", "Covenant", "Brotherhood", "Legion", "Syndicate", "Coven", "Horde", "Order", "Pact", "Host",
			"Goons", "Rascals", "Hooligans", "Scoundrels", "Riffraff", "Ne'er-do-wells"],
		"descriptors": ["Obsidian", "Crimson", "Ashen", "Black", "Blighted", "Hollow", "Bloodied", "Shadowed", "Grim", "Venomous",
			"Grumpy", "Smelly", "Sneaky", "Moist", "Rude", "Petty"],
		"objects": ["Thorn", "Skull", "Fang", "Dagger", "Serpent", "Chain", "Raven", "Ember", "Crow", "Bone",
			"Toenail", "Spork", "Onion", "Weasel", "Gremlin", "Pitchfork"],
	},
}

static func generate(alignment: String) -> String:
	var words: Dictionary = WORDS.get(alignment, WORDS[NpcStats.ALIGNMENT_NEUTRAL])
	var group: String = _pick(words["groups"])
	var descriptor: String = _pick(words["descriptors"])
	var object: String = _pick(words["objects"])
	match randi() % 3:
		0:
			# The descriptor is optional here, as in "Order of the Stick".
			if randi() % 2 == 0:
				return _format(group, "", object, true)
			return _format(group, descriptor, object, true)
		1:
			return _format(group, descriptor, "", false)
		_:
			return _format(group, descriptor, object, false)

## The name for two named parties merging into one: the host's group (its
## leader leads the lot) with at least one word of the joining party's --
## "Order of the Silver Ring" + "The Crimson Vanguard" gives "Order of the
## Crimson Ring". It keeps the host name's layout, so it reads as the same
## kind of name and can be combined again later. Returns "" when either name
## doesn't fit the templates (e.g. one given by hand), so it can't be done.
static func combine(host_name: String, joiner_name: String) -> String:
	var host := parse(host_name)
	var joiner := parse(joiner_name)
	if host.is_empty() or joiner.is_empty():
		return ""
	# The joiner's descriptor with the host's object ("Order of the [Crimson]
	# Ring"), or the host's descriptor with the joiner's object ("The Silver
	# [Skull] Vanguard"). Best is one that differs from the host's own name
	# (the two can share a word), then one with both slots filled.
	var best := ""
	var best_score := -1
	var options: Array = []
	if joiner["descriptor"] != "":
		options.append([joiner["descriptor"], host["object"]])
	if joiner["object"] != "":
		options.append([host["descriptor"], joiner["object"]])
	for option in options:
		var combined := _format(host["group"], option[0], option[1], host["of_the"])
		var score := (2 if combined != host_name else 0) + (1 if option[0] != "" and option[1] != "" else 0)
		if score > best_score:
			best = combined
			best_score = score
	return best

## Takes a name made by generate (or combine) apart into its words:
## {"group", "descriptor", "object", "of_the"} -- descriptor or object ""
## where the template has none, and of_the whether it's the "[Group] of the
## ..." layout. An empty dictionary for anything that doesn't fit.
static func parse(party_name: String) -> Dictionary:
	var words := party_name.split(" ", false)
	var of_at := party_name.find(" of the ")
	if of_at != -1:
		var group := party_name.substr(0, of_at)
		var rest := party_name.substr(of_at + " of the ".length()).split(" ", false)
		if group.contains(" ") or rest.size() < 1 or rest.size() > 2:
			return {}
		return {"group": group, "descriptor": rest[0] if rest.size() == 2 else "", "object": rest[-1], "of_the": true}
	if words.size() < 3 or words.size() > 4 or words[0] != "The":
		return {}
	return {"group": words[-1], "descriptor": words[1], "object": words[2] if words.size() == 4 else "", "of_the": false}

## Puts a name together from its words, in the "of the" layout or the "The"
## one. Without a descriptor it can only be "[Group] of the [Object]", and
## without an object only "The [Descriptor] [Group]".
static func _format(group: String, descriptor: String, object: String, of_the: bool) -> String:
	if object == "":
		return "The %s %s" % [descriptor, group]
	if descriptor == "":
		return "%s of the %s" % [group, object]
	if of_the:
		return "%s of the %s %s" % [group, descriptor, object]
	return "The %s %s %s" % [descriptor, object, group]

static func _pick(options: Array) -> String:
	return options[randi() % options.size()]
