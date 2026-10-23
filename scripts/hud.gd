class_name Hud
extends Control

## Whenever the selected (inspected) character changes -- including to
## nobody -- so GameManager can move the map highlight right away, even
## while paused (when its _process isn't running).
signal selection_changed

## The left column: the selected character's panel on top, then one for
## each other living member of their party (see _sync_party_panels) --
## compact ones, without the gear section, leaving room for the battle
## window below.
@onready var selection_container: VBoxContainer = $SelectionStats
## The right column: the leaderboard (see _update_leaderboard).
@onready var leaderboard_container: VBoxContainer = $LeaderboardStats
## Bottom left, below the selection column: the selected party's battles.
@onready var battle_window: BattleWindow = $BattleWindow
## Solid backing for the left and right columns and the toolbar, so a
## zoomed or moved maze only shows in the space between them (map_area).
@onready var left_frame: ColorRect = $LeftFrame
@onready var right_frame: ColorRect = $RightFrame
@onready var top_frame: ColorRect = $TopFrame
## Across the top of the map: how long till the storm, or till it closes.
@onready var storm_label: Label = $StormLabel
@onready var winner_label: Label = $WinnerLabel
## Across the top: pause, game speed, the fog toggles and so on (see Toolbar).
@onready var toolbar: Toolbar = $Toolbar

## Only this many HUD panels are ever shown at once -- whichever characters
## currently rank highest by combat power (see NpcStats.combat_power),
## counting both the living and anyone still serving out their death grace
## period (below). A dying character keeps occupying its slot until that
## grace period actually ends, so a lower-ranked living character isn't
## promoted into its place early.
const VISIBLE_HUD_COUNT := 10
## A character that was on the leaderboard at the moment it died keeps its
## panel on screen (playing the death flash, then sitting frozen and grey)
## for this long before actually dropping off, rather than vanishing the
## instant it's removed from the living roster.
const DEATH_GRACE_SECONDS := 3.0

var rows: Dictionary = {}
## Characters currently in their post-death grace period. Still included in
## the leaderboard ranking (using their frozen stats) so they keep occupying
## a slot until the grace timer actually removes them.
var dying: Dictionary = {}

## The selected character (opened by clicking their icon or gravestone in
## the maze), or null, plus their panel's widgets -- the inspector, at the
## top of the left column.
var inspected: NpcAgent = null
var inspector: Dictionary = {}
## Panels for the rest of the selected character's party, by character,
## listed below the inspector.
var party_panels: Dictionary = {}
## Party members who've just fallen, keeping their (grey, flashing) panel
## for DEATH_GRACE_SECONDS rather than vanishing from the list at once --
## the same courtesy the leaderboard gives (see mark_dead).
var fallen_party_members: Dictionary = {}

## The part of the screen the maze is seen through: between the columns,
## below the toolbar.
func map_area() -> Rect2:
	var top_left := Vector2(left_frame.get_rect().end.x, top_frame.get_rect().end.y)
	return Rect2(top_left, Vector2(right_frame.position.x, left_frame.get_rect().end.y) - top_left)

func _ready() -> void:
	winner_label.visible = false
	battle_window.member_clicked.connect(inspect)
	selection_container.add_theme_constant_override("separation", 2)
	leaderboard_container.add_theme_constant_override("separation", 2)
	# The banner sits just below the toolbar (which has no room left for it
	# in the middle), on a translucent strip so it reads over the maze.
	var banner_bg := StyleBoxFlat.new()
	banner_bg.bg_color = Color(0.0, 0.0, 0.0, 0.65)
	winner_label.add_theme_stylebox_override("normal", banner_bg)

## Keeps the storm line at the top of the map up to date: the countdown to
## it gathering, then to it closing in completely.
func update_storm(storm: Storm) -> void:
	storm_label.text = storm_text(storm)

static func storm_text(storm: Storm) -> String:
	if storm.is_closed():
		return "The storm covers everything"
	if not storm.has_started():
		return "The storm gathers in %s" % _clock(Storm.START_SECONDS - storm.elapsed)
	return "The storm is closing in: %s until it covers everything" % _clock(Storm.CLOSED_SECONDS - storm.elapsed)

