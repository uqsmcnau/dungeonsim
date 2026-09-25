class_name Hud
extends Control

@onready var left_container: VBoxContainer = $LeftStats
@onready var right_container: VBoxContainer = $RightStats
@onready var winner_label: Label = $WinnerLabel

var rows: Dictionary = {}
var left_count: int = 0
var right_count: int = 0

func _ready() -> void:
	winner_label.visible = false
	left_container.add_theme_constant_override("separation", 6)
	right_container.add_theme_constant_override("separation", 6)

## Builds a progress bar with its value text centered directly on top of it,
## instead of as a separate line, returning the pieces the caller needs to
## keep updating.
func _make_stat_bar(fill_color: Color) -> Dictionary:
	var container := Control.new()
	container.custom_minimum_size = Vector2(0, 16)

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

## Alternates new panels between the left and right columns flanking the
## maze, keeping both sides balanced regardless of how many NPCs there are.
func register_npc(npc: NpcAgent) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var c: Color = npc.visual.color
	style.bg_color = Color(c.r, c.g, c.b, 0.28)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)
	if left_count <= right_count:
		left_container.add_child(panel)
		left_count += 1
	else:
		right_container.add_child(panel)
		right_count += 1

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(400, 0)
	vbox.add_theme_constant_override("separation", 1)
	panel.add_child(vbox)

	var header := Label.new()
	vbox.add_child(header)

	var hp_widget := _make_stat_bar(Color(0.2, 0.8, 0.3))
	vbox.add_child(hp_widget["container"])

	var mp_widget := _make_stat_bar(Color(0.25, 0.55, 0.95))
	vbox.add_child(mp_widget["container"])

	var abilities_label := Label.new()
	vbox.add_child(abilities_label)

	var hit_label := Label.new()
	hit_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hit_label)

	var equipment_label := Label.new()
	equipment_label.add_theme_font_size_override("font_size", 12)
	equipment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(equipment_label)

	rows[npc] = {
		"panel": panel,
		"header": header,
		"hp_bar": hp_widget["bar"],
		"hp_fill": hp_widget["fill"],
		"hp_text": hp_widget["label"],
		"mp_bar": mp_widget["bar"],
		"mp_text": mp_widget["label"],
		"abilities": abilities_label,
		"hit": hit_label,
		"equipment": equipment_label,
	}
	_refresh_row(npc)

func refresh_npc(npc: NpcAgent) -> void:
	_refresh_row(npc)

func update_positions(npcs: Array) -> void:
	for npc in npcs:
		_refresh_row(npc)

func _refresh_row(npc: NpcAgent) -> void:
	if not rows.has(npc):
		return
	var r: Dictionary = rows[npc]
	var s: NpcStats = npc.stats

	r["header"].text = "%s — Lv.%d (%d/%d XP)  %dg" % [npc.npc_name, s.level, s.xp, s.xp_to_next, s.gold]

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

	r["hit"].text = "Accuracy +%d%%   Evasion +%d%%   (from DEX)" % [roundi(s.accuracy() * 100.0), roundi(s.evasion() * 100.0)]

	var owned: Array = s.inventory.keys()
	var equipment_text: String = "None" if owned.is_empty() else ", ".join(owned)
	var spares: Array = []
	for item_name in owned:
		if s.spare_count(item_name) > 0:
			spares.append("%s x%d" % [item_name, s.spare_count(item_name)])
	r["equipment"].text = "Equipped: %s" % equipment_text
	if not spares.is_empty():
		var shown: Array = spares.slice(0, 2)
		var extra: int = spares.size() - shown.size()
		var spare_text: String = ", ".join(shown)
		if extra > 0:
			spare_text += " +%d more" % extra
		r["equipment"].text += "\nSpare (no bonus): %s" % spare_text

## Freezes the panel on its final stats and tints it grey to show the
## character has died and is out of the run.
func mark_dead(npc: NpcAgent) -> void:
	if not rows.has(npc):
		return
	_refresh_row(npc)
	var r: Dictionary = rows[npc]
	r["panel"].modulate = Color(0.5, 0.5, 0.5, 1.0)
	r["header"].text += "  ☠ DEAD"

func announce_no_winner() -> void:
	winner_label.text = "Everyone has fallen — no winner"
	winner_label.visible = true

func announce_winner(npc: NpcAgent) -> void:
	winner_label.text = "%s wins the race! (Level %d)" % [npc.npc_name, npc.stats.level]
	winner_label.visible = true
