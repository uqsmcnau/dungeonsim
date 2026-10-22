class_name DungeonMaps
extends RefCounted

## What a character works from (see NpcAgent.use_maps): the maze, and the
## shared maps of who and what is where on it. The maps are the very
## dictionaries everyone using them reads and writes, not copies, so each
## character sees the others come and go. GameManager hands every character
## the real game's (see GameManager.shared_maps); a test can stand
## characters on a small maze of their own (see DungeonTest.isolate).

var grid: Array = []
var cell_size: float = GameManager.CELL_SIZE
## Where the race ends: the boss room's middle.
var exit_cell: Vector2i = MazeQuery.NONE
## Monsters, chests, shops and players by the cell they're on (a shop by
## its rarity -- see NpcAgent.shop_rarity).
var enemies: Dictionary = {}
var chests: Dictionary = {}
var shops: Dictionary = {}
var players: Dictionary = {}
## The safe zones (start zones, shops, boss rooms): no fights start there.
var safe_cells: Dictionary = {}
## The storm closing in, or null for none.
var storm: Storm = null

func _init(maze_grid: Array = []) -> void:
	grid = maze_grid
