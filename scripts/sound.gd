extends Node
## Autoload "Sound": music and sound effects (made by tools/make_audio.py into assets/audio).
## Sound.play("click") for an effect, Sound.music("peace" / "war") to crossfade the music.
## Volumes come from Settings (master, music, effects) and go to the Music and SFX buses.

const Settings = preload("res://scripts/settings.gd")
const FADE := 2.5           # seconds to crossfade between music tracks
const POOL := 6             # effects that can sound at once

var _streams := {}
var _sfx: Array = []
var _next := 0
var _music: Array = []      # two players, so one can fade out while the other fades in
var _current := -1
var _track := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup()


func _setup() -> void:
	## Buses and players; also called on first use, in case a sound is wanted before _ready.
	if not _sfx.is_empty():
		return
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	apply_volume()


func apply_volume() -> void:
	## Read the three volume settings (0..1) onto the buses.
	_set_bus("Master", float(Settings.get_value("master_volume")))
	_set_bus("Music", float(Settings.get_value("music_volume")))
	_set_bus("SFX", float(Settings.get_value("sfx_volume")))


func _set_bus(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func _stream(sound_name: String, loop: bool = false) -> AudioStream:
	if not _streams.has(sound_name):
		var s = load("res://assets/audio/%s.wav" % sound_name)
		if s is AudioStreamWAV and loop:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		_streams[sound_name] = s
	return _streams[sound_name]


func play(sound_name: String, volume_db: float = 0.0) -> void:
	## A sound effect: click, open, event, war, battle, doom.
	_setup()
	var s := _stream(sound_name)
	if s == null:
		return
	var p: AudioStreamPlayer = _sfx[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.volume_db = volume_db
	if not is_inside_tree():
		return
	p.play()


func music(track: String) -> void:
	## Crossfade to "peace" or "war" (nothing happens if it is already playing).
	_setup()
	if track == _track:
		return
	_track = track
	var s := _stream("music_" + track, true)
	if s == null:
		return
	var old: AudioStreamPlayer = _music[_current] if _current >= 0 else null
	_current = (_current + 1) % 2
	var cur: AudioStreamPlayer = _music[_current]
	cur.stream = s
	cur.volume_db = -40.0
	if not is_inside_tree():
		return   # too early (a script run before the tree starts): the track is set, it just isn't heard
	cur.play()
	var tw := create_tween().set_parallel()
	tw.tween_property(cur, "volume_db", 0.0, FADE)
	if old != null and old.playing:
		tw.tween_property(old, "volume_db", -60.0, FADE)
		tw.chain().tween_callback(old.stop)
