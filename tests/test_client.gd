extends SceneTree
# Tes replikasi: jalankan sebagai client headless saat dedicated server sudah hidup.

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


func _run() -> void:
	var save_game = root.get_node("SaveGame")
	if save_game.suffix.is_empty():
		print("FAIL jalankan dengan: -- --save-suffix=_test (supaya simpanan asli tidak tersentuh)")
		quit(1)
		return
	await wait(0.5)
	check("dunia tidak dibuat sebelum sesi mulai", level.enemy_container.get_child_count() == 0 and level.chest_container.get_child_count() == 0)
	level._on_join_pressed("Penguji", "green", "127.0.0.1")
	await wait(2.5)
	check("terhubung sebagai client", level.multiplayer.has_multiplayer_peer() and not level.multiplayer.is_server())
	check("24 musuh tereplikasi", level.enemy_container.get_child_count() == 24, level.enemy_container.get_child_count())
	check("15 peti tereplikasi", level.chest_container.get_child_count() == 15, level.chest_container.get_child_count())

	var p = level._get_local_player()
	check("pemain lokal ada", p != null)
	if p == null:
		quit(1)
		return
	check("HUD terikat ke pemain", level.hud_ui.visible and level.hud_ui._player == p)
	var inv = p.get_inventory()
	check("inventory tersinkron", inv != null and count_item(inv, "sword") == 1 and count_item(inv, "chicken_leg") == 2)
	check("pemain berdiri di pasir", p.is_on_floor(), p.global_position)

	p.request_equip_item.rpc_id(1, 0, 0)
	await wait(0.4)
	check("golok terpasang lewat RPC", inv.equipped_weapon.item_id == "sword", inv.equipped_weapon.item_id)

	# Posisi babi dan peti harus cocok dengan marker (replikasi posisi saat spawn).
	var chest = level.chest_container.get_child(0)
	var marker = level.chest_spawns.get_child(0)
	check("posisi peti cocok dengan marker", chest.global_position.distance_to(marker.global_position) < 0.05, chest.global_position)

	# --- Serang babi lewat jalur animasi yang sama dengan klik kiri ---
	var boar = level.enemy_container.get_child(0)
	p.global_position = boar.global_position + Vector3(0, 0.1, -1.4)
	p._body.global_rotation = Vector3.ZERO
	await wait(0.25)
	p.global_position = boar.global_position + Vector3(0, 0.1, -1.4)
	p._start_attack()
	await wait(0.7)
	check("pukulan client mengurangi darah babi", boar.health == 40, boar.health)

	# --- Diseruduk: darah turun lewat RPC dan HUD ikut berubah ---
	var hit := false
	for i in range(100):
		await wait(0.1)
		if p.health < 100:
			hit = true
			break
	check("diseruduk babi, darah turun", hit and p.health == 85, p.health)
	check("HUD menampilkan darah baru", level.hud_ui._health_label.text == "85 / 100", level.hud_ui._health_label.text)

	p.use_first_food()
	await wait(0.5)
	check("makan lewat RPC memulihkan darah", p.health == 100 and count_item(inv, "chicken_leg") == 1, [p.health, count_item(inv, "chicken_leg")])

	# --- Peti ---
	var items_before: int = level.item_container.get_child_count()
	p.global_position = chest.global_position + chest.global_basis.z * 1.6 + Vector3.UP * 0.1
	await wait(0.4)
	p.request_open_chest.rpc_id(1, str(chest.name))
	await wait(0.8)
	var spawned: int = level.item_container.get_child_count() - items_before
	check("peti terbuka di client", chest.is_open)
	check("3 item peti tereplikasi", spawned == 3, spawned)

	# --- Jual-beli lewat RPC ---
	var merchant = get_nodes_in_group("merchants")[0]
	var coins_start: int = p.get_coins()
	check("koin tersinkron ke client (20 + isi peti)", coins_start >= 30 and coins_start <= 54, coins_start)
	check("HUD menampilkan koin", level.hud_ui._coin_label.text == str(coins_start), level.hud_ui._coin_label.text)
	p.global_position = merchant.global_position + merchant.global_basis.z * 2.2 + Vector3.UP * 0.1
	await wait(0.4)
	level.open_shop(merchant)
	check("toko terbuka di client", level.is_shop_visible())
	p.request_buy_item.rpc_id(1, str(merchant.name), "chicken_leg")
	await wait(0.5)
	check("beli lewat RPC: koin berkurang 10", p.get_coins() == coins_start - 10 and count_item(inv, "chicken_leg") == 2, [p.get_coins(), count_item(inv, "chicken_leg")])
	check("toko menampilkan koin terbaru", level.shop_ui._coins_label.text == "Koin: %d" % p.get_coins(), level.shop_ui._coins_label.text)
	var chicken_slot := -1
	for i in range(inv.slots.size()):
		if inv.slots[i].item_id == "chicken_leg":
			chicken_slot = i
	p.request_sell_item.rpc_id(1, str(merchant.name), chicken_slot, 1)
	await wait(0.5)
	check("jual lewat RPC: koin bertambah 5", p.get_coins() == coins_start - 5 and count_item(inv, "chicken_leg") == 1, p.get_coins())
	level.shop_ui.close_shop()

	# --- Tumbang: biarkan babi menghabisi pemain yang diam ---
	var boar2 = level.enemy_container.get_child(1)
	var downed := false
	for i in range(400):
		if i % 20 == 0 and is_instance_valid(boar2) and not p.is_downed:
			p.global_position = boar2.global_position + Vector3(0, 0.1, 4.0)
		await wait(0.1)
		if p.is_downed:
			downed = true
			break
	check("pemain tumbang di client", downed and p.health == 0, p.health)
	check("HUD menampilkan pesan tumbang", level.hud_ui._downed_label.visible)
	check("badan terbaring", absf(p._body.rotation.x + PI / 2.0) < 0.01, p._body.rotation.x)
	await wait(5.6)
	var spawn_global: Vector3 = level.players_container.to_global(level.get_spawn_point(level.multiplayer.get_unique_id()))
	check("bangkit di client", not p.is_downed and p.health == 100, p.health)
	check("kembali ke titik awal", p.global_position.distance_to(spawn_global) < 1.5, p.global_position)
	check("badan tegak lagi", absf(p._body.rotation.x) < 0.01)

	print("SELESAI, gagal: ", failures)
	quit(1 if failures > 0 else 0)
