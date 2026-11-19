class_name Enemy
extends CharacterBody3D
## Musuh yang sepenuhnya dikendalikan server.
##
## Server menjalankan AI dan fisika; client hanya menerima posisi, rotasi,
## `health`, dan `state` lewat MultiplayerSynchronizer lalu menganimasikan
## tampilannya sendiri di `_process`.
##
## Satu skrip dipakai semua jenis musuh; `behavior` menentukan cara menyerang:
## CHARGE (babi hutan menyeruduk), SLAM (arca menghantam area di sekitarnya),
## STEAL (kera mencuri barang lalu kabur).

signal died(enemy: Enemy)

enum State { IDLE, WANDER, CHASE, WINDUP, CHARGE, RECOVER, DEAD, FLEE }
enum Behavior { CHARGE, SLAM, STEAL }

const DEATH_LINGER_SECONDS := 1.4
const CHARGE_SECONDS := 0.75
const WALL_STUN_SECONDS := 1.8
const TURN_SPEED := 9.0
const EMPTY_HANDED_FLEE_SECONDS := 3.0
const MAX_STOLEN_COINS := 15

@export var display_name := "Babi Hutan"
@export var behavior: Behavior = Behavior.CHARGE
@export var max_health := 60
@export var walk_speed := 2.2
@export var chase_speed := 4.8
## Jarak pemain mulai dikejar.
@export var aggro_radius := 13.0
## Jarak terjauh dari titik asal sebelum musuh menyerah dan pulang.
@export var leash_radius := 30.0
## Jarak ke pemain saat serangan dimulai.
@export var attack_trigger_distance := 6.5
@export var attack_damage := 15
@export var attack_cooldown_seconds := 2.2
## Lama ancang-ancang sebelum serangan (waktu pemain untuk menghindar).
@export var windup_seconds := 0.7
@export var recover_seconds := 1.0
## Seberapa jauh musuh terdorong saat dipukul (0 = tidak bergeming).
@export var stagger_strength := 5.0
## Dipakai pemain untuk menghitung apakah pukulannya kena.
@export var hit_radius := 0.8
## Suara saat mulai ancang-ancang (nama berkas di assets/audio/sfx tanpa akhiran).
@export var windup_sound := "boar_growl"

@export_group("Charge")
@export var charge_speed := 14.0

@export_group("Slam")
@export var slam_radius := 3.0

@export_group("Steal")
@export var flee_speed := 8.0
## Setelah selama ini kabur membawa barang, kera menghilang bersama barangnya.
@export var flee_seconds := 9.0

@export_group("Loot")
@export var loot_item_ids: Array[String] = ["chicken_leg", "bone"]
@export_range(0.0, 1.0, 0.05) var loot_chance := 0.75
## Koin untuk pemain yang memberi pukulan terakhir.
@export var coins_min := 4
@export var coins_max := 9

var health: int = 1:
	set(value):
		var previous := health
		health = value
		if is_node_ready():
			if value < previous:
				_hurt_punch = 1.0
				AudioManager.play("hit", global_position)
			_update_health_bar()

var state: int = State.IDLE:
	set(value):
		var previous := state
		state = value
		_visual_state_time = 0.0
		if is_node_ready():
			_update_health_bar()
			if value != previous:
				_play_state_sound(previous)

var home_position := Vector3.ZERO

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _rng := RandomNumberGenerator.new()
var _state_time := 0.0
var _state_duration := 0.0
var _wander_target := Vector3.ZERO
var _aggro_target: Character = null
var _attack_direction := Vector3.ZERO
var _attack_cooldown := 0.0
var _charge_victims: Dictionary = {}
var _stagger := Vector3.ZERO
var _stolen_item_id := ""
var _stolen_coins := 0

var _visual_state_time := 0.0
var _visual_clock := 0.0
var _hurt_punch := 0.0
var _last_visual_position := Vector3.ZERO

@onready var _visual: Node3D = $Visual
@onready var _health_bar: MeshInstance3D = $HealthBar
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("enemies")
	_rng.randomize()
	_last_visual_position = global_position
	if Network.is_hosting():
		health = max_health
		home_position = global_position
		_enter_state(State.IDLE)
	else:
		set_physics_process(false)
	if DisplayServer.get_name() == "headless":
		set_process(false)
	_update_health_bar()


func is_dead() -> bool:
	return state == State.DEAD


func has_stolen_goods() -> bool:
	return not _stolen_item_id.is_empty() or _stolen_coins > 0


# --- AI (server) ---


