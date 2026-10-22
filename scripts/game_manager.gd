class_name GameManager
extends Node2D

const MAZE_WIDTH := 68
const MAZE_HEIGHT := 68
const CELL_SIZE := 20.0
const NPC_COUNT := 26
## How far (in pixels) from a character's icon center a click still selects
## it -- about half a cell, matching the 16px icon.
const PICK_RADIUS := 10.0
## Seconds of game time (it doesn't tick while paused) between uses of
## Guidance, the spectator's right-click "go there" for the selected party.
const GUIDANCE_COOLDOWN := 15.0
## How far the selection ring sits beyond the outermost member's icon
## centre -- a touch more than half the 16px icon's diagonal.
const SELECTION_ICON_MARGIN := 13.0
## The selection ring's radius around a gravestone -- just clear of its icon.
const GRAVE_RING_RADIUS := 12.0
const NPC_SCENE: PackedScene = preload("res://scenes/NPC.tscn")
const GRAVE_SCENE: PackedScene = preload("res://scenes/Gravestone.tscn")

## Party Vision: while a character is selected, the fog of war shows only
## what their party knows -- the cells its members can see right now, and
## everything any of them has ever seen (see NpcAgent.seen_cells) -- rather
## than what everyone has. Starts the toolbar's "Party Vision" toggle in
## this state. Has no effect with the fog of war turned off.
@export var party_vision: bool = true
## Follow Mode: the view follows the selected party about the maze (see
## MapCamera.following). Starts the toolbar's "Follow Mode" toggle in this
## state; moving the view by hand switches it off.
@export var follow_mode: bool = false
## 0 (the default) plays a fresh random game each time; anything else
## replays the same maze, roster and dice rolls -- so a game that went wrong
## (see tools/soak.gd) can be played again to see what happened.
@export var game_seed: int = 0

## One distinct entry per NPC_COUNT -- kept at exactly 26 (a name for each
## letter) so no two of the starting characters share both a name and a
## color (they'd otherwise cycle and repeat via the modulo indexing below
## once NPC_COUNT exceeded the list length).
var npc_colors := [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW,
	Color.ORANGE, Color.PURPLE, Color.CYAN, Color.MAGENTA,
	Color.FOREST_GREEN, Color.PINK, Color.TEAL, Color.GOLD,
	Color.BROWN, Color.CORAL, Color.VIOLET, Color.SALMON,
	Color.KHAKI, Color.CRIMSON, Color.TURQUOISE, Color.SIENNA,
	Color.SKY_BLUE, Color.OLIVE, Color.SLATE_BLUE, Color.AQUAMARINE,
	Color.LAVENDER, Color.SEA_GREEN,
]
var npc_names := [
	"Aria", "Bram", "Cass", "Dorn", "Eska", "Finn",
	"Gale", "Hesk", "Iris", "Jace", "Kael", "Lyra",
	"Mira", "Nox", "Orla", "Pell", "Quen", "Rook", "Sable", "Tam",
	"Ulla", "Vex", "Wren", "Xan", "Yara", "Zed",
]

var npcs: Array = []
var winner: NpcAgent = null
var grid: Array = []
## The maze's outline (see MazeShape); cells outside it are rock.
var maze_shape: MazeShape
var start_cells: Array = []
var exit_cell: Vector2i
var enemy_map: Dictionary = {}
var chest_map: Dictionary = {}
## Every living player, by current cell — lets NPCs see and fight each other.
var player_map: Dictionary = {}
## Centers of the shops, in list form (for drawing) and lookup form.
var shop_cells: Array = []
var shop_map: Dictionary = {}
## Centers of the mini boss rooms, for drawing.
var mini_boss_cells: Array = []
## Starting safe zones, shop zones, mini boss rooms and the boss room: no
## enemies spawn or wander here, and no random chests are placed here.
var restricted_cells: Dictionary = {}
## Seconds until Guidance can be used again (0 = ready). Ticked down in
## _process, so it freezes while the game is paused.
var guidance_cooldown_left: float = 0.0
## A gravestone for every character who's died, by character, standing
## where they fell. Clicking one brings up their final HUD panel, with how
## they died.
var graves: Dictionary = {}
## Builds the maze and stocks it with monsters, chests and the like, and
## places chests later on (see WorldBuilder).
var world: WorldBuilder
## Brings monster numbers back up over time (see MonsterRespawner).
var respawner: MonsterRespawner
## The storm closing in on the maze (see Storm).
var storm: Storm

