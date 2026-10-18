class_name MusicPlayer
extends Node

## Background music: plays the tracks in `music_dir` (res://BGM -- kept out
## of git, so drop your own in) in random order, crossfading from one to the
## next over CROSSFADE_SECONDS as each nears its end. No tracks (e.g. a fresh
## clone, or CI) just means silence.
##
## Tracks are read straight from disk (AudioStreamMP3/OggVorbis/WAV
## load_from_file) rather than through Godot's import system, so they work
## whether or not the editor has imported them. Two players take turns: the
## one playing fades out while the other fades in. Pauses along with the
## game -- the players and the fade tween are ordinary pausable nodes.

const CROSSFADE_SECONDS := 1.0
const EXTENSIONS := ["mp3", "ogg", "wav"]
## The audio bus the music plays on, created on demand -- the toolbar's
## volume control sets this bus's volume, so it never fights the crossfade,
## which works on the players' own volumes.
const BUS := "Music"

@export_dir var music_dir: String = "res://BGM"
## Starting music volume, 0 to 1 (also where the toolbar slider starts).
@export_range(0.0, 1.0, 0.01) var volume: float = 0.5

## Every track found in `music_dir`, as full paths.
var tracks: Array[String] = []
## The track playing (or fading in) right now, or "" if none.
var current_track: String = ""
var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _fade: Tween = null

func _ready() -> void:
	# Pauses with the game wherever it's put, even under an always-processing
	# parent (the players and the fade tween follow it).
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_ensure_bus()
	for i in range(2):
		var player := AudioStreamPlayer.new()
		player.bus = BUS
		player.finished.connect(_on_player_finished.bind(player))
		add_child(player)
		_players.append(player)
	set_volume(volume)
	tracks = find_tracks(music_dir)
	if not tracks.is_empty():
		_play(_pick_next_track())

func _process(_delta: float) -> void:
	var player := active_player()
	if is_fading() or not player.playing or player.stream == null:
		return
	if player.stream.get_length() - player.get_playback_position() <= CROSSFADE_SECONDS:
		crossfade_to(_pick_next_track())

## The audio files in `dir`, sorted, as full paths ([] if it doesn't exist).
## Skips everything else there, e.g. the editor's .import files.
static func find_tracks(dir: String) -> Array[String]:
	var found: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return found
	for file in DirAccess.get_files_at(dir):
		if EXTENSIONS.has(file.get_extension().to_lower()):
			found.append(dir.path_join(file))
	found.sort()
	return found

## The player whose track is playing, or fading in.
func active_player() -> AudioStreamPlayer:
	return _players[_active]

func is_fading() -> bool:
	return _fade != null and _fade.is_valid() and _fade.is_running()

## Sets the music volume, 0 (muted) to 1.
func set_volume(value: float) -> void:
	volume = clampf(value, 0.0, 1.0)
	var bus := AudioServer.get_bus_index(BUS)
	AudioServer.set_bus_volume_db(bus, _to_db(volume))
	AudioServer.set_bus_mute(bus, volume <= 0.0)

## Fades the current track out and `path` in, together, over
## CROSSFADE_SECONDS. The outgoing player stops once it's silent.
func crossfade_to(path: String) -> void:
	var stream := _load(path)
	if stream == null:
		return
	var outgoing := active_player()
	_active = 1 - _active
	var incoming := active_player()
	incoming.stream = stream
	_set_level(0.0, incoming)
	incoming.play()
	current_track = path
	_fade = create_tween().set_parallel()
	_fade.tween_method(_set_level.bind(incoming), 0.0, 1.0, CROSSFADE_SECONDS)
	_fade.tween_method(_set_level.bind(outgoing), 1.0, 0.0, CROSSFADE_SECONDS)
	_fade.chain().tween_callback(outgoing.stop)

## A random track, other than the current one if there's any choice.
func _pick_next_track() -> String:
	var choices: Array[String] = tracks.filter(func(t): return t != current_track)
	if choices.is_empty():
		choices = tracks
	return choices[randi() % choices.size()]

## Starts `path` straight away at full volume, no fade.
func _play(path: String) -> void:
	var stream := _load(path)
	if stream == null:
		return
	var player := active_player()
	player.stream = stream
	_set_level(1.0, player)
	player.play()
	current_track = path

## A track that ran out without a crossfade (one shorter than the fade, say)
## goes straight on to the next.
func _on_player_finished(player: AudioStreamPlayer) -> void:
	if player == active_player() and not is_fading() and not tracks.is_empty():
		_play(_pick_next_track())

func _set_level(level: float, player: AudioStreamPlayer) -> void:
	player.volume_db = _to_db(level)

## Like linear_to_db, but silence is -80 dB rather than -infinity.
static func _to_db(level: float) -> float:
	return maxf(linear_to_db(level), -80.0)

static func _load(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null

static func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS)
	AudioServer.set_bus_send(index, "Master")