func _physics_process(delta: float) -> void:
	if not Network.is_hosting():
		return
	if state == State.DEAD:
		return

	_state_time += delta
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)

	# Desa adalah zona aman: musuh yang terlanjur masuk langsung pulang.
	if state != State.WANDER and state != State.FLEE and is_in_safe_zone(global_position):
		_aggro_target = null
		_wander_target = home_position
		_enter_state(State.WANDER, 12.0)

	match state:
		State.IDLE:
			_tick_idle()
		State.WANDER:
			_tick_wander(delta)
		State.CHASE:
			_tick_chase(delta)
		State.WINDUP:
			_tick_windup(delta)
		State.CHARGE:
			_tick_charge()
		State.RECOVER:
			_tick_recover()
		State.FLEE:
			_tick_flee(delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	velocity.x += _stagger.x
	velocity.z += _stagger.z
	_stagger = _stagger.move_toward(Vector3.ZERO, 30.0 * delta)
	move_and_slide()

	if state == State.CHARGE and is_on_wall():
		# Menabrak batu atau tebing: pusing lebih lama. Hadiah untuk yang pandai menghindar.
		_attack_cooldown = attack_cooldown_seconds
		_enter_state(State.RECOVER, WALL_STUN_SECONDS)


func _enter_state(new_state: State, duration: float = 0.0) -> void:
	state = new_state
	_state_time = 0.0
	_state_duration = duration


func _tick_idle() -> void:
	_stop()
	if _find_target():
		_enter_state(State.CHASE)
	elif _state_time >= _state_duration:
		var offset := Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(2.0, 6.0)
		_wander_target = home_position + Vector3(offset.x, 0.0, offset.y)
		_enter_state(State.WANDER, 5.0)


func _tick_wander(delta: float) -> void:
	if _find_target():
		_enter_state(State.CHASE)
		return
	var to_target := _flat(_wander_target - global_position)
	if to_target.length() < 0.6 or _state_time >= _state_duration or is_on_wall():
		_enter_state(State.IDLE, _rng.randf_range(1.5, 4.0))
		return
	_move_towards(to_target.normalized(), walk_speed, delta)


func _tick_chase(delta: float) -> void:
	var target := _find_target()
	if not target:
		_aggro_target = null
		_wander_target = home_position
		_enter_state(State.WANDER, 12.0)
		return
	var to_target := _flat(target.global_position - global_position)
	var distance := to_target.length()
	if distance <= attack_trigger_distance and _attack_cooldown <= 0.0:
		_stop()
		if behavior == Behavior.STEAL:
			_steal_from(target)
		else:
			_enter_state(State.WINDUP, windup_seconds)
		return
	# Berhenti sedikit di dalam jarak serang, supaya tidak ada celah tempat musuh
	# diam di luar jangkauan serangannya sendiri.
	if distance < minf(1.6, attack_trigger_distance - 0.2):
		_stop()
		_face(to_target, delta)
		return
	_move_towards(to_target.normalized(), chase_speed, delta)


func _tick_windup(delta: float) -> void:
	_stop()
	var target := _find_target()
	if target:
		var to_target := _flat(target.global_position - global_position)
		_face(to_target, delta)
		if not to_target.is_zero_approx():
			_attack_direction = to_target.normalized()
	if _state_time < _state_duration:
		return
	if behavior == Behavior.SLAM:
		_slam()
		_attack_cooldown = attack_cooldown_seconds
		_enter_state(State.RECOVER, recover_seconds)
		return
	if _attack_direction.is_zero_approx():
		_attack_direction = _flat(global_basis.z).normalized()
	_charge_victims.clear()
	rotation.y = atan2(_attack_direction.x, _attack_direction.z)
	_enter_state(State.CHARGE, CHARGE_SECONDS)


func _tick_charge() -> void:
	velocity.x = _attack_direction.x * charge_speed
	velocity.z = _attack_direction.z * charge_speed
	for player in _get_players():
		var player_id := player.get_multiplayer_authority()
		if player.is_downed or _charge_victims.has(player_id) or is_in_safe_zone(player.global_position):
			continue
		var offset := player.global_position - global_position
		if absf(offset.y) > 1.6 or _flat(offset).length() > hit_radius + 0.6:
			continue
		_charge_victims[player_id] = true
		player.server_take_damage(attack_damage, _attack_direction * 11.0 + Vector3.UP * 5.0)
	if _state_time >= _state_duration:
		_attack_cooldown = attack_cooldown_seconds
		_enter_state(State.RECOVER, recover_seconds)


## Hantaman arca: melukai semua pemain di sekitarnya.
func _slam() -> void:
	for player in _get_players():
		if player.is_downed or is_in_safe_zone(player.global_position):
			continue
		var offset := player.global_position - global_position
		var flat_offset := _flat(offset)
		if absf(offset.y) > 2.2 or flat_offset.length() > slam_radius:
			continue
		var push := flat_offset.normalized() if not flat_offset.is_zero_approx() else _attack_direction
		player.server_take_damage(attack_damage, push * 10.0 + Vector3.UP * 5.5)


func _steal_from(target: Character) -> void:
	var stolen := target.server_steal_random_item(MAX_STOLEN_COINS)
	_stolen_item_id = str(stolen.get("item_id", ""))
	_stolen_coins = int(stolen.get("coins", 0))
	_attack_cooldown = attack_cooldown_seconds
	var away := _flat(global_position - target.global_position)
	_attack_direction = away.normalized() if not away.is_zero_approx() else -_flat(global_basis.z).normalized()
	_aggro_target = null
	_enter_state(State.FLEE, flee_seconds if has_stolen_goods() else EMPTY_HANDED_FLEE_SECONDS)


func _tick_flee(delta: float) -> void:
	if _state_time >= _state_duration:
		if has_stolen_goods():
			# Lolos: kera menghilang bersama barang curiannya.
			died.emit(self)
			queue_free()
		else:
			_enter_state(State.IDLE, 1.5)
		return

	# Menjauh dari pemain terdekat; kalau terpojok di dinding, belok menyamping.
	var nearest := _find_nearest_player(40.0)
	if nearest:
		var away := _flat(global_position - nearest.global_position)
		if not away.is_zero_approx():
			_attack_direction = _attack_direction.lerp(away.normalized(), minf(1.0, 2.0 * delta)).normalized()
	if is_on_wall():
		var wall_normal := _flat(get_wall_normal())
		if not wall_normal.is_zero_approx():
			var side := wall_normal.normalized().cross(Vector3.UP)
			if side.dot(_attack_direction) < 0.0:
				side = -side
			_attack_direction = (side + wall_normal.normalized() * 0.4).normalized()
	_move_towards(_attack_direction, flee_speed, delta)


func _tick_recover() -> void:
	_stop()
	if _state_time >= _state_duration:
		_enter_state(State.CHASE)


func _stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


func _move_towards(direction: Vector3, speed: float, delta: float) -> void:
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	_face(direction, delta)


func _face(direction: Vector3, delta: float) -> void:
	if direction.is_zero_approx():
		return
	rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(1.0, TURN_SPEED * delta))


