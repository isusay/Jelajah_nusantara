class_name HudUI
extends Control
## HUD pemain lokal: darah, kilatan saat terluka, hitung mundur saat tumbang,
## dan petunjuk interaksi.

const FLASH_ALPHA := 0.35
const PROMPT_REFRESH_SECONDS := 0.15
const TOAST_SECONDS := 1.8
const NOTICE_SECONDS := 4.5

var _player: Character
var _respawn_at_msec := -1
var _prompt_timer := 0.0
var _toast_time_left := 0.0
var _notice_time_left := 0.0

@onready var _health_bar: ProgressBar = $HealthPanel/Margin/Rows/HealthBar
@onready var _health_label: Label = $HealthPanel/Margin/Rows/Header/HealthValue
@onready var _damage_flash: ColorRect = $DamageFlash
@onready var _downed_label: Label = $DownedLabel
@onready var _prompt_label: Label = $PromptLabel
@onready var _coin_label: Label = $HealthPanel/Margin/Rows/CoinRow/CoinValue
@onready var _coin_toast: Label = $CoinToast
@onready var _zone_label: Label = $ZoneLabel
@onready var _notice_label: Label = $NoticeLabel


func _ready() -> void:
	hide()
	_downed_label.hide()
	_prompt_label.hide()


func bind_player(player: Character) -> void:
	unbind_player()
	_player = player
	_player.health_changed.connect(_on_health_changed)
	_player.downed_changed.connect(_on_downed_changed)
	_player.coins_changed.connect(_on_coins_changed)
	_player.notice_received.connect(show_notice)
	_coin_label.text = str(_player.get_coins())
	_set_health(_player.health, Character.MAX_HEALTH)
	_on_downed_changed(_player.is_downed)
	show()


func unbind_player() -> void:
	if is_instance_valid(_player):
		if _player.health_changed.is_connected(_on_health_changed):
			_player.health_changed.disconnect(_on_health_changed)
		if _player.downed_changed.is_connected(_on_downed_changed):
			_player.downed_changed.disconnect(_on_downed_changed)
		if _player.coins_changed.is_connected(_on_coins_changed):
			_player.coins_changed.disconnect(_on_coins_changed)
		if _player.notice_received.is_connected(show_notice):
			_player.notice_received.disconnect(show_notice)
	_player = null
	_respawn_at_msec = -1
	_damage_flash.color.a = 0.0
	_downed_label.hide()
	_prompt_label.hide()
	_coin_toast.hide()
	_zone_label.hide()
	_notice_label.hide()
	_toast_time_left = 0.0
	_notice_time_left = 0.0
	hide()


func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		if visible:
			unbind_player()
		return

	_damage_flash.color.a = move_toward(_damage_flash.color.a, 0.0, delta * 1.2)

	if _respawn_at_msec >= 0:
		var seconds_left := ceili(maxf(0.0, (_respawn_at_msec - Time.get_ticks_msec()) / 1000.0))
		_downed_label.text = "Kamu tumbang!\nBangkit dalam %d..." % seconds_left

	if _toast_time_left > 0.0:
		_toast_time_left -= delta
		_coin_toast.modulate.a = clampf(_toast_time_left / 0.5, 0.0, 1.0)
		_coin_toast.visible = _toast_time_left > 0.0

	if _notice_time_left > 0.0:
		_notice_time_left -= delta
		_notice_label.modulate.a = clampf(_notice_time_left / 0.6, 0.0, 1.0)
		_notice_label.visible = _notice_time_left > 0.0

	_prompt_timer -= delta
	if _prompt_timer <= 0.0:
		_prompt_timer = PROMPT_REFRESH_SECONDS
		_refresh_prompt()


func _refresh_prompt() -> void:
	var text := ""
	if not _player.is_downed:
		if _player._find_chest_in_reach():
			text = "[E] Buka peti"
		elif _player._has_collectible_item_in_front():
			text = "[E] Ambil"
		elif _player._find_merchant_in_reach():
			text = "[E] Berdagang"
	var level_scene := get_tree().get_current_scene()
	if level_scene and level_scene.has_method("is_shop_visible") and level_scene.is_shop_visible():
		text = ""
	if level_scene and level_scene.has_method("get_zone_at"):
		var zone: String = level_scene.get_zone_at(_player.global_position)
		_zone_label.text = str(level_scene.ZONE_TITLES.get(zone, ""))
		_zone_label.visible = true
		AudioManager.set_zone(zone)
	_prompt_label.text = text
	_prompt_label.visible = not text.is_empty()


func _set_health(current: int, maximum: int) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "%d / %d" % [current, maximum]


func _on_health_changed(current: int, maximum: int, previous: int) -> void:
	_set_health(current, maximum)
	if current < previous:
		_damage_flash.color.a = FLASH_ALPHA


func _on_downed_changed(downed: bool) -> void:
	_downed_label.visible = downed
	_respawn_at_msec = Time.get_ticks_msec() + Character.RESPAWN_DELAY_MSEC if downed else -1


func _on_coins_changed(current: int, previous: int) -> void:
	_coin_label.text = str(current)
	if previous < 0 or current == previous:
		return
	var difference := current - previous
	AudioManager.play("coin")
	_coin_toast.text = ("+%d koin" if difference > 0 else "%d koin") % difference
	_coin_toast.modulate = Color(1, 1, 1, 1) if difference > 0 else Color(1, 0.7, 0.7, 1)
	_coin_toast.show()
	_toast_time_left = TOAST_SECONDS


func _is_in_safe_zone(world_position: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("safe_zones"):
		var zone := node as Node3D
		if not zone:
			continue
		var offset := world_position - zone.global_position
		if Vector2(offset.x, offset.z).length() <= float(zone.get_meta("radius", 20.0)):
			return true
	return false


func show_notice(text: String) -> void:
	# Kabar Peti Pusaka sudah punya suaranya sendiri (lihat Level.show_chat_message).
	if not text.contains("Peti Pusaka"):
		AudioManager.play("notice")
	_notice_label.text = text
	_notice_label.modulate.a = 1.0
	_notice_label.show()
	_notice_time_left = NOTICE_SECONDS