## Seconds as m:ss, rounded up -- a countdown never shows 0:00 early.
static func _clock(seconds: float) -> String:
	var whole := ceili(seconds)
	return "%d:%02d" % [whole / 60, whole % 60]

## A single cell for the equipment/potions/spells grid: a fixed-width,
## word-wrapping label, so two long entries sharing a row wrap instead of
## pushing the panel wider than its column.
const GRID_CELL_WIDTH := 200.0

func _make_grid_cell() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.custom_minimum_size = Vector2(GRID_CELL_WIDTH, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

## Builds a progress bar with its value text centered directly on top of it,
## instead of as a separate line, returning the pieces the caller needs to
## keep updating.
static func make_stat_bar(fill_color: Color) -> Dictionary:
	var container := Control.new()
	container.custom_minimum_size = Vector2(0, 14)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 0.6)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	bar.add_theme_stylebox_override("fill", fill)
	container.add_child(bar)

	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 3)
	container.add_child(label)

	return {"container": container, "bar": bar, "label": label, "fill": fill}

## Leaderboard panels are compact -- no gear section (see _build_panel) --
## so all VISIBLE_HUD_COUNT of them fit down the one column.
func register_npc(npc: NpcAgent) -> void:
	var r := _build_panel(npc, false)
	_select_on_click(r["panel"], npc)
	leaderboard_container.add_child(r["panel"])
	rows[npc] = r
	_refresh_row(npc)

## Has a click on `panel` (a leaderboard or party panel) select `npc`, as
## clicking them on the map does -- paused or not, like the map (see
## GameManager._on_world_clicked).
func _select_on_click(panel: PanelContainer, npc: NpcAgent) -> void:
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_ignore_mouse_inside(panel)  # a click on its HP bar is a click on the panel
	panel.gui_input.connect(_on_panel_input.bind(npc))

func _on_panel_input(event: InputEvent, npc: NpcAgent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		inspect(npc)
		accept_event()

## Leaves every Control inside `node` to let the mouse through to it.
static func _ignore_mouse_inside(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse_inside(child)

## Builds one character's stat panel (unparented) and returns its widgets,
## in the shape _fill_panel expects. Shared by the leaderboard rows and the
## selection column's panels, so they all look and read the same -- except
## that only `with_gear` panels (the selected character's own) get the gear section:
## equipment slots, potions and spells.
func _build_panel(npc: NpcAgent, with_gear: bool = true) -> Dictionary:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var c: Color = npc.visual.color
	style.bg_color = Color(c.r, c.g, c.b, 0.28)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(400, 0)
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	# A row rather than a bare label so the inspector can tack its close
	# button onto the end of it.
	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)

	var header := Label.new()
	header.add_theme_font_size_override("font_size", 14)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header)

	# Its own line rather than part of the header: party names run up to
	# ~30 characters, which would push the header past the panel's width.
	# Hidden while on their own (see _fill_panel).
	var party_label := Label.new()
	party_label.add_theme_font_size_override("font_size", 12)
	party_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 1.0))
	vbox.add_child(party_label)

	var action_label := Label.new()
	action_label.add_theme_font_size_override("font_size", 12)
	action_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6, 1.0))
	vbox.add_child(action_label)

	# Once dead, the action line says who or what killed them, and this one
	# says how (see _fill_panel). Hidden while alive.
	var death_label := Label.new()
	death_label.add_theme_font_size_override("font_size", 12)
	death_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.55, 1.0))
	death_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	death_label.visible = false
	vbox.add_child(death_label)

	var hp_widget := make_stat_bar(Color(0.2, 0.8, 0.3))
	vbox.add_child(hp_widget["container"])

	var mp_widget := make_stat_bar(Color(0.25, 0.55, 0.95))
	vbox.add_child(mp_widget["container"])

	var abilities_label := Label.new()
	abilities_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(abilities_label)

	## The gear section: one label per equipment slot, laid out two to a row
	## so the slot list reads as columns rather than one long wrapped block.
	var gear: GridContainer = null
	var slot_labels: Dictionary = {}
	var potions_label: Label = null
	var spells_label: Label = null
	if with_gear:
		gear = GridContainer.new()
		gear.columns = 2
		gear.add_theme_constant_override("h_separation", 12)
		gear.add_theme_constant_override("v_separation", 0)
		vbox.add_child(gear)

		# Every cell gets the same capped width with wrapping allowed, so two
		# long entries sharing a row (e.g. Accessories + Potions, both able to
		# list two items) wrap instead of pushing the panel wider than its column.
		for slot in ItemCatalog.SLOT_ORDER:
			var slot_label := _make_grid_cell()
			gear.add_child(slot_label)
			slot_labels[slot] = slot_label

		# Potions and spells fill out the same grid rather than breaking into
		# separate full-width rows, continuing on from the equipment slots
		# (accessory | potions, then spells alone on the next row).
		potions_label = _make_grid_cell()
		gear.add_child(potions_label)

		spells_label = _make_grid_cell()
		gear.add_child(spells_label)

	## A white overlay on top of the whole panel, flashed on level-up (see
	## flash_level_up) then faded back out.
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(flash)

	return {
		"panel": panel,
		"flash": flash,
		"header_row": header_row,
		"header": header,
		"party": party_label,
		"rank": 0,
		"action": action_label,
		"death": death_label,
		"hp_bar": hp_widget["bar"],
		"hp_fill": hp_widget["fill"],
		"hp_text": hp_widget["label"],
		"mp_bar": mp_widget["bar"],
		"mp_text": mp_widget["label"],
		"abilities": abilities_label,
		"gear": gear,
		"slot_labels": slot_labels,
		"potions": potions_label,
		"spells": spells_label,
	}

