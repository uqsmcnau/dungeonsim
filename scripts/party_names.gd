class_name PartyNames
extends RefCounted

## Random party names in the style of "Fellowship of the Ring", "Order of
## the Stick" or "The Rose Brigade", flavoured by alignment so a name hints
## at what kind of party it is. Built from three templates:
##   [Group] of the [Descriptor?] [Object]   -- "Order of the Broken Key"
##   The [Descriptor] [Group]                -- "The Crimson Vanguard"
##   The [Descriptor] [Object] [Group]       -- "The Iron Lantern Company"
## With ten words per list that's a few thousand names per alignment, so
## repeats within one run are rare (and harmless).

const WORDS := {
	NpcStats.ALIGNMENT_GOOD: {
		"groups": ["Order", "Fellowship", "Wardens", "Guardians", "Brotherhood", "Company", "Knights", "League", "Vanguard", "Circle"],
		"descriptors": ["Silver", "Golden", "Radiant", "Valiant", "White", "Rose", "Gilded", "Sunlit", "Steadfast", "Shining"],
		"objects": ["Ring", "Shield", "Lantern", "Dawn", "Star", "Oath", "Crown", "Lily", "Bell", "Hearth"],
	},
	NpcStats.ALIGNMENT_NEUTRAL: {
		"groups": ["Company", "Band", "League", "Guild", "Circle", "Wanderers", "Fellowship", "Society", "Crew", "Brigade"],
		"descriptors": ["Iron", "Grey", "Copper", "Dusty", "Silent", "Amber", "Rustic", "Hidden", "Weathered", "Oaken"],
		"objects": ["Stick", "Key", "Compass", "Coin", "Road", "Lantern", "Map", "Anvil", "Acorn", "Barrel"],
	},
	NpcStats.ALIGNMENT_EVIL: {
		"groups": ["Cabal", "Covenant", "Brotherhood", "Legion", "Syndicate", "Coven", "Horde", "Order", "Pact", "Host"],
		"descriptors": ["Obsidian", "Crimson", "Ashen", "Black", "Blighted", "Hollow", "Bloodied", "Shadowed", "Grim", "Venomous"],
		"objects": ["Thorn", "Skull", "Fang", "Dagger", "Serpent", "Chain", "Raven", "Ember", "Crow", "Bone"],
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
				return "%s of the %s" % [group, object]
			return "%s of the %s %s" % [group, descriptor, object]
		1:
			return "The %s %s" % [descriptor, group]
		_:
			return "The %s %s %s" % [descriptor, object, group]

static func _pick(options: Array) -> String:
	return options[randi() % options.size()]