func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


func _get_players() -> Array[Character]:
	var players: Array[Character] = []
	var container := get_tree().get_first_node_in_group("Players")
	if not container:
		return players
	for child in container.get_children():
		var player := child as Character
		if player and not player.is_queued_for_deletion():
			players.append(player)
	return players


func _find_nearest_player(max_distance: float) -> Character:
	var nearest: Character = null
	var nearest_distance := max_distance
	for player in _get_players():
		if player.is_downed or is_in_safe_zone(player.global_position):
			continue
		var distance := _flat(player.global_position - global_position).length()
		if distance <= nearest_distance:
			nearest = player
			nearest_distance = distance
	return nearest


func _find_target() -> Character:
	# Terlalu jauh dari rumah atau masuk desa: lupakan semua pemain.
	if _flat(global_position - home_position).length() > leash_radius or is_in_safe_zone(global_position):
		_aggro_target = null
		return null
	if is_instance_valid(_aggro_target) and not _aggro_target.is_downed:
		var aggro_position := _aggro_target.global_position
		if _flat(aggro_position - home_position).length() <= leash_radius and not is_in_safe_zone(aggro_position):
			return _aggro_target
	_aggro_target = null
	return _find_nearest_player(aggro_radius)


## Zona aman ditandai node di grup "safe_zones" dengan metadata `radius`.
func is_in_safe_zone(world_position: Vector3) -> bool:
	for node in get_tree().get_nodes_in_group("safe_zones"):
		var zone := node as Node3D
		if not zone:
			continue
		var radius := float(zone.get_meta("radius", 20.0))
		if _flat(world_position - zone.global_position).length() <= radius:
			return true
	return false