@onready var maze_view: MazeView = $World/MazeView
@onready var npc_container: Node2D = $World/NPCs
@onready var enemy_container: Node2D = $World/Enemies
@onready var chest_container: Node2D = $World/Chests
@onready var grave_container: Node2D = $World/Graves
@onready var hud: Hud = $HUD/Control
@onready var music: MusicPlayer = $MusicPlayer
## The view of the maze: zoom and move it about (see MapCamera).
@onready var camera: MapCamera = $MapCamera

func _ready() -> void:
	if game_seed != 0:
		seed(game_seed)
	else:
		randomize()
	world = WorldBuilder.new(self)
	world.build_maze()
	# The view starts on the whole maze, border and all, which can't then be
	# moved wholly out of view.
	var border := Vector2.ONE * MazeView.BORDER_WIDTH * CELL_SIZE
	camera.set_bounds(Rect2(maze_view.global_position - border, Vector2(MAZE_WIDTH, MAZE_HEIGHT) * CELL_SIZE + 2.0 * border))
	camera.set_view_area(hud.map_area())
	camera.frame(camera.maze_rect)
	hud.toolbar.fog_toggled.connect(_on_fog_toggled)
	hud.toolbar.party_vision_toggle.set_pressed_no_signal(party_vision)
	hud.toolbar.party_vision_toggled.connect(_on_party_vision_toggled)
	hud.toolbar.follow_toggle.set_pressed_no_signal(follow_mode)
	hud.toolbar.follow_toggled.connect(set_follow_mode)
	camera.following = follow_mode
	camera.follow_broken.connect(func(): set_follow_mode(false))
	hud.toolbar.volume_slider.set_value_no_signal(music.volume)
	hud.toolbar.volume_changed.connect(music.set_volume)
	hud.toolbar.speed_changed.connect(set_game_speed)
	$ClickPicker.clicked.connect(_on_world_clicked)
	$ClickPicker.right_clicked.connect(_on_world_right_clicked)
	hud.selection_changed.connect(_sync_selection_highlight)
	hud.selection_changed.connect(_sync_fog)
	hud.selection_changed.connect(_sync_battle_window)
	world.stock()
	respawner = MonsterRespawner.new(self, world)
	storm = Storm.new(maze_shape, grid)
	maze_view.storm = storm
	_spawn_npcs()

func _process(delta: float) -> void:
	hud.update_positions(npcs)
	respawner.tick(delta)
	storm.advance(delta)
	hud.update_storm(storm)
	maze_view.queue_redraw()  # the storm moves, fog or no fog
	_sync_fog()
	_sync_guidance_marker()
	_sync_selection_highlight()
	_sync_battle_window()
	guidance_cooldown_left = maxf(0.0, guidance_cooldown_left - delta)
	hud.toolbar.update_guidance(guidance_cooldown_left, GUIDANCE_COOLDOWN)

## Runs the whole game -- steps, fights, the storm, timers -- `speed` times
## as fast. The music plays on in real time.
func set_game_speed(speed: float) -> void:
	Engine.time_scale = speed
	hud.toolbar.show_speed(speed)

## Game speed is engine-wide, so it mustn't outlive the game.
func _exit_tree() -> void:
	Engine.time_scale = 1.0

## The fog checkbox stays usable while paused, but _process doesn't run then,
## so re-sync immediately or enemies/chests wouldn't appear/hide until resume.
func _on_fog_toggled(enabled: bool) -> void:
	maze_view.set_fog_enabled(enabled)
	_sync_fog()

## Likewise usable while paused, so re-sync straight away.
func _on_party_vision_toggled(enabled: bool) -> void:
	party_vision = enabled
	_sync_fog()

## Clicking a character's icon selects them -- opening their inspector panel
## and highlighting their party on the map -- as does clicking a fallen
## character's gravestone (a living character standing over one wins);
## clicking anywhere else on the map deselects them.
func _on_world_clicked(world_pos: Vector2) -> void:
	var npc: NpcAgent = npc_at(world_pos)
	if npc == null:
		npc = grave_at(world_pos)
	if npc != null:
		hud.inspect(npc)
	else:
		hud.close_inspector()

