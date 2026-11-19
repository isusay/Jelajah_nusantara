extends SceneTree
# Tes Tahap 2 (koin, pedagang, zona aman): godot --headless --path . -s tests/test_trade.gd

var level: Node
var failures := 0


func _initialize() -> void:
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


func find_slot(inventory, item_id: String) -> int:
	for i in range(inventory.slots.size()):
		if inventory.slots[i].item_id == item_id:
			return i
	return -1


func _run() -> void:
	await wait(0.6)
	var p = level.player_scene.instantiate()
	p.name = "1"
	p.position = level.get_spawn_point(1)
	level.players_container.add_child(p, true)
	await wait(0.8)
	var inv = p.get_inventory()
	check("koin awal 20", p.get_coins() == 20, p.get_coins())

	var merchants := get_nodes_in_group("merchants")
	check("ada satu pedagang", merchants.size() == 1, merchants.size())
	var m = merchants[0]
	var m_name := str(m.name)
	var front: Vector3 = m.global_position + m.global_basis.z * 2.2 + Vector3.UP * 0.1

	# --- Jauh dari pedagang: ditolak ---
	p.request_buy_item(m_name, "chicken_leg")
	check("beli dari jauh ditolak", p.get_coins() == 20 and count_item(inv, "chicken_leg") == 2)
	await wait(0.2)

	p.global_position = front
	await wait(0.3)
	check("pedagang terdeteksi dalam jangkauan", p._find_merchant_in_reach() == m)
	check("pemain tidak tersangkut di lapak", p.global_position.distance_to(front) < 0.6, p.global_position)

	# --- Beli ---
	p.request_buy_item(m_name, "chicken_leg")
	check("beli ayam bakar 10 koin", p.get_coins() == 10 and count_item(inv, "chicken_leg") == 3, [p.get_coins(), count_item(inv, "chicken_leg")])
	await wait(0.2)
	p.request_buy_item(m_name, "axe")
	check("koin kurang: beli kapak ditolak", p.get_coins() == 10 and count_item(inv, "axe") == 0)
	await wait(0.2)
	p.request_buy_item(m_name, "chalice")
	check("item di luar stok ditolak", p.get_coins() == 10 and count_item(inv, "chalice") == 0)
	await wait(0.2)

	# --- Jual ---
	var chicken_slot := find_slot(inv, "chicken_leg")
	p.request_sell_item(m_name, chicken_slot, 2)
	check("jual 2 ayam bakar (+10)", p.get_coins() == 20 and count_item(inv, "chicken_leg") == 1, [p.get_coins(), count_item(inv, "chicken_leg")])
	await wait(0.2)
	p.request_sell_item(m_name, chicken_slot, 50)
	check("jual melebihi stok hanya menjual yang ada", p.get_coins() == 25 and count_item(inv, "chicken_leg") == 0, p.get_coins())
	await wait(0.2)
	p.request_sell_item(m_name, chicken_slot, 1)
	check("jual slot kosong ditolak", p.get_coins() == 25)
	await wait(0.2)
	p.request_sell_item(m_name, find_slot(inv, "sword"), 1)
	check("jual golok (+80)", p.get_coins() == 105 and count_item(inv, "sword") == 0, p.get_coins())
	await wait(0.2)

	# --- Beli barang mahal setelah punya koin ---
	p.server_add_coins(400)
	p.request_buy_item(m_name, "sword_big")
	check("beli pedang besar 240 koin", p.get_coins() == 265 and count_item(inv, "sword_big") == 1, p.get_coins())
	await wait(0.2)

	# --- Tas penuh ---
	var bone = root.get_node("ItemDatabase").get_item("bone")
	for i in range(inv.get_active_slot_count()):
		if inv.get_slot(i).is_empty():
			inv.get_slot(i).item_id = "sword"
			inv.get_slot(i).quantity = 1
	check("tas penuh terdeteksi", not inv.can_add_item(bone))
	p.request_buy_item(m_name, "axe")
	check("tas penuh: beli ditolak dan koin utuh", p.get_coins() == 265 and count_item(inv, "axe") == 0, p.get_coins())
	await wait(0.2)
	for i in range(2, inv.get_active_slot_count()):
		inv.get_slot(i).clear()

	# --- Jendela toko ---
	level.main_menu.hide_menu()  # di tes headless menu utama masih tampil
	level.open_shop(m)
	check("jendela toko terbuka", level.is_shop_visible() and level.is_camera_input_blocked())
	check("daftar beli sesuai stok", level.shop_ui._buy_rows.get_child_count() == m.stock.size(), level.shop_ui._buy_rows.get_child_count())
	var sell_rows_before: int = level.shop_ui._sell_rows.get_child_count()
	p.request_sell_item(m_name, 0, 1)
	await wait(0.2)
	check("daftar jual ikut berubah setelah transaksi", level.shop_ui._sell_rows.get_child_count() == sell_rows_before - 1, [sell_rows_before, level.shop_ui._sell_rows.get_child_count()])
	level._handle_pause_action()
	check("Esc menutup toko", not level.is_shop_visible())

	# --- Koin dari peti dan babi ---
	for e in level.enemy_container.get_children():
		e.set_physics_process(false)
	var coins_before: int = p.get_coins()
	var chest = level.chest_container.get_child(0)
	p.global_position = chest.global_position + chest.global_basis.z * 1.6 + Vector3.UP * 0.1
	await wait(0.6)
	p.request_open_chest(str(chest.name))
	var from_chest: int = p.get_coins() - coins_before
	check("peti memberi 10-25 koin", from_chest >= 10 and from_chest <= 25, from_chest)

	coins_before = p.get_coins()
	var boar = level.enemy_container.get_child(0)
	boar.server_take_damage(999, p)
	var from_boar: int = p.get_coins() - coins_before
	check("babi memberi 4-9 koin", from_boar >= 4 and from_boar <= 9, from_boar)
	await wait(1.8)

	# --- Zona aman ---
	var zone = get_nodes_in_group("safe_zones")[0]
	var radius := float(zone.get_meta("radius"))
	var hunter = level.enemy_container.get_child(0)
	# Babi ditaruh tepat di luar tepi utara desa, pemain 5 m di dalamnya.
	var edge: Vector3 = zone.global_position + Vector3(10.0, 0.0, -1.0).normalized() * radius
	hunter.global_position = edge + Vector3(10.0, 0.0, -1.0).normalized() * 4.0 + Vector3.UP * 0.1
	hunter.home_position = hunter.global_position
	p.global_position = edge - Vector3(10.0, 0.0, -1.0).normalized() * 3.0 + Vector3.UP * 0.1
	hunter.set_physics_process(true)
	var health_before: int = p.health
	var chased := false
	for i in range(40):
		await wait(0.1)
		if hunter.state >= 2 and hunter.state <= 4:
			chased = true
	check("pemain di desa tidak dikejar", not chased and p.health == health_before, [hunter.state, p.health])
	check("HUD menandai zona aman", level.hud_ui._is_in_safe_zone(p.global_position))

	p.global_position = hunter.global_position + Vector3(10.0, 0.0, -1.0).normalized() * 5.0
	chased = false
	for i in range(30):
		await wait(0.1)
		if hunter.state >= 2 and hunter.state <= 4:
			chased = true
			break
	check("di luar desa babi kembali mengejar", chased, hunter.state)

	print("SELESAI, gagal: ", failures)
	quit(1 if failures > 0 else 0)
