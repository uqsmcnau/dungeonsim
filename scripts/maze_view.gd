class_name MazeView
extends Node2D

var grid: Array = []
var cell_size: float = 48.0
var start_cells: Array = []
## Every shop, by cell, with its rarity (bronze or silver).
var shops: Dictionary = {}
var mid_boss_cells: Array = []
var exit_cell: Vector2i = Vector2i.ZERO

## A shop's room on the map: blue for a bronze shop, silver for a silver one.
const SHOP_COLOR := Color(0.3, 0.55, 1.0)
const SILVER_SHOP_COLOR := Color(0.82, 0.85, 0.95)

## The stone border around the maze (see _draw): how far past the maze's
## edge it reaches, in cells, and how smoothly its outline is drawn.
const BORDER_WIDTH := 1.2
const BORDER_POINTS := 160
const BORDER_COLOR := Color(0.36, 0.32, 0.29)
const BORDER_RIM_COLOR := Color(0.16, 0.13, 0.11)
const BORDER_RIM_WIDTH := 4.0
## The maze's floor: the colour the window clears to, so the maze looks as
## it always has -- it just stops where the rock starts.
const FLOOR_COLOR := Color(0.3, 0.3, 0.3)
## The border's outline, in pixels, and the floor as rects (see set_maze).
var _border := PackedVector2Array()
var _floor: Array = []

## The storm closing in (see Storm), drawn over everything outside its ring
## -- the maze, the border -- as a purple haze with a glowing edge.
var storm: Storm = null
const STORM_COLOR := Color(0.45, 0.15, 0.7, 0.4)
const STORM_EDGE_COLOR := Color(0.85, 0.55, 1.0, 0.95)
const STORM_EDGE_WIDTH := 3.0

## Fog of war: cells any character has ever seen stay in `discovered`
## forever. `currently_visible` is recomputed every tick from where
## characters are right now, plus any `sticky_cells` that have already
## been discovered (shops and mid boss rooms stay fully revealed once
## found, rather than dimming again once nobody's nearby).
var fog_enabled: bool = true
var discovered: Dictionary = {}
var currently_visible: Dictionary = {}
var sticky_cells: Dictionary = {}
## Revealed to everyone from the start (the boss room), so they show even
## under Party Vision.
var permanent_cells: Dictionary = {}

## Party Vision (see GameManager._sync_fog): while a party is in focus, the
## fog shows only what *they* know -- their pooled map (see
## NpcAgent.seen_cells) as discovered, and what they can see right now as
## lit -- in place of what everyone has ever seen.
var focus_active: bool = false
var focus_known: Dictionary = {}
var focus_visible: Dictionary = {}

## Where the selected party has been sent by Guidance (see
## GameManager._on_world_right_clicked), or NONE.
var guidance_marker: Vector2i = MazeQuery.NONE

func set_guidance_marker(cell: Vector2i) -> void:
	if cell == guidance_marker:
		return
	guidance_marker = cell
	queue_redraw()

## The selected party's highlight (see GameManager._sync_selection_highlight):
## a ring around all its members' icons, in maze coordinates. Radius 0 means
## nobody's selected. Drawn beneath the icons, so they stay on top.
var selection_center: Vector2 = Vector2.ZERO
var selection_radius: float = 0.0
const SELECTION_COLOR := Color(0.45, 0.9, 1.0)

func set_selection_highlight(center: Vector2, radius: float) -> void:
	if center == selection_center and radius == selection_radius:
		return
	selection_center = center
	selection_radius = radius
	queue_redraw()

func set_maze(new_grid: Array, new_cell_size: float, new_starts: Array, new_exit: Vector2i,
		new_shops: Dictionary, new_mid_bosses: Array, shape: MazeShape = null) -> void:
	grid = new_grid
	cell_size = new_cell_size
	start_cells = new_starts
	exit_cell = new_exit
	shops = new_shops
	mid_boss_cells = new_mid_bosses
	_border = PackedVector2Array()
	if shape != null:
		for point in shape.outline(BORDER_POINTS, BORDER_WIDTH):
			_border.append(point * cell_size)
	_floor = _floor_runs()
	queue_redraw()