func refresh_npc(npc: NpcAgent) -> void:
	_refresh_row(npc)
	if npc == inspected:
		_refresh_inspector()

## Called every frame. Only the leaderboard panels actually on show are
## refreshed -- a hidden one is filled in afresh the frame it's shown.
func update_positions(npcs: Array) -> void:
	_update_players_left(npcs)
	_update_leaderboard(npcs)
	for npc in npcs:
		if rows.has(npc) and rows[npc]["panel"].visible:
			_refresh_row(npc)
	_refresh_inspector()

## Opens (or switches) the inspector to show `npc` at the top of the left
## column, independent of whether they're on the leaderboard, with the rest
## of their party listed below it.
func inspect(npc: NpcAgent) -> void:
	close_inspector()
	inspected = npc
	inspector = _build_panel(npc)
	var panel: PanelContainer = inspector["panel"]

	var close_button := Button.new()
	close_button.text = "✕"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	# Like the pause button, stays clickable while the game is paused.
	close_button.process_mode = Node.PROCESS_MODE_ALWAYS
	close_button.pressed.connect(close_inspector)
	inspector["header_row"].add_child(close_button)
	inspector["close_button"] = close_button

	selection_container.add_child(panel)
	_refresh_inspector()
	selection_changed.emit()

func close_inspector() -> void:
	if inspector.has("panel"):
		_discard_panel(inspector["panel"])
	for member in party_panels:
		_discard_panel(party_panels[member]["panel"])
	party_panels = {}
	fallen_party_members = {}
	inspector = {}
	inspected = null
	selection_changed.emit()

## Out of the column straight away (so a new selection lays out cleanly),
## freed at the end of the frame.
func _discard_panel(panel: Control) -> void:
	if panel.get_parent() != null:
		panel.get_parent().remove_child(panel)
	panel.queue_free()

## Called every frame, but also straight from inspect() so a click while
## paused (when update_positions isn't running) still shows current stats.
func _refresh_inspector() -> void:
	if inspected == null:
		return
	inspector["rank"] = rows[inspected]["rank"] if rows.has(inspected) else 0
	_fill_panel(inspector, inspected)
	# Dead characters drop out of `npcs` but stay inspectable, frozen on
	# their final stats and greyed out like their leaderboard panel.
	if inspected.dead:
		inspector["header"].text += "  ☠ DEAD"
		inspector["panel"].modulate = Color(0.5, 0.5, 0.5, 1.0)
	_sync_party_panels()
	for member in party_panels:
		var r: Dictionary = party_panels[member]
		r["rank"] = rows[member]["rank"] if rows.has(member) else 0
		_fill_panel(r, member)
		if member.dead:
			r["header"].text += "  ☠ DEAD"
			r["panel"].modulate = Color(0.5, 0.5, 0.5, 1.0)

