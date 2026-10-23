class_name FigureLook
extends RefCounted

## How a player's figure looks in the battle window in the gear they're
## wearing (see BattlePainter.draw_figure) -- worked out from it by `of`.
## Fields, not a Dictionary's string keys, so a misspelt part fails when the
## script loads rather than quietly never drawing.

## The swords that show in a figure's hand, best first, and how each looks;
## likewise what's held in the other hand.
const SWORDS := {"Mithril Sword": "mithril_sword", "Steel Sword": "steel_sword", "Iron Sword": "iron_sword"}
const OFF_HANDS := {
	"Aegis Shield": "aegis", "Silver Shield": "silver_shield", "Shield": "shield",
	"Archmage's Staff": "staff", "Enchanted Tome": "tome", "Arcane Tome": "tome",
}

## "mithril_sword", "steel_sword", "iron_sword", or "" for bare hands -- the
## best sword they've got.
var weapon := ""
## "aegis", "silver_shield", "shield", "staff", "tome", a second sword
## ("iron_sword": two swords, nothing else), or "".
var off_hand := ""
## "plate", "chainmail", "leather" or "".
var armor := ""
## Whether they're wearing one.
var helmet := false
var boots := false
var amulet := false
var ring := false
## Whether it's the Golden Helm, the Winged Boots, a Ring of Might.
var gold_helm := false
var winged := false
var might := false

## The look of whoever has `stats`, in the gear they're wearing.
static func of(stats: NpcStats) -> FigureLook:
	var look := FigureLook.new()
	var hands: Array = stats.equipped_in("hand")
	var swords: Array = SWORDS.keys().filter(func(s): return hands.has(s))
	look.weapon = SWORDS[swords[0]] if not swords.is_empty() else ""
	for item in OFF_HANDS:
		if hands.has(item):
			look.off_hand = OFF_HANDS[item]
			break
	if look.off_hand == "" and swords.size() > 1:
		look.off_hand = "iron_sword"  # the second sword, over the shoulder
	var worn: Array = stats.equipped_in("armor")
	if worn.has("Plate Armor"):
		look.armor = "plate"
	elif worn.has("Chainmail"):
		look.armor = "chainmail"
	elif not worn.is_empty():
		look.armor = "leather"
	look.helmet = not stats.equipped_in("helmet").is_empty()
	look.gold_helm = stats.equipped_in("helmet").has("Golden Helm")
	look.boots = not stats.equipped_in("feet").is_empty()
	look.winged = stats.equipped_in("feet").has("Winged Boots")
	var accessories: Array = stats.equipped_in("accessory")
	look.amulet = accessories.has("Sage's Amulet") or accessories.has("Moonstone Amulet")
	look.ring = accessories.has("Silver Ring") or accessories.has("Ring of Vigor")
	look.might = accessories.has("Ring of Might")
	return look