## Guidance: right-clicking the maze while a character is selected
## (inspected) sends their whole party there -- whoever's leading it, even
## if the selected character is a follower. Usable once every
## GUIDANCE_COOLDOWN seconds; the cooldown only starts when Guidance is
## actually given, so a click that goes nowhere doesn't waste it. Works
## while paused; the party sets off once the game resumes.
func _on_world_right_clicked(world_pos: Vector2) -> void:
	var leader := _inspected_party_leader()
	if leader == null:
		return
	var cell := world_to_cell(world_pos)
	if MazeGenerator.is_outside(grid, cell):  # off the map, or the rock around the maze
		return
	if guidance_cooldown_left > 0.0:
		hud.toolbar.guidance_denied()
		return
	if leader.guide_to(cell):
		guidance_cooldown_left = GUIDANCE_COOLDOWN
		hud.toolbar.update_guidance(guidance_cooldown_left, GUIDANCE_COOLDOWN)
	_sync_guidance_marker()

## The leader of the selected character's party, or null if nobody's
## selected or they're out of the running.
func _inspected_party_leader() -> NpcAgent:
	var npc: NpcAgent = hud.inspected
	if npc == null or npc.dead or npc.finished:
		return null
	return PartyOps.leader_of(npc.party)

func world_to_cell(world_pos: Vector2) -> Vector2i:
	var local: Vector2 = npc_container.get_global_transform().affine_inverse() * world_pos
	return Vector2i(floori(local.x / CELL_SIZE), floori(local.y / CELL_SIZE))

## Turns Follow Mode on or off, ticking or unticking its toggle to match
## (it goes off by itself when the view's moved by hand).
func set_follow_mode(enabled: bool) -> void:
	follow_mode = enabled
	camera.following = enabled
	hud.toolbar.follow_toggle.set_pressed_no_signal(enabled)

## Rings the selected character's whole party on the map, following them as
## they move -- centred on the leader, wide enough to take in every member's
## icon (party members stand slightly offset from the leader, see
## PartyOps.PARTY_OFFSETS). A dead character's gravestone is ringed
## instead; nothing is when nobody's selected. Follow Mode follows whatever
## is ringed.
func _sync_selection_highlight() -> void:
	var npc: NpcAgent = hud.inspected
	if npc == null:
		_ring(Vector2.ZERO, 0.0)
		return
	if npc.dead:
		var grave: Node2D = graves.get(npc)
		if grave == null:
			_ring(Vector2.ZERO, 0.0)
		else:
			_ring(grave.position, GRAVE_RING_RADIUS)
		return
	var leader: NpcAgent = PartyOps.leader_of(npc.party)
	if leader == null:
		leader = npc
	var radius := 0.0
	for member in leader.living_party():
		radius = maxf(radius, member.position.distance_to(leader.position))
	_ring(leader.position, radius + SELECTION_ICON_MARGIN)

## Rings `center` (map coordinates) on the map and points Follow Mode at it;
## a radius of 0 rings nothing, leaving Follow Mode nothing to follow.
func _ring(center: Vector2, radius: float) -> void:
	maze_view.set_selection_highlight(center, radius)
	camera.follow(maze_view.to_global(center), radius > 0.0)

## The party whose view Party Vision shows: the selected character's,
## followers included. Nobody (so everyone's view shows) when it's switched
## off, nobody's selected, or the selected character has died.
func _party_vision_focus() -> Array:
	var npc: NpcAgent = hud.inspected
	if not party_vision or npc == null or npc.dead:
		return []
	return npc.living_party()

## Tells the battle window who's in the scene: the selected character's
## party, its leader first (front and centre) -- the selected one included
## even once fallen, so the fight they fell in plays out to the end -- and
## whoever that party's fighting.
func _sync_battle_window() -> void:
	var npc: NpcAgent = hud.inspected
	if npc == null:
		hud.battle_window.show_fight([], [], "")
		return
	var leader := PartyOps.leader_of(npc.party)
	var members: Array = npc.living_party()
	if leader != null:
		members.erase(leader)
		members.push_front(leader)
	if npc.dead:
		members.append(npc)
	if leader == null:
		hud.battle_window.show_fight(members, [], npc.current_action)
		return
	var status := leader.current_action
	if leader.living_party().size() > 1 and leader.party_name != "":
		status = "%s\n%s" % [leader.party_name, status]
	hud.battle_window.show_fight(members, GroupCombat.opponents_of(leader, enemy_map), status, leader.is_sliding())

## A blow, spell or escape in someone's fight: the battle window plays it
## out if it's the selected party's (brought up to date first, in case the
## fight's only just begun).
func _on_combat_event(event: CombatEvent) -> void:
	_sync_battle_window()
	hud.battle_window.play(event)