func server_take_damage(amount: int, attacker: Character = null) -> void:
	if not multiplayer.is_server() or state == State.DEAD or amount <= 0:
		return
	health = maxi(0, health - amount)
	if health <= 0:
		if attacker:
			var reward := _stolen_coins
			if coins_max > 0:
				reward += _rng.randi_range(coins_min, maxi(coins_min, coins_max))
			attacker.server_add_coins(reward)
			_stolen_coins = 0
		_server_die()
		return
	if attacker:
		_stagger = _flat(global_position - attacker.global_position).normalized() * stagger_strength
		if state != State.FLEE:
			_aggro_target = attacker
	if state == State.IDLE or state == State.WANDER:
		_enter_state(State.CHASE)


func _server_die() -> void:
	_enter_state(State.DEAD)
	velocity = Vector3.ZERO
	collision_layer = 0
	_collision_shape.set_deferred("disabled", true)
	_drop_loot()
	died.emit(self)
	get_tree().create_timer(DEATH_LINGER_SECONDS).timeout.connect(queue_free)


func _drop_loot() -> void:
	var level_scene := get_tree().get_current_scene()
	if not level_scene or not level_scene.has_method("server_spawn_world_item"):
		return
	var drop_position := global_position + Vector3.UP * 0.9
	if not _stolen_item_id.is_empty():
		# Barang curian selalu kembali bila kera berhasil dikalahkan.
		level_scene.server_spawn_world_item(_stolen_item_id, drop_position, Vector3.UP * 3.0)
		_stolen_item_id = ""
	if loot_item_ids.is_empty() or _rng.randf() > loot_chance:
		return
	var item_id := loot_item_ids[_rng.randi() % loot_item_ids.size()]
	level_scene.server_spawn_world_item(item_id, drop_position, Vector3.UP * 2.5)


# --- Tampilan (semua peer) ---


func _process(delta: float) -> void:
	_visual_clock += delta
	_visual_state_time += delta
	_hurt_punch = maxf(0.0, _hurt_punch - delta * 5.0)

	var moved := _flat(global_position - _last_visual_position).length()
	_last_visual_position = global_position
	var speed := moved / maxf(delta, 0.0001)

	var target_tilt := 0.0
	var offset := Vector3.ZERO
	var roll := 0.0
	var size := 1.0 + _hurt_punch * 0.18

	match state:
		State.WINDUP:
			if behavior == Behavior.SLAM:
				# Arca mengangkat badan sebelum menghantam.
				var lift := clampf(_visual_state_time / maxf(windup_seconds, 0.01), 0.0, 1.0)
				target_tilt = -0.3 * lift
				offset.y = 0.45 * lift
			else:
				# Ancang-ancang: badan menunduk dan bergetar sebelum menyeruduk.
				target_tilt = 0.28
			offset.x = sin(_visual_clock * 55.0) * 0.045
		State.CHARGE:
			target_tilt = 0.12
			offset.y = absf(sin(_visual_clock * 26.0)) * 0.08
		State.RECOVER:
			if behavior == Behavior.SLAM:
				target_tilt = 0.35 * clampf(1.0 - _visual_state_time * 2.0, 0.0, 1.0)
			else:
				roll = sin(_visual_clock * 9.0) * 0.12
		State.FLEE:
			target_tilt = 0.2
			offset.y = absf(sin(_visual_clock * 22.0)) * 0.16
		State.DEAD:
			roll = minf(_visual_state_time * 5.0, 1.0) * PI * 0.5
			size = clampf((DEATH_LINGER_SECONDS - _visual_state_time) * 3.0, 0.0, 1.0)
		_:
			if speed > 0.3:
				offset.y = absf(sin(_visual_clock * (6.0 + speed * 1.6))) * 0.06

	_visual.rotation.x = lerp_angle(_visual.rotation.x, target_tilt, minf(1.0, delta * 12.0))
	_visual.rotation.z = roll
	_visual.position = offset
	_visual.scale = Vector3.ONE * maxf(size, 0.001)


func _update_health_bar() -> void:
	if not _health_bar:
		return
	var ratio := clampf(float(health) / float(maxi(max_health, 1)), 0.0, 1.0)
	_health_bar.visible = state != State.DEAD and ratio < 1.0
	_health_bar.scale.x = maxf(ratio, 0.001)


func _play_state_sound(previous: int) -> void:
	match state:
		State.WINDUP:
			AudioManager.play(windup_sound, global_position)
		State.RECOVER:
			if behavior == Behavior.SLAM and previous == State.WINDUP:
				AudioManager.play("slam", global_position)
		State.FLEE:
			AudioManager.play("monkey_screech", global_position)
		State.DEAD:
			AudioManager.play("enemy_die", global_position)
