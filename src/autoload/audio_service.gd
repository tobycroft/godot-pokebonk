extends Node
## Music, SFX and creature cries.
##
## The web client streams `.ogg` music and cries from the CDN and synthesises
## most SFX with oscillators (`e.kt(freq, dur, {w:'square', lp:..., v:...})`).
## The music and cry sets shipped here (assets/music, assets/cries), so:
##   * cries stream `cries/<species>.ogg`, with the generated template WAV as a
##     logged fallback for the species that have no file
##   * music maps 1:1 onto the web's `Kc` track table (menu / halloween-menu /
##     ingame1-4 / boss), including its loop starts and 0.8s / 0.6s fades
##   * SFX are synthesised here as 16-bit PCM, mirroring the web's tone recipe
## See data/pb/missing_remote_assets.json for the remaining gap list.

const SAMPLE_RATE := 22050

const MUSIC_DIR := "res://assets/music/"
const CRY_DIR := "res://assets/cries/"
const CRY_TEMPLATE := "res://assets/audio/cries/cry_template.wav"

## Web `Kc` (bundle offset ~76691): loop start in seconds for each track.
const MUSIC_LOOP := {
	"menu": 70.17733333333334,
	"halloween-menu": 56.342666666666666,
	"ingame1": 79.93333333333334,
	"ingame2": 48.384,
	"ingame3": 47.844,
	"ingame4": 65.428,
	"boss": 8.959333333333333,
}
## Web `Jc` (same table): one of these is picked per run.
const RUN_TRACKS := ["ingame1", "ingame2", "ingame3", "ingame4"]
## Web event `halloween26` (assets/news chunk) carries `music: "halloween-menu"`;
## `oU()` selects it while the event window is open and `menu` otherwise.
const HALLOWEEN_MUSIC_START := "2026-10-21T16:30:00"
const HALLOWEEN_MUSIC_END := "2026-11-04T17:30:00"

const MUSIC_FADE_IN := 0.8
const MUSIC_FADE_OUT := 0.6
const SILENT_DB := -60.0

var _music_players: Array[AudioStreamPlayer] = []
var _music_slot := 0
var _music_track := ""
var _music_tween: Tween = null
var _run_track := ""
var _sfx_pool: Array[AudioStreamPlayer] = []
var _cry_player := AudioStreamPlayer.new()
var _tone_cache := {}
var _cry_cache := {}
var _cry_missing := {}
var _cry_template: AudioStreamWAV = null
var music_gain := 0.5
var sfx_gain := 0.7


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.name = "Music%d" % i
		p.volume_db = SILENT_DB
		add_child(p)
		_music_players.append(p)
	_cry_player.name = "Cries"
	add_child(_cry_player)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		add_child(p)
		_sfx_pool.append(p)


func apply_profile_settings(settings: Dictionary) -> void:
	music_gain = clampf(float(settings.get("music", music_gain)), 0.0, 1.0)
	sfx_gain = clampf(float(settings.get("sfx", sfx_gain)), 0.0, 1.0)
	var playing := _current_music()
	if playing != null and playing.playing:
		playing.volume_db = _music_db()


# ------------------------------------------------------------------- music
## `track` accepts the web names: menu, halloween-menu, ingame1..4, boss.
## `ingame` resolves to the track picked for the current run.
func play_music(track: String = "menu") -> void:
	var resolved := _resolve_track(track)
	if resolved.is_empty():
		return
	var current := _current_music()
	if resolved == _music_track and current != null and current.playing:
		return
	var path := MUSIC_DIR + resolved + ".ogg"
	if not ResourceLoader.exists(path):
		push_warning("Audio: music track missing %s" % path)
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	_apply_loop(resolved, stream)
	_start_track(resolved, stream)


## Web `playTrack(this.musicFor())`: pick a random ingame track once per run.
func start_run_music() -> void:
	_run_track = RUN_TRACKS[randi() % RUN_TRACKS.size()]
	play_music(_run_track)


