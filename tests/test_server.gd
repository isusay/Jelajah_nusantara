extends SceneTree
# Smoke test logika server: jalankan dengan --headless -s <file ini>.

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
	await wait(0.6)
	check("server aktif", level.multiplayer.has_multiplayer_peer() and level.multiplayer.is_server())
	check("24 musuh", level.enemy_container.get_child_count() == 24, level.enemy_container.get_child_count())
	check("15 peti", level.chest_container.get_child_count() == 15, level.chest_container.get_child_count())

	var p = level.player_scene.instantiate()
	p.name = "1"
	p.position = level.get_spawn_point(1)
	level.players_container.add_child(p, true)
	await wait(1.0)
	check("pemain berdiri di pasir", p.is_on_floor() and absf(p.global_position.y - level.environment_root.global_position.y) < 0.3, p.global_position)

	var inv = p.get_inventory()
	check("bekal awal", count_item(inv, "sword") == 1 and count_item(inv, "chicken_leg") == 2)
	check("damage tangan kosong 10", p.get_attack_damage() == 10)
	p.request_equip_item(0, 0)  # WEAPON
	check("golok terpasang, damage 20", p.get_attack_damage() == 20, inv.equipped_weapon.item_id)

	# Semua babi harus sudah menapak tanah.
	var grounded := true
	for e in level.enemy_container.get_children():
		if not e.is_on_floor():
			grounded = false
	check("babi menapak tanah", grounded)

	# --- Serang babi ---
	for e in level.enemy_container.get_children():
		e.set_physics_process(false)  # diamkan supaya tes tidak diganggu
	var boar = level.enemy_container.get_child(0)
	p.global_position = boar.global_position + Vector3(0, 0, -1.6)
	p._body.global_rotation = Vector3.ZERO  # menghadap +Z, ke arah babi
	await wait(0.1)
	p._server_begin_attack()
	await wait(0.5)
	check("pukulan 1 kena (60 -> 40)", boar.health == 40, boar.health)
	p._server_begin_attack()
	await wait(0.5)
	check("cooldown serangan menahan pukulan kedua", boar.health == 40, boar.health)
	await wait(0.5)
	# Membelakangi babi: tidak boleh kena.
	p._body.global_rotation = Vector3(0, PI, 0)
	p._server_begin_attack()
	await wait(0.5)
	check("membelakangi musuh tidak kena", boar.health == 40, boar.health)
	p._body.global_rotation = Vector3.ZERO
	await wait(0.5)
	p._server_begin_attack()
	await wait(1.0)
	p._server_begin_attack()
	await wait(0.5)
	check("babi mati setelah 3 pukulan", boar.is_dead(), boar.health)
	await wait(1.8)
	check("bangkai babi hilang", not is_instance_valid(boar))

	# --- Darah pemain dan makanan ---
	p.global_position = level.players_container.to_global(level.get_spawn_point(1))
	await wait(0.3)
	p.server_take_damage(30, Vector3(6, 3, 0))
	check("kena 30 damage (100 -> 70)", p.health == 70, p.health)
	p.use_first_food()
	await wait(0.1)
	check("makan ayam bakar (70 -> 100)", p.health == 100 and count_item(inv, "chicken_leg") == 1, [p.health, count_item(inv, "chicken_leg")])
	p.use_first_food()
	await wait(0.6)
	check("darah penuh tidak bisa makan", count_item(inv, "chicken_leg") == 1)

	# --- Tumbang dan bangkit ---
	p.server_take_damage(500)
	check("tumbang saat darah habis", p.is_downed and p.health == 0)
	p.server_take_damage(10)
	p._server_begin_attack()
	await wait(5.4)
	var spawn_global: Vector3 = level.players_container.to_global(level.get_spawn_point(1))
	check("bangkit dengan darah penuh", not p.is_downed and p.health == 100, p.health)
	check("bangkit di titik awal", p.global_position.distance_to(spawn_global) < 1.0, p.global_position)
	p.server_take_damage(10)
	check("kebal sesaat setelah bangkit", p.health == 100, p.health)

	# --- Peti ---
	var chest = level.chest_container.get_child(0)
	var items_before: int = level.item_container.get_child_count()
	p.request_open_chest(str(chest.name))
	check("peti jauh tidak bisa dibuka", not chest.is_open)
	await wait(0.6)
	p.global_position = chest.global_position + chest.global_basis.z * 1.6 + Vector3.UP * 0.1
	await wait(0.2)
	check("peti terdeteksi dalam jangkauan", p._find_chest_in_reach() == chest)
	p.request_open_chest(str(chest.name))
	await wait(0.2)
	var spawned: int = level.item_container.get_child_count() - items_before
	check("peti terbuka dan memunculkan 3 item", chest.is_open and spawned == 3, spawned)
	await wait(2.5)
	var settled := true
	for item in level.item_container.get_children():
		if item.global_position.y < level.environment_root.global_position.y - 0.5:
			settled = false
	check("item peti tidak jatuh menembus tanah", settled)

	# --- AI babi: mengejar dan menyeruduk pemain yang diam ---
	var hunter = level.enemy_container.get_child(0)
	hunter.set_physics_process(true)
	p.global_position = hunter.global_position + Vector3(0, 0.1, 8.0)
	var states := {}
	var start_health: int = p.health
	for i in range(60):
		await wait(0.1)
		if not is_instance_valid(hunter):
			break
		states[hunter.state] = true
		if p.health < start_health:
			break
	check("babi mengejar (CHASE)", states.has(2), states.keys())
	check("babi ancang-ancang lalu menyeruduk", states.has(3) and states.has(4), states.keys())
	check("serudukan melukai pemain", p.health == start_health - 15, p.health)

	print("SELESAI, gagal: ", failures)
	quit(1 if failures > 0 else 0)
