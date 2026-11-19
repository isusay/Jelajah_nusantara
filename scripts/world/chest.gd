class_name Chest
extends StaticBody3D
## Peti harta. Server yang membuka dan memunculkan isinya sebagai item dunia;
## `is_open` disinkronkan supaya tutupnya terbuka di semua pemain.

## Bobot kemunculan tiap item (makin besar makin sering).
const LOOT_WEIGHTS := {
	"chicken_leg": 30,
	"bone": 12,
	"chalice": 12,
	"axe": 7,
	"backpack": 5,
	"sword_big": 4,
	"fedora": 4,
	"headphones": 4,
	"pirate_hat": 4,
	"sheriff_hat": 4,
	"sombrero": 4,
	"wizard_hat": 4,
}
const OPEN_ANGLE := -1.9

## Item yang selalu ada di setiap peti.
@export var guaranteed_item_id := "chicken_leg"
## Jumlah item acak tambahan.
@export var loot_rolls := 2
## Koin untuk pemain yang membuka peti.
@export var coins_min := 10
@export var coins_max := 25
## Bila diisi, pembukaan peti ini diumumkan ke semua pemain.
@export var announce_name := ""

var is_open := false:
	set(value):
		if is_open == value:
			return
		is_open = value
		if is_node_ready():
			_animate_lid()
			if is_open:
				AudioManager.play("chest_open", global_position)

var _rng := RandomNumberGenerator.new()

@onready var _lid_pivot: Node3D = $LidPivot


func _ready() -> void:
	add_to_group("chests")
	_rng.randomize()
	_lid_pivot.rotation.x = OPEN_ANGLE if is_open else 0.0


func server_open(opener: Character = null) -> void:
	if not multiplayer.is_server() or is_open:
		return
	is_open = true
	if opener and coins_max > 0:
		opener.server_add_coins(_rng.randi_range(coins_min, maxi(coins_min, coins_max)))
	var level_scene := get_tree().get_current_scene()
	if not level_scene or not level_scene.has_method("server_spawn_world_item"):
		return
	if opener and not announce_name.is_empty() and level_scene.has_method("server_announce"):
		level_scene.server_announce("%s membuka %s!" % [opener.nickname.text, announce_name])
	var item_ids: Array[String] = []
	if not guaranteed_item_id.is_empty():
		item_ids.append(guaranteed_item_id)
	for i in range(loot_rolls):
		item_ids.append(_roll_item())
	for item_id in item_ids:
		var side := _rng.randf_range(-0.35, 0.35)
		var spawn_position := global_position + Vector3.UP * 1.1 + global_basis.x * side
		var impulse := Vector3.UP * 3.0 + global_basis.z * _rng.randf_range(1.0, 2.2) + global_basis.x * side * 3.0
		level_scene.server_spawn_world_item(item_id, spawn_position, impulse)


func _roll_item() -> String:
	var total := 0
	for item_id in LOOT_WEIGHTS:
		total += int(LOOT_WEIGHTS[item_id])
	var pick := _rng.randi_range(1, total)
	for item_id in LOOT_WEIGHTS:
		pick -= int(LOOT_WEIGHTS[item_id])
		if pick <= 0:
			return str(item_id)
	return guaranteed_item_id


func _animate_lid() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_lid_pivot, "rotation:x", OPEN_ANGLE if is_open else 0.0, 0.45)


## Menerapkan pengaturan dari metadata Marker3D tempat peti ini dimunculkan.
func configure_from_marker(marker: Node) -> void:
	guaranteed_item_id = str(marker.get_meta("guaranteed_item", guaranteed_item_id))
	loot_rolls = int(marker.get_meta("loot_rolls", loot_rolls))
	coins_min = int(marker.get_meta("coins_min", coins_min))
	coins_max = int(marker.get_meta("coins_max", coins_max))
	announce_name = str(marker.get_meta("announce_name", announce_name))
	scale = Vector3.ONE * float(marker.get_meta("chest_scale", 1.0))
