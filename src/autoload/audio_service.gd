extends Node
## Music, SFX and creature cries.
##
## The web client synthesises most SFX with oscillators (`e.kt(freq, dur,
## {w:'square', lp:..., v:...})`) and streams `.ogg` music/cries from the CDN.
## Neither the ogg sets nor the per-move sfx tables shipped in pokebonk-web, so:
##   * cries play the generated template WAV with a deterministic per-species pitch
##   * music plays the generated loop (assets/audio/music/menu_theme.wav)
##   * SFX are synthesised here as 16-bit PCM, mirroring the web's tone recipe
## See data/pb/missing_remote_assets.json for the full gap list.

const SAMPLE_RATE := 22050

var _music := AudioStreamPlayer.new()
var _sfx_pool: Array[AudioStreamPlayer] = []
var _cry_player := AudioStreamPlayer.new()
var _tone_cache := {}
var _cry_stream: AudioStreamWAV = null
var music_gain := 0.5
var sfx_gain := 0.7


func _ready() -> void:
	_music.name = "Music"
	_music.volume_db = linear_to_db(music_gain)
	add_child(_music)
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
	_music.volume_db = linear_to_db(music_gain)


# ------------------------------------------------------------------- music
func play_music(track: String = "menu") -> void:
	var path := ""
	match track:
		"menu":
			path = "res://assets/audio/music/menu_theme.wav"
		"halloween":
			path = "res://assets/music/halloween-menu.ogg"
		_:
			# TODO(asset): boss/level tracks are not available offline.
			path = "res://assets/audio/music/menu_theme.wav"
	if _music.stream != null and _music.playing and str(_music.stream.resource_path) == path:
		return
	if not ResourceLoader.exists(path):
		push_warning("Audio: music track missing %s" % path)
		return
	var stream := load(path) as AudioStream
	_music.stream = stream
	var wav := stream as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 2
	_music.play()


func stop_music() -> void:
	_music.stop()


# ------------------------------------------------------------------- cries
func play_cry(species_id: int, volume: float = 1.0) -> void:
	if _cry_stream == null:
		var path := "res://assets/audio/cries/cry_template.wav"
		if not ResourceLoader.exists(path):
			return
		_cry_stream = load(path)
	# Deterministic pitch per species, so 151 dex ids stay distinguishable.
	_cry_player.stream = _cry_stream
	_cry_player.pitch_scale = clampf(0.65 + float((species_id * 37) % 60) / 60.0 * 1.1, 0.5, 2.0)
	_cry_player.volume_db = linear_to_db(clampf(volume, 0.05, 1.0) * 0.8)
	_cry_player.play()


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