## Keeps one panel below the inspector for each other living member of the
## selected character's party, in party order -- adding them as they join,
## dropping them as they leave, and a little after they fall (see
## fallen_party_members). None for a dead selection.
func _sync_party_panels() -> void:
	var members: Array = []
	if not inspected.dead:
		for m in inspected.living_party():
			if m != inspected:
				members.append(m)
		for m in fallen_party_members:
			if party_panels.has(m):
				members.append(m)
	for m in party_panels.keys():
		if not members.has(m):
			_discard_panel(party_panels[m]["panel"])
			party_panels.erase(m)
	for i in range(members.size()):
		var m: NpcAgent = members[i]
		if not party_panels.has(m):
			party_panels[m] = _build_panel(m, false)
			_select_on_click(party_panels[m]["panel"], m)
			selection_container.add_child(party_panels[m]["panel"])
		selection_container.move_child(party_panels[m]["panel"], i + 1)

## `rows` keeps every character ever registered (dead ones included), so it
## doubles as the starting headcount.
func _update_players_left(npcs: Array) -> void:
	var alive := 0
	for npc in npcs:
		if not npc.dead:
			alive += 1
	toolbar.show_players_left(alive, rows.size())

## Ranks every living character (dead ones are already excluded from
## `npcs` by the time this is called -- see GameManager._on_npc_died) plus
## anyone still serving out their death grace period (see mark_dead, using
## their frozen stats) together by combat power, and shows only the panels
## for the top VISIBLE_HUD_COUNT, in rank order. A dying character keeps occupying its
## slot in this combined ranking for as long as its grace period lasts, so
## a lower-ranked living character only gets promoted into view once that
## slot is actually freed up -- never while the dead one is still showing.
func _update_leaderboard(npcs: Array) -> void:
	var ranked: Array = npcs.duplicate()
	for npc in dying:
		if not ranked.has(npc):
			ranked.append(npc)
	ranked.sort_custom(func(a, b): return a.stats.combat_power() > b.stats.combat_power())

	var shown: Dictionary = {}
	for i in range(min(VISIBLE_HUD_COUNT, ranked.size())):
		shown[ranked[i]] = i + 1

	for npc in rows:
		var rank: int = shown.get(npc, 0)
		rows[npc]["rank"] = rank
		rows[npc]["panel"].visible = rank > 0

	_order_leaderboard(shown)

## Stacks the shown panels at the top of the leaderboard column, #1 first.
func _order_leaderboard(shown: Dictionary) -> void:
	var ranked_shown: Array = shown.keys()
	ranked_shown.sort_custom(func(a, b): return shown[a] < shown[b])
	for i in range(ranked_shown.size()):
		leaderboard_container.move_child(rows[ranked_shown[i]]["panel"], i)

func _refresh_row(npc: NpcAgent) -> void:
	if not rows.has(npc):
		return
	_fill_panel(rows[npc], npc)

