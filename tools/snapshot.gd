extends SceneTree

## Pictures of the game, for checking how something looks: a few fixed
## scenes, each saved as a PNG. Every scene is the same each run -- the same
## game seed, a fixed frame rate, everyone held still -- so a picture taken
## before a change to the drawing code and one taken after can be compared
## pixel for pixel: a tidy-up that changes nothing on screen leaves them
## identical. Compare runs of the same scenes, though: the whole window can
## come out a few pixels different after other scenes than on its own (text
## drawn from a font cache that's warmed up differently).
##
## The scenes:
##   gear  -- the battle window: a party of five in every kind of gear
##   boss  -- the battle window: a party facing the Dragon's party
##   pack  -- the battle window: a party facing a pack of maze monsters
##   shop  -- the battle window: a party at a silver shop
##   hud   -- the whole window, someone selected
##   map   -- the whole window, the fog of war off: every room on the map
##
## Needs a window to draw into (not --headless). From the project folder:
##   godot --path . --fixed-fps 60 -s tools/snapshot.gd -- --out=DIR [--scenes=gear,boss]
## Saves DIR/<scene>.png for each (DIR defaults to user://snapshots).

const SCENES := ["gear", "boss", "pack", "shop", "hud", "map"]
const GAME_SEED := 3
## Frames to let a scene settle -- figures walk in, the shop slides in --
## before it's taken.
const SETTLE_FRAMES := 60

## What each of the party of five wears in the gear scene.
const OUTFITS := [
	["Iron Sword", "Shield", "Leather Armor", "Helmet", "Leather Boots"],
	["Steel Sword", "Silver Shield", "Chainmail", "Steel Helm", "Swift Boots", "Silver Ring"],
	["Mithril Sword", "Aegis Shield", "Plate Armor", "Golden Helm", "Winged Boots", "Ring of Might"],
	["Archmage's Staff", "Sage's Amulet", "Leather Boots"],
	["Iron Sword", "Steel Sword", "Enchanted Tome", "Moonstone Amulet", "Ring of Vigor"],
]

var out_dir := "user://snapshots"
var scenes: Array = SCENES.duplicate()
var main: GameManager
var frames := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--scenes="):
			scenes = Array(arg.get_slice("=", 1).split(","))
	DirAccess.make_dir_recursive_absolute(out_dir)

## Each scene starts on a frame of its own, once the one before is gone: not
## from _initialize (the tree isn't running yet, so the game wouldn't set
## itself up), and not alongside the last scene's game while it's still being
## freed (it'd roll the dice the new one had just been seeded with, and a
## scene would come out differently after another than on its own).
func _process(_delta: float) -> bool:
	if main == null:
		if scenes.is_empty():
			return true
		_start(scenes[0])
		return false
	frames += 1
	if frames < SETTLE_FRAMES:
		return false
	_save(scenes.pop_front())
	main.queue_free()
	main = null
	return false

## A fresh game, with `scene` set up in it.
func _start(scene: String) -> void:
	frames = 0
	main = load("res://scenes/Main.tscn").instantiate()
	main.game_seed = GAME_SEED
	root.add_child(main)
	for npc in main.npcs:
		npc.set_process(false)  # held still, so nothing changes but what's shown
	for enemy in main.enemy_container.get_children():
		enemy.wanders = false
	var party := _party(5 if scene == "gear" or scene == "boss" else 3)
	var leader: NpcAgent = party[0]
	match scene:
		"gear":
			for i in range(party.size()):
				party[i].stats.inventory.clear()
				for item_name in OUTFITS[i]:
					party[i].stats.acquire_item(item_name)
		"boss":
			_fight(leader, main.enemy_map[main.exit_cell])
		"pack":
			_fight(leader, _a_maze_pack())
		"shop":
			leader.shopping_at = ItemCatalog.RARITY_SILVER
			leader.current_action = "Shopping"
		"map":
			main._on_fog_toggled(false)
			return  # nobody selected
	main.hud.inspect(leader)

## The first `size` characters as one party, the first leading -- tough
## enough not to fall in a scene's few seconds of fighting.
func _party(size: int) -> Array:
	var party: Array = main.npcs.slice(0, size)
	for member in party:
		member.party = party
		member.is_party_leader = member == party[0]
		member.stats.max_hp = 999
		member.stats.hp = 999
	return party

func _fight(leader: NpcAgent, pack: EnemyAgent) -> void:
	for member in pack.living_pack():
		member.stats.max_hp = 999
		member.stats.hp = 999
	GroupCombat.engage_pack(leader, pack.cell_pos, pack)

## A roaming pack of more than one, out in the maze.
func _a_maze_pack() -> EnemyAgent:
	for enemy in main.enemy_map.values():
		if not enemy.in_boss_party() and enemy.living_pack().size() > 1:
			return enemy
	return main.enemy_map.values()[0]

func _save(scene: String) -> void:
	var image := root.get_texture().get_image()
	if scene != "hud" and scene != "map":
		image = image.get_region(Rect2i(main.hud.battle_window.get_global_rect()))
	var path := out_dir.path_join(scene + ".png")
	image.save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))
