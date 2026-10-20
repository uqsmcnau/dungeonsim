class_name NpcBody
extends Node2D

## Where a character is and how it gets around -- the part of NpcAgent that
## isn't deciding anything: its cell, stepping from cell to cell (its party
## tagging along), its icon's slide across the map, and its entry in the
## shared `players` map. NpcAgent extends this and decides where to go.
##
## Two rules everything here keeps (both learned the hard way -- see
## CLAUDE.md): the icon moves through slide_to, one slide at a time, so it
## and cell_pos can't come apart; and a `players` entry only counts if it
## really stands for someone there (holds_cell).

@export var move_seconds_base: float = 0.35

var grid: Array = []
var cell_size: float = 48.0
var cell_pos: Vector2i = Vector2i.ZERO
var visited: Dictionary = {}
## Every living player, by current cell — shared across all characters, the
## same way the monster map is, so each can see where the others are. Only
## ever holds PARTY LEADERS; a party's followers are found via its party,
## not this dict.
var players: Dictionary = {}
## Mid-step -- or held still by something else that uses the same lock (a
## monster fight, reading a tome, ...). Nothing new is decided while it's set.
var is_moving: bool = false
## Where in its cell this character's icon sits, as a follower: offset
## slightly from the leader's so a whole party stays visible (see
## PartyOps.assign_party_offsets).
var party_offset: Vector2 = Vector2.ZERO
## The icon's slide under way, if any (see slide_to).
var _slide: Tween = null

# ================================ Hooks ===================================

## How quick on its feet this character is (1 is ordinary).
func _move_speed() -> float:
	return 1.0

## Who tags along when this character steps somewhere (see move_to).
func _followers() -> Array:
	return []

## Whether this character stands for its party on the map: alive, and
## leading it. Only they belong in `players` (see holds_cell).
func represents_party() -> bool:
	return true

## Arrived in cell_pos at the end of a step (see move_to).
func _on_enter_cell() -> void:
	pass

# ================================ Moving ==================================

## How long one step from cell to cell takes this character.
func step_seconds() -> float:
	return move_seconds_base / maxf(_move_speed(), 0.1)

## Steps to `next_cell` (a neighbour), the followers tagging along; cell_pos
## changes when the step's done (see _on_move_finished).
func move_to(next_cell: Vector2i) -> void:
	is_moving = true
	var duration := step_seconds()
	slide_to(_cell_to_world(next_cell), duration).finished.connect(_on_move_finished.bind(next_cell))
	for member in _followers():
		member._follow_to(next_cell, duration)

## Every step the leader takes, each follower tags along to the same cell,
## offset slightly so the whole party stays visible as distinct members.
func _follow_to(next_cell: Vector2i, duration: float) -> void:
	cell_pos = next_cell
	slide_to(_cell_to_world(next_cell) + party_offset, duration).finished.connect(func(): visited[cell_pos] = true)

func _on_move_finished(next_cell: Vector2i) -> void:
	unregister()
	cell_pos = next_cell
	is_moving = false
	_on_enter_cell()

## Slides this character's icon to `world_pos` over `seconds`, first
## stopping any slide still under way -- one at a time, so whichever move
## came last decides both where the icon ends up and (through its finished
## callback, which a stopped slide never fires) where cell_pos says it is.
## Two at once used to pull the icon one way while the other's arrival set
## cell_pos somewhere else, leaving the fog lit around an empty spot.
func slide_to(world_pos: Vector2, seconds: float) -> Tween:
	stop_sliding()
	_slide = create_tween()
	_slide.tween_property(self, "position", world_pos, seconds)
	return _slide

func is_sliding() -> bool:
	return _slide != null and _slide.is_valid() and _slide.is_running()

## Stops the icon wherever it is, dropping the slide's finished callback.
func stop_sliding() -> void:
	if _slide != null and _slide.is_valid():
		_slide.kill()
	_slide = null

func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * cell_size, (cell.y + 0.5) * cell_size)

# ============================== On the map ================================

## Whether someone other than us stands for a party on `cell`.
func _has_live_player(cell: Vector2i) -> bool:
	return players.has(cell) and players[cell] != self and holds_cell(players[cell], cell)

## Whether `other` (an entry in `players`) really does stand for a party on
## `cell`: still there, a living leader, on that very cell. Anything else
## is a stale entry left behind -- which used to count as someone being
## there, so a party could get into a fight with someone on the far side of
## the maze, and the winner then walked straight across it to "claim" the
## loser's cell.
static func holds_cell(other, cell: Vector2i) -> bool:
	return other != null and is_instance_valid(other) and other.represents_party() and other.cell_pos == cell

## Puts this (leading) character back in `players` if its cell's entry has
## gone -- as when someone passed through it (see NpcAgent._squeeze_past),
## took over the entry, and then moved on, taking the entry with them -- or
## if the entry is stale (see holds_cell).
func _reclaim_registration() -> void:
	if not holds_cell(players.get(cell_pos), cell_pos):
		players[cell_pos] = self

## Removes this character's own entry from `players` -- and only its own.
## Followers share their leader's cell, and two leaders can briefly share
## one too, so a blind `players.erase(cell_pos)` would wipe out whoever
## else is registered there (e.g. a follower dying used to erase its
## leader, leaving the party invisible to everyone and its fight loop
## unable to find it).
func unregister() -> void:
	if players.get(cell_pos) == self:
		players.erase(cell_pos)
