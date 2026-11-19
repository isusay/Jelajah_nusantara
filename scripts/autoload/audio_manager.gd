extends Node
## Pengelola audio: efek suara, musik, dan ambience per zona.
##
## Efek suara tidak dikirim lewat jaringan. Tiap peer memutarnya sendiri saat
## melihat perubahan yang memang sudah disinkronkan (darah berkurang, peti
## terbuka, state musuh berubah), jadi tidak ada RPC tambahan.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const AMBIENCE_DIR := "res://assets/audio/ambience/"

const SFX_NAMES: Array[String] = [
	"swing",
	"hit",
	"enemy_die",
	"boar_growl",
	"tiger_roar",
	"monkey_screech",
	"stone_grind",
	"slam",
	"player_hurt",
	"player_down",
	"respawn",
	"chest_open",
	"coin",
	"eat",
	"pickup",
	"trap",
	"sizzle",
	"notice",
	"pusaka",
	"ui_click",
]
const MUSIC_NAMES: Array[String] = ["desa", "jelajah", "candi"]
const AMBIENCE_NAMES: Array[String] = ["ombak", "hutan", "gunung"]

## Musik dan ambience untuk tiap zona: [musik, ambience].
const ZONE_AUDIO := {
	"menu": ["desa", "ombak"],
	"desa": ["desa", "ombak"],
	"pantai": ["jelajah", "ombak"],
	"hutan": ["jelajah", "hutan"],
	"candi": ["candi", "hutan"],
	"gunung": ["candi", "gunung"],
}

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const FADE_SECONDS := 0.8
const MUSIC_LEVEL_DB := -9.0
const AMBIENCE_LEVEL_DB := -13.0
const MIN_REPEAT_MSEC := 45

var music_volume := 0.7
var sfx_volume := 0.9

var _enabled := false
var _sfx: Dictionary = {}
var _music: Dictionary = {}
var _ambience: Dictionary = {}
var _last_played_msec: Dictionary = {}
var _zone := ""
var _music_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer
var _music_name := ""
var _ambience_name := ""


func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless"
	if not _enabled:
		return
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_load_settings()
	for sfx_name in SFX_NAMES:
		_sfx[sfx_name] = load(SFX_DIR + sfx_name + ".wav")
	for music_name in MUSIC_NAMES:
		_music[music_name] = _load_loop(MUSIC_DIR + music_name + ".wav")
	for ambience_name in AMBIENCE_NAMES:
		_ambience[ambience_name] = _load_loop(AMBIENCE_DIR + ambience_name + ".wav")
	_music_player = _make_loop_player()
	_ambience_player = _make_loop_player()
	_apply_volumes()


func is_enabled() -> bool:
	return _enabled


## Memutar efek suara. Dengan `world_position`, suara terdengar dari titik itu
## (makin jauh makin pelan); tanpa itu, suara diputar rata untuk pemain lokal.
func play(sfx_name: String, world_position: Variant = null, pitch_variation: float = 0.06) -> void:
	if not _enabled or not _sfx.has(sfx_name):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played_msec.get(sfx_name, -MIN_REPEAT_MSEC)) < MIN_REPEAT_MSEC:
		return
	_last_played_msec[sfx_name] = now
	var pitch := 1.0 + randf_range(-pitch_variation, pitch_variation)
	if world_position is Vector3:
		var player_3d := AudioStreamPlayer3D.new()
		player_3d.stream = _sfx[sfx_name]
		player_3d.bus = SFX_BUS
		player_3d.unit_size = 9.0
		player_3d.max_distance = 60.0
		player_3d.pitch_scale = pitch
		add_child(player_3d)
		player_3d.global_position = world_position
		player_3d.finished.connect(player_3d.queue_free)
		player_3d.play()
	else:
		var player := AudioStreamPlayer.new()
		player.stream = _sfx[sfx_name]
		player.bus = SFX_BUS
		player.pitch_scale = pitch
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()


## Mengganti musik dan ambience sesuai zona ("menu", "desa", "pantai", ...).
func set_zone(zone: String) -> void:
	if zone == _zone or not ZONE_AUDIO.has(zone):
		return
	_zone = zone
	if not _enabled:
		return
	var tracks: Array = ZONE_AUDIO[zone]
	if tracks[0] != _music_name:
		_music_name = tracks[0]
		_crossfade(_music_player, _music[_music_name], MUSIC_LEVEL_DB)
	if tracks[1] != _ambience_name:
		_ambience_name = tracks[1]
		_crossfade(_ambience_player, _ambience[_ambience_name], AMBIENCE_LEVEL_DB)


func get_zone() -> String:
	return _zone


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()


func _crossfade(player: AudioStreamPlayer, stream: AudioStream, level_db: float) -> void:
	var tween := create_tween()
	if player.playing:
		tween.tween_property(player, "volume_db", -50.0, FADE_SECONDS)
	tween.tween_callback(
		func() -> void:
			player.stream = stream
			player.volume_db = -50.0
			player.play()
	)
	tween.tween_property(player, "volume_db", level_db, FADE_SECONDS)


func _make_loop_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = MUSIC_BUS
	player.volume_db = -50.0
	add_child(player)
	return player


func _load_loop(path: String) -> AudioStream:
	var stream := load(path) as AudioStreamWAV
	if stream:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")


func _apply_volumes() -> void:
	_set_bus_volume(MUSIC_BUS, music_volume)
	_set_bus_volume(SFX_BUS, sfx_volume)


func _set_bus_volume(bus_name: StringName, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, value <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))


func _settings_path() -> String:
	return "user://jelajah_settings%s.cfg" % SaveGame.suffix


func _load_settings() -> void:
	var settings := ConfigFile.new()
	if settings.load(_settings_path()) != OK:
		return
	music_volume = clampf(float(settings.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(settings.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)


func _save_settings() -> void:
	var settings := ConfigFile.new()
	settings.set_value("audio", "music", music_volume)
	settings.set_value("audio", "sfx", sfx_volume)
	settings.save(_settings_path())
