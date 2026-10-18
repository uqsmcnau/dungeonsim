extends DungeonTest

## Covers the background music: a random track from the music folder at
## start, crossfading to another as each nears its end, pausing with the
## game, and the toolbar's volume control. Uses short generated tracks in
## a scratch folder rather than whatever's in res://BGM (not in git).

const TEST_DIR := "user://test_bgm"
const TRACK_SECONDS := 3.0

var music: MusicPlayer

func before_all():
	DirAccess.make_dir_recursive_absolute(TEST_DIR)
	for track_name in ["a.wav", "b.wav", "c.wav"]:
		_silent_wav(TRACK_SECONDS).save_to_wav(TEST_DIR.path_join(track_name))
	# Not music, so never picked.
	FileAccess.open(TEST_DIR.path_join("notes.txt"), FileAccess.WRITE).store_string("hi")
	FileAccess.open(TEST_DIR.path_join("a.wav.import"), FileAccess.WRITE).store_string("[remap]")

func after_all():
	for file in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR.path_join(file))
	DirAccess.remove_absolute(TEST_DIR)

func after_each():
	get_tree().paused = false

static func _silent_wav(seconds: float) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(int(8000 * seconds) * 2)
	wav.data = data
	return wav

## A music player on the scratch tracks, started the way the game starts it.
func _music(dir: String = TEST_DIR) -> MusicPlayer:
	music = MusicPlayer.new()
	music.music_dir = dir
	add_child_autofree(music)
	return music

## Puts the playing track `seconds` from its end.
func _near_the_end(seconds: float) -> void:
	var player := music.active_player()
	player.seek(player.stream.get_length() - seconds)

func _playing_players() -> Array:
	return music._players.filter(func(p): return p.playing)

# ================================ Tracks ==================================

func test_only_audio_files_count_as_tracks():
	var tracks := MusicPlayer.find_tracks(TEST_DIR)
	assert_eq(tracks, [TEST_DIR.path_join("a.wav"), TEST_DIR.path_join("b.wav"), TEST_DIR.path_join("c.wav")])

func test_a_random_track_starts_playing_at_once():
	_music()
	assert_has(music.tracks, music.current_track)
	assert_true(music.active_player().playing)

func test_every_track_gets_its_turn_at_starting():
	var started := {}
	for i in range(30):
		started[_music().current_track] = true
		music.queue_free()
	assert_eq(started.size(), 3, "random, not always the same one")

func test_no_music_folder_means_silence_not_a_crash():
	_music("user://no_such_folder")
	assert_true(music.tracks.is_empty())
	assert_eq(_playing_players().size(), 0)

# =============================== Crossfade ================================

func test_a_track_nearing_its_end_crossfades_to_another():
	_music()
	var first: String = music.current_track
	var outgoing := music.active_player()
	_near_the_end(MusicPlayer.CROSSFADE_SECONDS - 0.2)
	await wait_process_frames(2)
	assert_true(music.is_fading())
	assert_ne(music.current_track, first, "a different track")
	assert_eq(_playing_players().size(), 2, "both playing while they overlap")
	assert_ne(music.active_player(), outgoing)

func test_the_crossfade_takes_a_second():
	_music()
	var outgoing := music.active_player()
	_near_the_end(MusicPlayer.CROSSFADE_SECONDS + 0.5)  # starts fading in half a second
	await wait_seconds(0.5 + MusicPlayer.CROSSFADE_SECONDS / 2.0)
	var incoming := music.active_player()
	assert_ne(incoming, outgoing, "sanity: the fade has started")
	assert_between(incoming.volume_db, -40.0, -0.5, "halfway: fading in")
	assert_between(outgoing.volume_db, -40.0, -0.5, "halfway: fading out")
	await wait_seconds(MusicPlayer.CROSSFADE_SECONDS / 2.0 + 0.2)
	assert_false(music.is_fading())
	assert_almost_eq(incoming.volume_db, 0.0, 0.01, "the new track at full volume")
	assert_false(outgoing.playing, "the old one stopped")