## Marks where the selected party has been sent by Guidance, if anywhere.
func _sync_guidance_marker() -> void:
	var leader := _inspected_party_leader()
	maze_view.set_guidance_marker(leader.guidance_target if leader != null else MazeQuery.NONE)

## The living character whose icon is nearest `world_pos`, within
## PICK_RADIUS, or null. Party members share a cell (offset by
## PartyOps.PARTY_OFFSETS), so their icons overlap -- nearest wins.
func npc_at(world_pos: Vector2) -> NpcAgent:
	var best: NpcAgent = null
	var best_dist := PICK_RADIUS
	for npc in npcs:
		if npc.dead:
			continue
		var dist: float = npc.global_position.distance_to(world_pos)
		if dist <= best_dist:
			best = npc
			best_dist = dist
	return best

## The fallen character whose gravestone is nearest `world_pos`, within
## PICK_RADIUS, or null. Only gravestones showing on the map count.
func grave_at(world_pos: Vector2) -> NpcAgent:
	var best: NpcAgent = null
	var best_dist := PICK_RADIUS
	for npc in graves:
		var grave: Node2D = graves[npc]
		if not grave.visible:
			continue
		var dist: float = grave.global_position.distance_to(world_pos)
		if dist <= best_dist:
			best = npc
			best_dist = dist
	return best

func _sync_fog() -> void:
	for npc in npcs:
		npc.look_around()
	maze_view.update_fog(npcs, _party_vision_focus())
	for cell in enemy_map:
		var enemy: EnemyAgent = enemy_map[cell]
		var cell_visible: bool = maze_view.is_currently_visible(cell)
		# enemy_map only ever holds the pack's leader; followers (sharing the
		# same cell, offset slightly) aren't in it at all, so without this
		# they'd never get hidden and would always show through the fog.
		for pack_member in enemy.living_pack():
			pack_member.visible = cell_visible
	for cell in chest_map:
		var chest: ChestAgent = chest_map[cell]
		chest.visible = maze_view.is_currently_visible(cell)
	# Landmarks, like shops: shown wherever the map's been discovered (by
	# the selected party, under Party Vision), not only while in sight.
	for npc in graves:
		graves[npc].visible = maze_view.is_discovered(npc.cell_pos)

## The dungeon as the characters see it (see DungeonMaps): this game's maze,
## its shared maps of who and what is where, and its storm.
func shared_maps() -> DungeonMaps:
	var maps := DungeonMaps.new(grid)
	maps.cell_size = CELL_SIZE
	maps.exit_cell = exit_cell
	maps.enemies = enemy_map
	maps.chests = chest_map
	maps.shops = shop_map
	maps.players = player_map
	maps.safe_cells = restricted_cells
	maps.storm = storm
	return maps

func _spawn_npcs() -> void:
	var maps := shared_maps()
	for i in range(NPC_COUNT):
		var npc: NpcAgent = NPC_SCENE.instantiate()
		npc_container.add_child(npc)
		var color: Color = npc_colors[i % npc_colors.size()]
		var display_name: String = npc_names[i % npc_names.size()]
		var start_cell: Vector2i = start_cells[i]
		npc.setup(start_cell, color, display_name, maps)
		npc.reached_exit.connect(_on_npc_reached_exit)
		npc.leveled_up.connect(_on_npc_leveled_up)
		npc.died.connect(_on_npc_died)
		npc.combat_event.connect(_on_combat_event)
		npcs.append(npc)
		hud.register_npc(npc)

func _on_npc_reached_exit(npc: NpcAgent) -> void:
	if winner != null:
		return
	winner = npc
	hud.announce_winner(npc)

func _on_npc_died(npc: NpcAgent) -> void:
	npcs.erase(npc)
	_place_grave(npc)
	hud.mark_dead(npc)
	world.place_death_chest(npc.cell_pos, npc.stats.inventory.duplicate(), npc.stats.gold)
	if npcs.is_empty() and winner == null:
		hud.announce_no_winner()

## A gravestone exactly where `npc`'s icon stood when they fell.
func _place_grave(npc: NpcAgent) -> void:
	var grave: Node2D = GRAVE_SCENE.instantiate()
	grave.position = npc.position
	grave_container.add_child(grave)
	graves[npc] = grave
	_sync_selection_highlight()  # in case they were selected: ring the grave now

func _on_npc_leveled_up(npc: NpcAgent) -> void:
	hud.refresh_npc(npc)
	hud.flash_level_up(npc)
