class_name MazeView
extends Node2D

var grid: Array = []
var cell_size: float = 48.0
var start_cells: Array = []
var shop_cells: Array = []
var mini_boss_cells: Array = []
var exit_cell: Vector2i = Vector2i.ZERO

## Fog of war: cells any character has ever seen stay in `discovered`
## forever. `currently_visible` is recomputed every tick from where
## characters are right now, plus any `sticky_cells` that have already
## been discovered (shops and mini boss rooms stay fully revealed once
## found, rather than dimming again once nobody's nearby).
var fog_enabled: bool = true
var discovered: Dictionary = {}
var currently_visible: Dictionary = {}
var sticky_cells: Dictionary = {}

## Where the selected party has been sent by Guidance (see
## GameManager._on_world_right_clicked), or NONE.
var guidance_marker: Vector2i = MazeQuery.NONE

func set_guidance_marker(cell: Vector2i) -> void:
	if cell == guidance_marker:
		return
	guidance_marker = cell
	queue_redraw()

func set_maze(new_grid: Array, new_cell_size: float, new_starts: Array, new_exit: Vector2i, new_shops: Array, new_mini_bosses: Array) -> void:
	grid = new_grid
	cell_size = new_cell_size
	start_cells = new_starts
	exit_cell = new_exit
	shop_cells = new_shops
	mini_boss_cells = new_mini_bosses
	queue_redraw()

func set_fog_enabled(enabled: bool) -> void:
	fog_enabled = enabled
	queue_redraw()

## Cells that are lit up and stay that way forever, regardless of whether
## anyone is currently nearby — used for the boss room, visible from turn one.
func reveal_permanently(cells: Dictionary) -> void:
	for c in cells:
		discovered[c] = true
	sticky_cells.merge(cells)

## Cells that become permanently revealed once first discovered normally —
## used for shop and mini boss room zones ("always visible once found").
func register_sticky_zone(cells: Dictionary) -> void:
	sticky_cells.merge(cells)

func is_currently_visible(cell: Vector2i) -> bool:
	if not fog_enabled:
		return true
	return currently_visible.has(cell)

func is_discovered(cell: Vector2i) -> bool:
	if not fog_enabled:
		return true
	return discovered.has(cell)

## Recomputes what's lit up right now from every living character's
## position, called once a frame by GameManager. Cheap: each character only
## scans the small box around itself that its sight range covers.
func update_fog(npcs: Array, sight_range: int) -> void:
	if not fog_enabled:
		return
	currently_visible.clear()
	for npc in npcs:
		if npc.dead:
			continue
		_reveal_around(npc.cell_pos, sight_range)
	for c in sticky_cells:
		if discovered.has(c):
			currently_visible[c] = true
	queue_redraw()

func _reveal_around(center: Vector2i, sight_range: int) -> void:
	var height: int = grid.size()
	var width: int = grid[0].size()
	for dy in range(-sight_range, sight_range + 1):
		for dx in range(-sight_range, sight_range + 1):
			if max(abs(dx), abs(dy)) > sight_range:
				continue
			var c := Vector2i(center.x + dx, center.y + dy)
			if c.x < 0 or c.x >= width or c.y < 0 or c.y >= height:
				continue
			if MazeQuery.has_line_of_sight(grid, center, c):
				currently_visible[c] = true
				discovered[c] = true

func _draw() -> void:
	if grid.is_empty():
		return
	var height: int = grid.size()
	var width: int = grid[0].size()
	var thickness := 3.0
	var dim := Color(0.4, 0.4, 0.4, 1.0)

	for s in start_cells:
		_draw_marker_if_visible(s, Color(0.2, 0.9, 0.3, 0.6))
	_draw_marker_if_visible(exit_cell, Color(0.95, 0.8, 0.15, 0.6))

	for shop in shop_cells:
		if not is_discovered(shop):
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				_draw_marker(shop + Vector2i(dx, dy), Color(0.3, 0.55, 1.0, 0.18))
		_draw_marker(shop, Color(0.3, 0.55, 1.0, 0.6))
		var font := ThemeDB.fallback_font
		var baseline := Vector2(shop.x * cell_size, shop.y * cell_size + cell_size * 0.78)
		draw_string(font, baseline, "$", HORIZONTAL_ALIGNMENT_CENTER, cell_size, int(cell_size * 0.8), Color.WHITE)

	for mini_boss in mini_boss_cells:
		if not is_discovered(mini_boss):
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				_draw_marker(mini_boss + Vector2i(dx, dy), Color(0.55, 0.15, 0.75, 0.18))
		_draw_marker(mini_boss, Color(0.55, 0.15, 0.75, 0.6))
		var mb_font := ThemeDB.fallback_font
		var mb_baseline := Vector2(mini_boss.x * cell_size, mini_boss.y * cell_size + cell_size * 0.78)
		draw_string(mb_font, mb_baseline, "☠", HORIZONTAL_ALIGNMENT_CENTER, cell_size, int(cell_size * 0.8), Color.WHITE)

	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			if not is_discovered(cell):
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

	if guidance_marker != MazeQuery.NONE:
		var center := Vector2((guidance_marker.x + 0.5) * cell_size, (guidance_marker.y + 0.5) * cell_size)
		draw_arc(center, cell_size * 0.4, 0.0, TAU, 24, Color(1.0, 0.85, 0.2, 0.95), 2.0)
		draw_circle(center, cell_size * 0.1, Color(1.0, 0.85, 0.2, 0.95))

func _draw_marker_if_visible(cell: Vector2i, color: Color) -> void:
	if is_discovered(cell):
		_draw_marker(cell, color)

func _draw_marker(cell: Vector2i, color: Color) -> void:
	var top_left := Vector2(cell.x * cell_size, cell.y * cell_size)
	draw_rect(Rect2(top_left, Vector2(cell_size, cell_size)), color)
