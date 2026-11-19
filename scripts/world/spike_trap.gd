class_name SpikeTrap
extends Node3D
## Jebakan duri di lantai candi. Node ini bagian dari scene (ada di semua peer);
## server yang menjalankan siklusnya dan mengirim tiap perubahan lewat RPC.
##
## Siklus: diam -> peringatan (ujung duri muncul) -> aktif (duri naik, melukai).

enum Phase { IDLE, WARNING, ACTIVE }

@export var damage := 20
@export var idle_seconds := 1.8
@export var warning_seconds := 0.7
@export var active_seconds := 0.8
## Geser awal siklus supaya deretan jebakan tidak naik bersamaan.
@export var phase_offset := 0.0
## Setengah ukuran area yang melukai (sumbu X dan Z lokal).
@export var half_extents := Vector2(1.0, 1.0)

var phase: int = Phase.IDLE

var _phase_time := 0.0
var _victims: Dictionary = {}

@onready var _spikes: Node3D = $Spikes


func _ready() -> void:
	_phase_time = -phase_offset
	_apply_visual(true)


func _physics_process(delta: float) -> void:
	if not Network.is_hosting():
		return
	_phase_time += delta
	match phase:
		Phase.IDLE:
			if _phase_time >= idle_seconds:
				_server_set_phase(Phase.WARNING)
		Phase.WARNING:
			if _phase_time >= warning_seconds:
				_victims.clear()
				_server_set_phase(Phase.ACTIVE)
		Phase.ACTIVE:
			_server_hurt_players()
			if _phase_time >= active_seconds:
				_server_set_phase(Phase.IDLE)


func _server_set_phase(new_phase: Phase) -> void:
	_phase_time = 0.0
	sync_phase.rpc(new_phase)


@rpc("authority", "call_local", "reliable")
func sync_phase(new_phase: int) -> void:
	phase = clampi(new_phase, Phase.IDLE, Phase.ACTIVE)
	_apply_visual(false)
	if phase == Phase.ACTIVE:
		AudioManager.play("trap", global_position)


func _server_hurt_players() -> void:
	var container := get_tree().get_first_node_in_group("Players")
	if not container:
		return
	for child in container.get_children():
		var player := child as Character
		if not player or player.is_downed:
			continue
		var player_id := player.get_multiplayer_authority()
		if _victims.has(player_id):
			continue
		var local := to_local(player.global_position)
		if absf(local.x) > half_extents.x or absf(local.z) > half_extents.y or local.y < -0.5 or local.y > 1.2:
			continue
		_victims[player_id] = true
		player.server_take_damage(damage, Vector3.UP * 5.0)


func _apply_visual(instant: bool) -> void:
	if not _spikes:
		return
	var target_height := -0.75
	match phase:
		Phase.WARNING:
			target_height = -0.55
		Phase.ACTIVE:
			target_height = 0.0
	if instant or DisplayServer.get_name() == "headless":
		_spikes.position.y = target_height
		return
	var tween := create_tween()
	tween.tween_property(_spikes, "position:y", target_height, 0.1 if phase == Phase.ACTIVE else 0.25)