func test_a_track_that_ends_without_a_crossfade_goes_straight_on():
	_music()
	var first: String = music.current_track
	music.active_player().stop()
	music.active_player().finished.emit()
	assert_ne(music.current_track, first)
	assert_true(music.active_player().playing)

func test_one_track_on_its_own_loops_back_round():
	DirAccess.make_dir_recursive_absolute(TEST_DIR + "_solo")
	_silent_wav(TRACK_SECONDS).save_to_wav(TEST_DIR + "_solo/only.wav")
	_music(TEST_DIR + "_solo")
	_near_the_end(0.5)
	await wait_process_frames(2)
	assert_true(music.is_fading())
	assert_eq(music.current_track, TEST_DIR + "_solo/only.wav")
	DirAccess.remove_absolute(TEST_DIR + "_solo/only.wav")
	DirAccess.remove_absolute(TEST_DIR + "_solo")

# ================================= Pause ==================================

func test_pausing_the_game_pauses_the_music():
	_music()
	await wait_seconds(0.2)
	get_tree().paused = true
	await get_tree().create_timer(0.1, true).timeout
	var player := music.active_player()
	assert_true(player.stream_paused)
	var position := player.get_playback_position()
	await get_tree().create_timer(0.4, true).timeout
	assert_almost_eq(player.get_playback_position(), position, 0.01, "not moving on")
	get_tree().paused = false
	await wait_process_frames(2)
	assert_false(player.stream_paused, "and resumes with it")

func test_a_crossfade_waits_while_paused():
	_music()
	var outgoing := music.active_player()
	_near_the_end(MusicPlayer.CROSSFADE_SECONDS - 0.3)
	await wait_process_frames(2)
	assert_true(music.is_fading(), "sanity")
	get_tree().paused = true
	await get_tree().create_timer(0.1, true).timeout
	var level: float = outgoing.volume_db
	await get_tree().create_timer(MusicPlayer.CROSSFADE_SECONDS + 0.3, true).timeout
	assert_almost_eq(outgoing.volume_db, level, 0.01, "the fade holds where it was")
	assert_gt(outgoing.volume_db, -79.0, "not finished behind the pause")
	assert_true(music.is_fading())
	get_tree().paused = false
	await wait_seconds(MusicPlayer.CROSSFADE_SECONDS + 0.2)
	assert_false(music.is_fading(), "and carries on once unpaused")
	assert_false(outgoing.playing)

# ================================= Volume =================================

func _bus() -> int:
	return AudioServer.get_bus_index(MusicPlayer.BUS)

func test_music_plays_on_its_own_bus():
	_music()
	assert_ne(_bus(), -1)
	for p in music._players:
		assert_eq(p.bus, MusicPlayer.BUS)

func test_setting_the_volume_sets_the_music_bus():
	_music()
	music.set_volume(0.25)
	assert_almost_eq(AudioServer.get_bus_volume_db(_bus()), linear_to_db(0.25), 0.01)
	assert_false(AudioServer.is_bus_mute(_bus()))
	music.set_volume(0.0)
	assert_true(AudioServer.is_bus_mute(_bus()), "all the way down is silent")
	music.set_volume(0.1)

func test_the_toolbar_slider_controls_the_volume_even_while_paused():
	load_main()
	var slider: HSlider = main.hud.volume_slider
	assert_almost_eq(slider.value, main.music.volume, 0.001, "starts where the music does")
	main.hud.set_paused(true)
	slider.value = 0.2
	assert_almost_eq(main.music.volume, 0.2, 0.001)
	assert_almost_eq(AudioServer.get_bus_volume_db(_bus()), linear_to_db(0.2), 0.01)
	slider.value = 0.1

func test_the_slider_doesnt_steal_the_spacebar():
	load_main()
	assert_eq(main.hud.volume_slider.focus_mode, Control.FOCUS_NONE)

func test_the_game_starts_at_ten_percent_volume():
	load_main()
	assert_almost_eq(main.music.volume, 0.1, 0.001)
	assert_almost_eq(main.hud.volume_slider.value, 0.1, 0.001)
	assert_almost_eq(AudioServer.get_bus_volume_db(_bus()), linear_to_db(0.1), 0.01)