## Writes `npc`'s current stats into a panel built by _build_panel.
func _fill_panel(r: Dictionary, npc: NpcAgent) -> void:
	var s: NpcStats = npc.stats

	var rank_tag: String = "#%d " % int(r["rank"]) if int(r["rank"]) > 0 else ""
	r["header"].text = "%s%s [%s] — Lv.%d (%d/%d XP)  %dg" % [rank_tag, npc.npc_name, s.alignment, s.level, s.xp, s.xp_to_next, s.gold]
	var in_party: bool = npc.party.size() > 1
	r["party"].visible = in_party
	if in_party:
		r["party"].text = "Party: %s (%d)" % [npc.party_name, npc.party.size()]
	r["action"].text = "Action: %s" % npc.current_action
	r["death"].visible = npc.dead
	if npc.dead:
		r["action"].text = "Killed by: %s" % (npc.killed_by if npc.killed_by != "" else "unknown")
		r["death"].text = "How: %s" % (npc.death_method if npc.death_method != "" else "unknown")

	var hp_bar: ProgressBar = r["hp_bar"]
	hp_bar.max_value = s.max_hp
	hp_bar.value = s.hp
	r["hp_text"].text = "HP %d/%d" % [s.hp, s.max_hp]
	var ratio: float = clampf(float(s.hp) / float(max(s.max_hp, 1)), 0.0, 1.0)
	var hp_fill: StyleBoxFlat = r["hp_fill"]
	hp_fill.bg_color = Color(1.0, 0.15, 0.15).lerp(Color(0.2, 0.85, 0.3), ratio)

	var mp_bar: ProgressBar = r["mp_bar"]
	mp_bar.max_value = s.max_mp
	mp_bar.value = s.mp
	r["mp_text"].text = "MP %d/%d" % [s.mp, s.max_mp]

	r["abilities"].text = "STR %d  DEX %d  CON %d  INT %d  WIS %d  CHA %d" % [
		s.strength, s.dexterity, s.constitution, s.intelligence, s.wisdom, s.charisma
	]

	if r["gear"] == null:
		return
	var slot_labels: Dictionary = r["slot_labels"]
	for slot in ItemCatalog.SLOT_ORDER:
		slot_labels[slot].text = _slot_text(s, slot)

	var potion_parts: Array = []
	for potion_name in ItemCatalog.stockable_names(ItemCatalog.RARITY_BRONZE):
		var count: int = int(s.inventory.get(potion_name, 0))
		if count > 0:
			potion_parts.append("%s x%d" % [potion_name, count])
	r["potions"].text = "Potions: %s" % ("-" if potion_parts.is_empty() else ", ".join(potion_parts))

	var spell_names: Array = []
	for spell in s.known_spells:
		spell_names.append(String(spell).capitalize())
	r["spells"].text = "Spells: %s" % ("-" if spell_names.is_empty() else ", ".join(spell_names))

## "Hands: Iron Sword, Shield" — or "Hands: -" when the slot is empty.
func _slot_text(s: NpcStats, slot: String) -> String:
	var worn: Array = s.equipped_in(slot)
	return "%s: %s" % [ItemCatalog.SLOT_LABELS[slot], "-" if worn.is_empty() else ", ".join(worn)]

## Freezes the panel on its final stats, tints it grey to show the character
## has died and is out of the run, and flashes red on the way there.
func mark_dead(npc: NpcAgent) -> void:
	if not rows.has(npc):
		return
	var r: Dictionary = rows[npc]
	var was_on_leaderboard: bool = int(r["rank"]) > 0
	_refresh_row(npc)
	r["panel"].modulate = Color(0.5, 0.5, 0.5, 1.0)
	r["header"].text += "  ☠ DEAD"
	if party_panels.has(npc):
		fallen_party_members[npc] = true
		get_tree().create_timer(DEATH_GRACE_SECONDS, false).timeout.connect(func():
			fallen_party_members.erase(npc)
			if inspected != null:
				_refresh_inspector()
		)
	if npc == inspected or party_panels.has(npc):
		_refresh_inspector()
	_flash(npc, Color(1.0, 0.15, 0.15))

	# It was visible on the leaderboard right up until it died -- keep it
	# there a little longer (frozen, death flash playing) instead of having
	# it vanish the instant it's removed from the living roster.
	if was_on_leaderboard:
		dying[npc] = true
		r["panel"].visible = true
		var timer := get_tree().create_timer(DEATH_GRACE_SECONDS, false)
		timer.timeout.connect(func():
			dying.erase(npc)
			if rows.has(npc):
				r["panel"].visible = false
		)

## Briefly flashes the character's whole panel white to celebrate a level-up.
func flash_level_up(npc: NpcAgent) -> void:
	_flash(npc, Color(1, 1, 1))

## Flashes a color over the character's panel (and their inspector, if
## open), fading back out.
func _flash(npc: NpcAgent, color: Color) -> void:
	if rows.has(npc):
		_flash_rect(rows[npc]["flash"], color)
	if npc == inspected:
		_flash_rect(inspector["flash"], color)
	if party_panels.has(npc):
		_flash_rect(party_panels[npc]["flash"], color)

func _flash_rect(flash: ColorRect, color: Color) -> void:
	flash.color = Color(color.r, color.g, color.b, 0.9)
	var tween := flash.create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.6)

func announce_no_winner() -> void:
	winner_label.text = "Everyone has fallen — no winner"
	winner_label.visible = true

func announce_winner(npc: NpcAgent) -> void:
	winner_label.text = "%s wins the race! (Level %d)" % [npc.npc_name, npc.stats.level]
	winner_label.visible = true
