class_name LavaPool
extends Node3D
## Kolam lahar: melukai pemain yang berdiri di atasnya berulang kali.
## Node ini bagian dari scene dan tidak punya state, jadi tidak perlu sinkron;
## hanya server yang menghitung lukanya.

@export var damage := 12
@export var interval_seconds := 0.6
## Setengah ukuran kolam pada sumbu X dan Z lokal.
@export var half_extents := Vector2(3.0, 3.0)

var _last_hit_msec: Dictionary = {}


func _physics_process(_delta: float) -> void:
	if not Network.is_hosting():
		return
	var container := get_tree().get_first_node_in_group("Players")
	if not container:
		return
	var now := Time.get_ticks_msec()
	for child in container.get_children():
		var player := child as Character
		if not player or player.is_downed:
			continue
		var local := to_local(player.global_position)
		if absf(local.x) > half_extents.x or absf(local.z) > half_extents.y or local.y < -0.6 or local.y > 0.5:
			continue
		var player_id := player.get_multiplayer_authority()
		if now - int(_last_hit_msec.get(player_id, -100000)) < int(interval_seconds * 1000.0):
			continue
		_last_hit_msec[player_id] = now
		player.server_take_damage(damage, Vector3.UP * 4.5)
