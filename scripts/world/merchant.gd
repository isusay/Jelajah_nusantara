class_name Merchant
extends StaticBody3D
## Pedagang. Node ini bagian dari scene (sama di semua peer), jadi tidak perlu
## disinkronkan; server cukup memvalidasi nama, jarak, dan harga.

@export var display_name := "Pedagang"
## Item yang dijual pedagang ini.
@export var stock: Array[String] = [
	"chicken_leg", "pisang", "backpack", "axe", "sword_big", "caping", "pirate_hat"
]
## Harga beli = nilai item x pengali ini.
@export var buy_multiplier := 2.0
## Harga jual pemain = nilai item x pengali ini.
@export var sell_multiplier := 1.0
## Tekstur warna untuk model robot pedagang.
@export var skin_texture: Texture2D


func _ready() -> void:
	add_to_group("merchants")
	if skin_texture:
		var skin_material := StandardMaterial3D.new()
		skin_material.albedo_texture = skin_texture
		for mesh_instance in find_children("*", "MeshInstance3D", true, false):
			if mesh_instance.get_parent() is Skeleton3D:
				(mesh_instance as MeshInstance3D).material_override = skin_material
	var animation_player := find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player and animation_player.has_animation(&"Idle"):
		animation_player.play(&"Idle")


func sells(item_id: String) -> bool:
	return stock.has(item_id)


func get_buy_price(item: Item) -> int:
	return maxi(1, ceili(item.value * buy_multiplier))


func get_sell_price(item: Item) -> int:
	return maxi(0, floori(item.value * sell_multiplier))