## The maze's floor as a few long rects -- each run of maze cells along a
## row -- rather than a rect per cell, since it's drawn every frame.
func _floor_runs() -> Array:
	var runs: Array = []
	for y in range(grid.size()):
		var run_start := -1
		for x in range(grid[0].size() + 1):
			var inside: bool = x < grid[0].size() and not MazeGenerator.is_outside(grid, Vector2i(x, y))
			if inside and run_start < 0:
				run_start = x
			elif not inside and run_start >= 0:
				runs.append(Rect2(run_start * cell_size, y * cell_size, (x - run_start) * cell_size, cell_size))
				run_start = -1
	return runs

func set_fog_enabled(enabled: bool) -> void:
	fog_enabled = enabled
	queue_redraw()

## Cells that are lit up and stay that way forever, regardless of whether
## anyone is currently nearby — used for the boss room, visible from turn one.
func reveal_permanently(cells: Dictionary) -> void:
	for c in cells:
		discovered[c] = true
	sticky_cells.merge(cells)
	permanent_cells.merge(cells)

## Cells that become permanently revealed once first discovered normally —
## used for shop and mid boss room zones ("always visible once found").
func register_sticky_zone(cells: Dictionary) -> void:
	sticky_cells.merge(cells)

func is_currently_visible(cell: Vector2i) -> bool:
	if not fog_enabled:
		return true
	if focus_active:
		return focus_visible.has(cell)
	return currently_visible.has(cell)

func is_discovered(cell: Vector2i) -> bool:
	if not fog_enabled:
		return true
	if focus_active:
		return focus_known.has(cell)
	return discovered.has(cell)

## Recomputes what's lit up right now from what every living character can
## see (NpcAgent.sight_cells -- GameManager has them look_around first),
## called once a frame by GameManager. `focus` is the party Party Vision is
## showing, or empty to show everyone's view.
func update_fog(npcs: Array, focus: Array = []) -> void:
	if not fog_enabled:
		return
	currently_visible.clear()
	for npc in npcs:
		if npc.dead:
			continue
		currently_visible.merge(npc.sight_cells)
		discovered.merge(npc.sight_cells)
	for c in sticky_cells:
		if discovered.has(c):
			currently_visible[c] = true

	focus_known.clear()
	focus_visible.clear()
	focus_active = false
	for member in focus:
		if member.dead:
			continue
		focus_active = true
		focus_known.merge(member.seen_cells)
		focus_visible.merge(member.sight_cells)
	if focus_active:
		focus_known.merge(permanent_cells)
		for c in sticky_cells:
			if focus_known.has(c):
				focus_visible[c] = true
	queue_redraw()

func _draw() -> void:
	if grid.is_empty():
		return
	_draw_border()
	for s in start_cells:
		_draw_marker_if_visible(s, Color(0.2, 0.9, 0.3, 0.6))
	_draw_marker_if_visible(exit_cell, Color(0.95, 0.8, 0.15, 0.6))
	for shop in shops:
		if is_discovered(shop):
			_draw_room(shop, SILVER_SHOP_COLOR if shops[shop] == ItemCatalog.RARITY_SILVER else SHOP_COLOR, "$")
	for mid_boss in mid_boss_cells:
		if is_discovered(mid_boss):
			_draw_room(mid_boss, Color(0.55, 0.15, 0.75), "☠")
	_draw_walls()
	_draw_storm()
	_draw_guidance_marker()
	_draw_selection()

## The border: a band of stone around the maze's circle, its outer edge
## rimmed, then the maze's floor laid over the middle of it -- so the band
## shows between the floor's stepped edge and the smooth rim. Drawn whatever
## the fog, so the dungeon's outline is always framed.
func _draw_border() -> void:
	if not _border.is_empty():
		draw_colored_polygon(_border, BORDER_COLOR)
		var rim := _border.duplicate()
		rim.append(rim[0])
		draw_polyline(rim, BORDER_RIM_COLOR, BORDER_RIM_WIDTH, true)
	for run in _floor:
		draw_rect(run, FLOOR_COLOR)