## Web `musicFor()`: boss when a boss (or Mewtwo) is alive, otherwise the run track.
func play_run_music(boss_alive: bool = false) -> void:
	if _run_track.is_empty():
		_run_track = RUN_TRACKS[randi() % RUN_TRACKS.size()]
	play_music("boss" if boss_alive else _run_track)


func current_music() -> String:
	return _music_track


func current_run_track() -> String:
	return _run_track


func stop_music() -> void:
	_music_track = ""
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	var fade := create_tween().set_parallel(true)
	var fading := false
	for p in _music_players:
		if p.playing:
			fade.tween_property(p, "volume_db", SILENT_DB, MUSIC_FADE_OUT)
			fading = true
	if fading:
		fade.chain().tween_callback(_stop_all_music)
	_music_tween = fade


func _stop_all_music() -> void:
	for p in _music_players:
		p.stop()


func _resolve_track(track: String) -> String:
	match track:
		"menu":
			return "halloween-menu" if _halloween_music_active() else "menu"
		"ingame", "run":
			if _run_track.is_empty():
				_run_track = RUN_TRACKS[randi() % RUN_TRACKS.size()]
			return _run_track
	if MUSIC_LOOP.has(track):
		return track
	return ""


func _halloween_music_active() -> bool:
	var now := Time.get_unix_time_from_system()
	var start := Time.get_unix_time_from_datetime_string(HALLOWEEN_MUSIC_START)
	var end := Time.get_unix_time_from_datetime_string(HALLOWEEN_MUSIC_END)
	return now >= start and now <= end


func _current_music() -> AudioStreamPlayer:
	return _music_players[_music_slot] if not _music_players.is_empty() else null


func _music_db() -> float:
	return linear_to_db(music_gain) if music_gain > 0.0 else SILENT_DB


## Web `Kc[name].loop` -> the ogg stream's loop start. OggVorbis has no loop-end
## property, so the stream loops to its natural end like the web build does.
func _apply_loop(track: String, stream: AudioStream) -> void:
	var ogg := stream as AudioStreamOggVorbis
	if ogg == null:
		return
	ogg.loop = true
	ogg.loop_offset = float(MUSIC_LOOP.get(track, 0.0))


func _start_track(track: String, stream: AudioStream) -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	var old_player := _current_music()
	var next_slot := 1 - _music_slot
	var new_player := _music_players[next_slot]
	if new_player.playing:
		new_player.stop()
	new_player.stream = stream
	new_player.volume_db = SILENT_DB
	new_player.play()
	_music_slot = next_slot
	_music_track = track
	var fade := create_tween().set_parallel(true)
	if old_player != null and old_player.playing:
		fade.tween_property(old_player, "volume_db", SILENT_DB, MUSIC_FADE_OUT)
	fade.tween_property(new_player, "volume_db", _music_db(), MUSIC_FADE_IN)
	if old_player != null and old_player.playing:
		fade.chain().tween_callback(old_player.stop)
	_music_tween = fade


# ------------------------------------------------------------------- cries
## Web `cry(species, volume)` -> `cries/<species>.ogg`; missing files fall back
## to the generated template with a deterministic per-species pitch.
func play_cry(species_id: int, volume: float = 1.0) -> void:
	var stream := _cry_stream_for(species_id)
	if stream != null:
		_cry_player.stream = stream
		_cry_player.pitch_scale = 1.0
		_cry_player.volume_db = linear_to_db(clampf(volume, 0.05, 1.0))
		_cry_player.play()
		return
	if _cry_template == null:
		if not ResourceLoader.exists(CRY_TEMPLATE):
			return
		_cry_template = load(CRY_TEMPLATE)
	if _cry_template == null:
		return
	# Deterministic pitch per species, so the fallback stays distinguishable.
	_cry_player.stream = _cry_template
	_cry_player.pitch_scale = clampf(0.65 + float((species_id * 37) % 60) / 60.0 * 1.1, 0.5, 2.0)
	_cry_player.volume_db = linear_to_db(clampf(volume, 0.05, 1.0) * 0.8)
	_cry_player.play()


