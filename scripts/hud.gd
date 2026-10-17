class_name Hud
extends Control

## Forwarded from the fog-of-war checkbox so GameManager can wire it
## straight to MazeView without Hud needing to know about MazeView at all.
signal fog_toggled(enabled: bool)

@onready var left_container: VBoxContainer = $LeftStats
@onready var right_container: VBoxContainer = $RightStats
@onready var winner_label: Label = $WinnerLabel
@onready var fog_toggle: CheckBox = $FogToggle

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

func _ready() -> void:
	winner_label.visible = false
	left_container.add_theme_constant_override("separation", 2)
	right_container.add_theme_constant_override("separation", 2)
	fog_toggle.toggled.connect(func(pressed: bool): fog_toggled.emit(pressed))

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
func _make_stat_bar(fill_color: Color) -> Dictionary:
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

## New panels start in the left column -- _balance_columns reassigns them
## (along with everyone else) the moment the leaderboard next updates, so
## where they start doesn't matter.
func register_npc(npc: NpcAgent) -> void:
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
	left_container.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(400, 0)
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	var header := Label.new()
	header.add_theme_font_size_override("font_size", 14)
	vbox.add_child(header)

	var action_label := Label.new()
	action_label.add_theme_font_size_override("font_size", 12)
	action_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6, 1.0))
	vbox.add_child(action_label)

	var hp_widget := _make_stat_bar(Color(0.2, 0.8, 0.3))
	vbox.add_child(hp_widget["container"])

	var mp_widget := _make_stat_bar(Color(0.25, 0.55, 0.95))
	vbox.add_child(mp_widget["container"])

	var abilities_label := Label.new()
	abilities_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(abilities_label)

	## One label per equipment slot, laid out two to a row so the slot list
	## reads as columns rather than one long wrapped block.
	var equipment_grid := GridContainer.new()
	equipment_grid.columns = 2
	equipment_grid.add_theme_constant_override("h_separation", 12)
	equipment_grid.add_theme_constant_override("v_separation", 0)
	vbox.add_child(equipment_grid)

	# Every cell gets the same capped width with wrapping allowed, so two
	# long entries sharing a row (e.g. Accessories + Potions, both able to
	## list two items) wrap instead of pushing the panel wider than its column.
	var slot_labels: Dictionary = {}
	for slot in ItemCatalog.SLOT_ORDER:
		var slot_label := _make_grid_cell()
		equipment_grid.add_child(slot_label)
		slot_labels[slot] = slot_label

	# Potions and spells fill out the same grid rather than breaking into
	# separate full-width rows, continuing on from the equipment slots
	# (accessory | potions, then spells alone on the next row).
	var potions_label := _make_grid_cell()
	equipment_grid.add_child(potions_label)

	var spells_label := _make_grid_cell()
	equipment_grid.add_child(spells_label)

	## A white overlay on top of the whole panel, flashed on level-up (see
	## flash_level_up) then faded back out.
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(flash)

	rows[npc] = {
		"panel": panel,
		"flash": flash,
		"header": header,
		"rank": 0,
		"action": action_label,
		"hp_bar": hp_widget["bar"],
		"hp_fill": hp_widget["fill"],
		"hp_text": hp_widget["label"],
		"mp_bar": mp_widget["bar"],
		"mp_text": mp_widget["label"],
		"abilities": abilities_label,
		"slot_labels": slot_labels,
		"potions": potions_label,
		"spells": spells_label,
	}
	_refresh_row(npc)

func refresh_npc(npc: NpcAgent) -> void:
	_refresh_row(npc)

func update_positions(npcs: Array) -> void:
	_update_leaderboard(npcs)
	for npc in npcs:
		_refresh_row(npc)

## Ranks every living character (dead ones are already excluded from
## `npcs` by the time this is called -- see GameManager._on_npc_died) plus
## anyone still serving out their death grace period (see mark_dead, using
## their frozen stats) together by combat power, and shows only the panels
## for the top VISIBLE_HUD_COUNT. A dying character keeps occupying its
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

	_balance_columns(shown)

## Keeps the two columns balanced -- odd ranks in the left column, even
## ranks in the right, so the normal 10-visible case always lands exactly
## 5 and 5 -- rather than leaving each panel in whichever column it
## happened to start in, which could leave one column crowded and the
## other sparse once only a shifting subset of characters are ever shown.
func _balance_columns(shown: Dictionary) -> void:
	var ranked_shown: Array = shown.keys()
	ranked_shown.sort_custom(func(a, b): return shown[a] < shown[b])
	var left_index := 0
	var right_index := 0
	for npc in ranked_shown:
		var panel: PanelContainer = rows[npc]["panel"]
		if int(shown[npc]) % 2 == 1:
			if panel.get_parent() != left_container:
				panel.reparent(left_container)
			left_container.move_child(panel, left_index)
			left_index += 1
		else:
			if panel.get_parent() != right_container:
				panel.reparent(right_container)
			right_container.move_child(panel, right_index)
			right_index += 1

func _refresh_row(npc: NpcAgent) -> void:
	if not rows.has(npc):
		return
	var r: Dictionary = rows[npc]
	var s: NpcStats = npc.stats

	var party_tag: String = " (Party of %d)" % npc.party.size() if npc.party.size() > 1 else ""
	var rank_tag: String = "#%d " % int(r["rank"]) if int(r["rank"]) > 0 else ""
	r["header"].text = "%s%s [%s]%s — Lv.%d (%d/%d XP)  %dg" % [rank_tag, npc.npc_name, s.alignment, party_tag, s.level, s.xp, s.xp_to_next, s.gold]
	r["action"].text = "Action: %s" % npc.current_action

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
	_flash(npc, Color(1.0, 0.15, 0.15))

	# It was visible on the leaderboard right up until it died -- keep it
	# there a little longer (frozen, death flash playing) instead of having
	# it vanish the instant it's removed from the living roster.
	if was_on_leaderboard:
		dying[npc] = true
		r["panel"].visible = true
		var timer := get_tree().create_timer(DEATH_GRACE_SECONDS)
		timer.timeout.connect(func():
			dying.erase(npc)
			if rows.has(npc):
				r["panel"].visible = false
		)

## Briefly flashes the character's whole panel white to celebrate a level-up.
func flash_level_up(npc: NpcAgent) -> void:
	_flash(npc, Color(1, 1, 1))

## Flashes a color over the character's panel, fading back out.
func _flash(npc: NpcAgent, color: Color) -> void:
	if not rows.has(npc):
		return
	var flash: ColorRect = rows[npc]["flash"]
	flash.color = Color(color.r, color.g, color.b, 0.9)
	var tween := flash.create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.6)

func announce_no_winner() -> void:
	winner_label.text = "Everyone has fallen — no winner"
	winner_label.visible = true

func announce_winner(npc: NpcAgent) -> void:
	winner_label.text = "%s wins the race! (Level %d)" % [npc.npc_name, npc.stats.level]
	winner_label.visible = true