## A 3x3 room around `center` -- a shop or a mid boss's -- tinted `tint`,
## its middle stronger and marked with `symbol`.
func _draw_room(center: Vector2i, tint: Color, symbol: String) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_draw_marker(center + Vector2i(dx, dy), Color(tint, 0.18))
	_draw_marker(center, Color(tint, 0.6))
	var baseline := Vector2(center.x * cell_size, center.y * cell_size + cell_size * 0.78)
	draw_string(ThemeDB.fallback_font, baseline, symbol, HORIZONTAL_ALIGNMENT_CENTER, cell_size, int(cell_size * 0.8), Color.WHITE)

## The walls of every discovered cell: white where they're in sight right
## now, dimmed elsewhere.
func _draw_walls() -> void:
	var thickness := 3.0
	var dim := Color(0.4, 0.4, 0.4, 1.0)
	for y in range(grid.size()):
		for x in range(grid[0].size()):
			var cell := Vector2i(x, y)
			if MazeGenerator.is_outside(grid, cell) or not is_discovered(cell):
				continue
			var wall_color := Color.WHITE if is_currently_visible(cell) else dim
			var walls: int = grid[y][x]
			var top_left := Vector2(x * cell_size, y * cell_size)
			var top_right := Vector2((x + 1) * cell_size, y * cell_size)
			var bottom_left := Vector2(x * cell_size, (y + 1) * cell_size)
			var bottom_right := Vector2((x + 1) * cell_size, (y + 1) * cell_size)
			if walls & MazeGenerator.WALL_N:
				draw_line(top_left, top_right, wall_color, thickness)
			if walls & MazeGenerator.WALL_E:
				draw_line(top_right, bottom_right, wall_color, thickness)
			if walls & MazeGenerator.WALL_S:
				draw_line(bottom_left, bottom_right, wall_color, thickness)
			if walls & MazeGenerator.WALL_W:
				draw_line(top_left, bottom_left, wall_color, thickness)

## Where the selected party's been sent by Guidance, if anywhere.
func _draw_guidance_marker() -> void:
	if guidance_marker == MazeQuery.NONE:
		return
	var center := Vector2((guidance_marker.x + 0.5) * cell_size, (guidance_marker.y + 0.5) * cell_size)
	draw_arc(center, cell_size * 0.4, 0.0, TAU, 24, Color(1.0, 0.85, 0.2, 0.95), 2.0)
	draw_circle(center, cell_size * 0.1, Color(1.0, 0.85, 0.2, 0.95))

## The ring round the selected party, if anyone's selected.
func _draw_selection() -> void:
	if selection_radius <= 0.0:
		return
	draw_circle(selection_center, selection_radius, Color(SELECTION_COLOR, 0.18))
	draw_arc(selection_center, selection_radius, 0.0, TAU, 32, Color(SELECTION_COLOR, 0.95), 2.5)

func _draw_marker_if_visible(cell: Vector2i, color: Color) -> void:
	if is_discovered(cell):
		_draw_marker(cell, color)

func _draw_marker(cell: Vector2i, color: Color) -> void:
	var top_left := Vector2(cell.x * cell_size, cell.y * cell_size)
	draw_rect(Rect2(top_left, Vector2(cell_size, cell_size)), color)

## The storm, once it's begun: a haze over everything outside its ring, out
## past the border, and the ring itself picked out as it closes. Once it's
## closed it covers the lot.
func _draw_storm() -> void:
	if storm == null or not storm.has_started():
		return
	var middle := storm.center * cell_size
	var outer := (storm.start_radius + BORDER_WIDTH + 0.5) * cell_size
	var inner := storm.radius * cell_size
	if inner <= 0.0:
		draw_circle(middle, outer, STORM_COLOR)
		return
	draw_arc(middle, (inner + outer) / 2.0, 0.0, TAU, 128, STORM_COLOR, outer - inner)
	draw_arc(middle, inner, 0.0, TAU, 128, STORM_EDGE_COLOR, STORM_EDGE_WIDTH, true)
