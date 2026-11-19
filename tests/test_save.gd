extends SceneTree
# Tes simpan progres. WAJIB memakai berkas simpanan terpisah:
#   godot --headless --path . -s tests/test_save.gd -- --save-suffix=_test

const TOKEN := "0123456789abcdef0123456789abcdef"

var level: Node
var save_game: Node
var network: Node
var failures := 0


func _initialize() -> void:
	save_game = root.get_node("SaveGame")
	network = root.get_node("Network")
	if save_game.suffix.is_empty():
		print("FAIL jalankan dengan: -- --save-suffix=_test (supaya simpanan asli tidak tersentuh)")
		quit(1)
		return
	save_game.delete_save()
	level = load("res://scenes/level/level.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	_run()


func check(label: String, ok: bool, detail: Variant = "") -> void:
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label + ("  " + str(detail) if str(detail) != "" else ""))


func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func count_item(inventory, item_id: String) -> int:
	var total := 0
	for slot in inventory.slots:
		if slot.item_id == item_id:
			total += slot.quantity
	return total


func spawn_player(peer_id: int):
	var p = level.player_scene.instantiate()
	p.name = str(peer_id)
	p.position = level.get_spawn_point(peer_id)
	level.players_container.add_child(p, true)
	level._server_restore_player(p, peer_id)
	return p


func _run() -> void:
	await wait(0.6)
	check("berkas simpanan tes terpisah dari yang asli", save_game.get_save_path() == "user://jelajah_save_test.json", save_game.get_save_path())

	# --- Token ---
	var local_token: String = save_game.get_local_token()
	check("token lokal sah dan tetap sama", save_game.is_valid_token(local_token) and save_game.get_local_token() == local_token)
	network.register_player_token(5, "bukan-token")
	check("token tidak sah diabaikan", network.get_player_token(5) == "")
	network.register_player_token(1, TOKEN)
	network.register_player_token(6, TOKEN)
	check("token yang sedang dipakai pemain lain diabaikan", network.get_player_token(1) == TOKEN and network.get_player_token(6) == "")

	# --- Pemain baru: bekal awal ---
	var p = spawn_player(1)
	await wait(0.5)
	var inv = p.get_inventory()
	check("pemain baru mendapat bekal awal", p.get_coins() == 20 and count_item(inv, "sword") == 1 and count_item(inv, "chicken_leg") == 2)

	# --- Ubah progres lalu simpan ---
	p.server_add_coins(130)
	p.request_equip_item(0, 0)
	p.request_add_single_item("keris_pusaka")
	p.request_add_single_item("chalice")
	p.request_add_single_item("chalice")
	level.server_save_all()
	check("berkas simpanan ditulis", FileAccess.file_exists(save_game.get_save_path()))
	var raw_text := FileAccess.get_file_as_string(save_game.get_save_path())
	check("berkas simpanan memuat token dan nama", raw_text.contains(TOKEN) and raw_text.contains("\"nick\""))

	# --- Sesi baru: muat dari disk ---
	level.players_container.remove_child(p)
	p.free()
	save_game.reload()
	p = spawn_player(1)
	await wait(0.5)
	inv = p.get_inventory()
	check("koin dipulihkan (150)", p.get_coins() == 150, p.get_coins())
	check("isi tas dipulihkan", count_item(inv, "keris_pusaka") == 1 and count_item(inv, "chalice") == 2 and count_item(inv, "chicken_leg") == 2)
	check("senjata terpasang dipulihkan", inv.equipped_weapon.item_id == "sword" and p.get_attack_damage() == 20, inv.equipped_weapon.item_id)
	var sword_node = p.get_node("GodotRobot3D/RobotArmature/Skeleton3D/LeftHandAttach/Sword")
	check("senjata yang dipulihkan terlihat di tangan", sword_node.visible)

	# --- Pemain tanpa token tidak disimpan dan tidak memuat ---
	var guest = spawn_player(7)
	await wait(0.3)
	check("pemain tanpa token mulai dari bekal awal", guest.get_coins() == 20)
	guest.server_add_coins(999)
	level.server_save_all()
	check("pemain tanpa token tidak ikut disimpan", not FileAccess.get_file_as_string(save_game.get_save_path()).contains("1019"))

	# --- Berkas yang diubah tangan dibersihkan saat dimuat ---
	var tampered := {
		"version": 1,
		"players": {
			TOKEN: {
				"nick": "Curang",
				"inventory": {
					"coins": 99999999999.0,
					"slots": [
						{"item_id": "item_palsu", "quantity": 5.0},
						{"item_id": "sword", "quantity": 500.0},
						{"item_id": "chicken_leg", "quantity": 5000.0},
						"bukan kamus"
					],
					"equipped_weapon": {"item_id": "chalice", "quantity": 1.0},
					"equipped_hat": 42
				}
			}
		}
	}
	var file := FileAccess.open(save_game.get_save_path(), FileAccess.WRITE)
	file.store_string(JSON.stringify(tampered))
	file.close()
	level.players_container.remove_child(p)
	p.free()
	save_game.reload()
	p = spawn_player(1)
	await wait(0.5)
	inv = p.get_inventory()
	check("koin berlebih dibatasi", p.get_coins() == 999999, p.get_coins())
	check("item palsu dibuang", count_item(inv, "item_palsu") == 0 and inv.get_slot(0).is_empty())
	check("jumlah berlebih dibatasi tumpukan maksimum", count_item(inv, "sword") == 1 and count_item(inv, "chicken_leg") == 99, [count_item(inv, "sword"), count_item(inv, "chicken_leg")])

	# --- Berkas rusak total tidak membuat game gagal ---
	file = FileAccess.open(save_game.get_save_path(), FileAccess.WRITE)
	file.store_string("{ ini bukan json")
	file.close()
	save_game.reload()
	check("berkas rusak diabaikan", not save_game.has_player(TOKEN))

	save_game.delete_save()
	print("SELESAI, gagal: ", failures)
	quit(1 if failures > 0 else 0)
