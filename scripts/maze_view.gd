class_name MazeView
extends Node2D

var grid: Array = []
var cell_size: float = 48.0
var start_cells: Array = []
var shop_cells: Array = []
var mini_boss_cells: Array = []
var exit_cell: Vector2i = Vector2i.ZERO

func set_maze(new_grid: Array, new_cell_size: float, new_starts: Array, new_exit: Vector2i, new_shops: Array, new_mini_bosses: Array) -> void:
	grid = new_grid
	cell_size = new_cell_size
	start_cells = new_starts
	exit_cell = new_exit
	shop_cells = new_shops
	mini_boss_cells = new_mini_bosses
	queue_redraw()

func _draw() -> void:
	if grid.is_empty():
		return
	var height: int = grid.size()
	var width: int = grid[0].size()
	var wall_color := Color.WHITE
	var thickness := 3.0

	for s in start_cells:
		_draw_marker(s, Color(0.2, 0.9, 0.3, 0.6))
	_draw_marker(exit_cell, Color(0.95, 0.8, 0.15, 0.6))

	for shop in shop_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				_draw_marker(shop + Vector2i(dx, dy), Color(0.3, 0.55, 1.0, 0.18))
		_draw_marker(shop, Color(0.3, 0.55, 1.0, 0.6))
		var font := ThemeDB.fallback_font
		var baseline := Vector2(shop.x * cell_size, shop.y * cell_size + cell_size * 0.78)
		draw_string(font, baseline, "$", HORIZONTAL_ALIGNMENT_CENTER, cell_size, int(cell_size * 0.8), Color.WHITE)

	for mini_boss in mini_boss_cells:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				_draw_marker(mini_boss + Vector2i(dx, dy), Color(0.55, 0.15, 0.75, 0.18))
		_draw_marker(mini_boss, Color(0.55, 0.15, 0.75, 0.6))
		var mb_font := ThemeDB.fallback_font
		var mb_baseline := Vector2(mini_boss.x * cell_size, mini_boss.y * cell_size + cell_size * 0.78)
		draw_string(mb_font, mb_baseline, "☠", HORIZONTAL_ALIGNMENT_CENTER, cell_size, int(cell_size * 0.8), Color.WHITE)

	for y in range(height):
		for x in range(width):
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

func _draw_marker(cell: Vector2i, color: Color) -> void:
	var top_left := Vector2(cell.x * cell_size, cell.y * cell_size)
	draw_rect(Rect2(top_left, Vector2(cell_size, cell_size)), color)