func _cry_stream_for(species_id: int) -> AudioStream:
	if _cry_cache.has(species_id):
		return _cry_cache[species_id]
	var ogg_path := "%s%d.ogg" % [CRY_DIR, species_id]
	var wav_path := "%s%d.wav" % [CRY_DIR, species_id]
	var stream: AudioStream = null
	# Species 25 ships as .wav; every other cry is .ogg. Checking the source
	# first avoids Godot's stale `<id>.ogg.import` stub for that one file.
	if FileAccess.file_exists(wav_path):
		stream = load(wav_path)
	elif ResourceLoader.exists(ogg_path):
		stream = load(ogg_path)
	if stream == null:
		_cry_missing[species_id] = true
	_cry_cache[species_id] = stream
	return stream


## Coverage of the shipped cry set, mirroring the web's per-id `cries/<id>.ogg`.
func cry_coverage() -> Dictionary:
	var missing := []
	for id in range(1, 1026):
		if not FileAccess.file_exists("%s%d.ogg" % [CRY_DIR, id]) \
				and not FileAccess.file_exists("%s%d.wav" % [CRY_DIR, id]):
			missing.append(id)
	return {"total": 1025, "available": 1025 - missing.size(), "missing": missing,
		"fallback_used": _cry_missing.size()}


# ------------------------------------------------------------------- sfx
## Synthesise one tone the way the web client does, then cache it.
## wave: "sine" | "square" | "saw" | "noise"; slide multiplies the frequency.
func tone(freq: float, duration: float, wave: String = "square", gain: float = 0.25,
		slide: float = 1.0) -> AudioStreamWAV:
	var key := "%0.1f_%0.3f_%s_%0.2f_%0.2f" % [freq, duration, wave, gain, slide]
	if _tone_cache.has(key):
		return _tone_cache[key]
	var frames := maxi(16, int(SAMPLE_RATE * duration))
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(frames)
		var f := freq * (1.0 + (slide - 1.0) * t)
		var phase := TAU * f * float(i) / float(SAMPLE_RATE)
		var raw := 0.0
		match wave:
			"square":
				raw = 1.0 if sin(phase) >= 0.0 else -1.0
			"saw":
				raw = 2.0 * (phase / TAU - floor(phase / TAU)) - 1.0
			"noise":
				raw = float((randi() % 2000) - 1000) / 1000.0
			_:
				raw = sin(phase)
		var env := clampf(1.0 - t, 0.0, 1.0) * minf(1.0, t * 40.0)
		var sample := int(clampf(raw * env * gain, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, sample)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	_tone_cache[key] = stream
	return stream


## Named cues used by the arena; the recipes mirror the web's kt()/Ec() calls.
func sfx(cue: String, pitch: float = 1.0) -> void:
	var stream: AudioStreamWAV = null
	match cue:
		"hit":
			stream = tone(220.0, 0.07, "square", 0.22, 0.7)
		"crit":
			stream = tone(660.0, 0.12, "saw", 0.26, 1.6)
		"xp":
			stream = tone(880.0, 0.06, "sine", 0.2, 1.25)
		"level":
			stream = tone(523.0, 0.35, "square", 0.24, 2.0)
		"deny":
			stream = tone(160.0, 0.12, "square", 0.2, 0.6)
		"boss":
			stream = tone(110.0, 0.6, "saw", 0.28, 0.8)
		"fusion":
			stream = tone(990.0, 0.25, "square", 0.22, 1.8)
		"ui":
			stream = tone(440.0, 0.04, "sine", 0.12, 1.0)
		_:
			stream = tone(330.0, 0.05, "sine", 0.15, 1.0)
	_play(stream, pitch)


func _play(stream: AudioStream, pitch: float) -> void:
	if stream == null:
		return
	for p in _sfx_pool:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = clampf(pitch, 0.25, 4.0)
			p.volume_db = linear_to_db(sfx_gain)
			p.play()
			return
	# All busy: steal the first slot.
	_sfx_pool[0].stream = stream
	_sfx_pool[0].pitch_scale = clampf(pitch, 0.25, 4.0)
	_sfx_pool[0].volume_db = linear_to_db(sfx_gain)
	_sfx_pool[0].play()
