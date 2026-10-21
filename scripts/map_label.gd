class_name MapLabel
extends Label

## The label over a character on the map. At rest it says who they are --
## the text NpcAgent hands it (see NpcAgent.sync_label); otherwise it's
## showing something in passing (a find, a fight, a party growing), either
## for a few seconds or until it's put back to rest.

## How long a passing message stays up, by default, before the label goes
## back to rest.
const MESSAGE_SECONDS := 1.5
## In a party, the one label left showing (the leader's) sits this much
## higher, clear of the members' icons standing around it.
const PARTY_LIFT := 10.0

## Whether it's showing something other than its resting text (see
## show_message), and for a passing message, the seconds until it goes
## back -- 0 means until something calls rest (e.g. a fight ending).
var busy := false
var time_left := 0.0
var _base_y := 0.0

func _ready() -> void:
	_base_y = position.y

## Shows `message` in place of the resting text, for `seconds` -- or, if 0,
## until rest puts it back.
func show_message(message: String, seconds: float = 0.0) -> void:
	text = message
	busy = true
	time_left = seconds

## Counts down a passing message; true once it's just run out, when it's
## time for the label to go back to rest.
func tick(delta: float) -> bool:
	if time_left <= 0.0:
		return false
	time_left -= delta
	return time_left <= 0.0

## Takes over whatever `other` is showing, countdown and all.
func copy_from(other: MapLabel) -> void:
	text = other.text
	busy = other.busy
	time_left = other.time_left

## Back to rest, showing `resting_text`.
func rest(resting_text: String) -> void:
	busy = false
	time_left = 0.0
	text = resting_text

## Shows or hides it, raised clear of a party's icons or not; a label at
## rest also takes up `resting_text`, while one busy showing something
## leaves that be until it's back at rest.
func place(shown: bool, raised: bool, resting_text: String) -> void:
	visible = shown
	position.y = _base_y - (PARTY_LIFT if raised else 0.0)
	if not busy:
		text = resting_text
