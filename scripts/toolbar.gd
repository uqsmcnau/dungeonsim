class_name Toolbar
extends Control

## The strip across the top of the map: fog of war and Party Vision, pause,
## game speed, Guidance's readiness, music volume and the players-left count.
## Hands the spectator's choices on as signals (GameManager wires them up),
## except pausing, which it does itself. Every control runs with
## PROCESS_MODE_ALWAYS, so the bar stays usable while the game is paused.

## From the fog-of-war checkbox, for GameManager to pass to MazeView.
signal fog_toggled(enabled: bool)
## From the Party Vision checkbox (see GameManager.party_vision).
signal party_vision_toggled(enabled: bool)
## From the music volume slider (0 to 1).
signal volume_changed(volume: float)
## From the speed button: the game should now run `speed` times as fast
## (one of GAME_SPEEDS).
signal speed_changed(speed: float)

## The speeds the speed button steps through, slowest first.
const GAME_SPEEDS: Array[float] = [1.0, 2.0, 5.0, 10.0]
const GUIDANCE_READY_COLOR := Color(0.95, 0.75, 0.2)
const GUIDANCE_COOLING_COLOR := Color(0.4, 0.45, 0.55)

@onready var fog_toggle: CheckBox = $FogToggle
@onready var party_vision_toggle: CheckBox = $PartyVisionToggle
## Music volume, 0 to 1 (see MusicPlayer).
@onready var volume_slider: HSlider = $VolumeSlider
## Pauses the whole SceneTree (Space does too).
@onready var pause_button: Button = $PauseButton
## Cycles through GAME_SPEEDS: a click speeds the game up, a right-click
## slows it down.
@onready var speed_button: Button = $SpeedButton
@onready var players_left_label: Label = $PlayersLeftLabel
## Shows whether Guidance (right-click "go there", see
## GameManager._on_world_right_clicked) is ready, or how long until it is.
@onready var guidance_indicator: Control = $GuidanceIndicator
var guidance_widget: Dictionary = {}

## The game speed currently showing on the speed button.
var game_speed := 1.0

func _ready() -> void:
	fog_toggle.toggled.connect(func(pressed: bool): fog_toggled.emit(pressed))
	party_vision_toggle.toggled.connect(func(pressed: bool): party_vision_toggled.emit(pressed))
	volume_slider.value_changed.connect(func(value: float): volume_changed.emit(value))
	pause_button.toggled.connect(set_paused)
	speed_button.pressed.connect(func(): step_speed(1))
	speed_button.gui_input.connect(_on_speed_button_input)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	pause_button.shortcut = Shortcut.new()
	pause_button.shortcut.events = [space]
	# Space also "presses" whichever button has keyboard focus, so once the
	# fog checkbox had been clicked it would swallow Space as a fog toggle.
	# Keep the toolbar's controls out of focus so Space always means pause.
	for control in [pause_button, fog_toggle, party_vision_toggle, volume_slider, speed_button]:
		control.focus_mode = Control.FOCUS_NONE

	guidance_widget = Hud.make_stat_bar(GUIDANCE_READY_COLOR)
	var guidance_bar: Control = guidance_widget["container"]
	guidance_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Let hovers through to the indicator itself, which carries the tooltip.
	guidance_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guidance_widget["bar"].mouse_filter = Control.MOUSE_FILTER_IGNORE
	guidance_widget["label"].add_theme_font_size_override("font_size", 14)
	guidance_indicator.add_child(guidance_bar)
	update_guidance(0.0, 1.0)

func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	pause_button.set_pressed_no_signal(paused)
	pause_button.text = "Resume" if paused else "Pause"

## Moves the game speed `steps` along GAME_SPEEDS (negative to slow down),
## stopping at either end.
func step_speed(steps: int) -> void:
	var i := clampi(GAME_SPEEDS.find(game_speed) + steps, 0, GAME_SPEEDS.size() - 1)
	if GAME_SPEEDS[i] == game_speed:
		return
	show_speed(GAME_SPEEDS[i])
	speed_changed.emit(game_speed)

func show_speed(speed: float) -> void:
	game_speed = speed
	speed_button.text = "Speed x%d" % int(speed)

func _on_speed_button_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		step_speed(-1)
		speed_button.accept_event()

## Fills up as Guidance recharges: gold "Guidance ready" when it's usable,
## otherwise a greyed bar counting down the seconds left.
func update_guidance(cooldown_left: float, cooldown_total: float) -> void:
	var bar: ProgressBar = guidance_widget["bar"]
	var fill: StyleBoxFlat = guidance_widget["fill"]
	var label: Label = guidance_widget["label"]
	bar.step = 0.0  # continuous -- a fraction, not whole numbers
	bar.max_value = 1.0
	if cooldown_left <= 0.0:
		bar.value = 1.0
		fill.bg_color = GUIDANCE_READY_COLOR
		label.text = "Guidance ready"
	else:
		bar.value = 1.0 - cooldown_left / cooldown_total
		fill.bg_color = GUIDANCE_COOLING_COLOR
		label.text = "Guidance %ds" % ceili(cooldown_left)

## A quick red flash on the indicator when Guidance is tried on cooldown.
func guidance_denied() -> void:
	guidance_indicator.modulate = Color(1.0, 0.35, 0.35)
	var tween := guidance_indicator.create_tween()
	tween.tween_property(guidance_indicator, "modulate", Color.WHITE, 0.4)

func show_players_left(alive: int, total: int) -> void:
	players_left_label.text = "Players left: %d / %d" % [alive, total]
