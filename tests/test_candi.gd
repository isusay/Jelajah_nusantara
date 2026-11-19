extends SceneTree
# Tes Tahap 3 (kera, arca, jebakan, pusaka): godot --headless --path . -s tests/test_candi.gd

var level: Node
var failures := 0
var notices: Array[String] = []


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


func total_items(inventory) -> int:
	var total := 0
	for slot in inventory.slots:
		total += slot.quantity
	return total


func enemies_named(display_name: String) -> Array:
	var found := []
	for e in level.enemy_container.get_children():
		if e.display_name == display_name and not e.is_dead():
			found.append(e)
	return found


func world_item_count(item_id: String) -> int:
	var count := 0
	for item in level.item_container.get_children():
		if item.item_id == item_id and not item.is_queued_for_deletion():
			count += 1
	return count


func _run() -> void:
	await wait(0.6)
	var p = level.player_scene.instantiate()
	p.name = "1"
	p.position = level.get_spawn_point(1)
	level.players_container.add_child(p, true)
	p.notice_received.connect(func(text): notices.append(text))
	await wait(0.8)
	var inv = p.get_inventory()
	var g: float = level.environment_root.global_position.y

	for e in level.enemy_container.get_children():
		e.set_physics_process(false)
	check("5 kera pencuri (3 di candi, 2 di hutan)", enemies_named("Kera Pencuri").size() == 5, enemies_named("Kera Pencuri").size())
	check("4 arca penjaga (2 di candi, 2 di gunung)", enemies_named("Arca Penjaga").size() == 4, enemies_named("Arca Penjaga").size())
	check("11 babi hutan", enemies_named("Babi Hutan").size() == 11)
	var grounded := true
	for e in level.enemy_container.get_children():
		if e.global_position.y < g - 0.4:
			grounded = false
	check("semua musuh menapak lantai", grounded)

	# --- Lorong tebing bisa dilewati ---
	p.global_position = Vector3(0, g + 0.1, -46)
	await wait(0.5)
	check("lorong tebing ke candi terbuka", p.is_on_floor() and Vector2(p.global_position.x, p.global_position.z + 46).length() < 0.3, p.global_position)

	# --- Kera mencuri lalu dikalahkan ---
	var monkeys := enemies_named("Kera Pencuri")
	var monkey = monkeys[0]
	var items_before := total_items(inv)
	p.global_position = monkey.global_position + Vector3(4.0, 0.1, 0)
	monkey.set_physics_process(true)
	var fled := false
	for i in range(50):
		await wait(0.1)
		if monkey.state == 7:
			fled = true
			break
	check("kera mencuri satu barang lalu kabur", fled and total_items(inv) == items_before - 1, [monkey.state, items_before, total_items(inv)])
	check("pemain diberi tahu soal pencurian", notices.size() == 1 and notices[0].begins_with("Kera mencuri"), notices)
	var stolen_id: String = monkey._stolen_item_id
	var world_before := world_item_count(stolen_id)
	monkey.server_take_damage(999, p)
	await wait(0.2)
	check("kera dikalahkan: barang curian jatuh", world_item_count(stolen_id) == world_before + 1, stolen_id)

	# --- Kera lolos membawa barang ---
	monkey = monkeys[1]
	monkey.flee_seconds = 1.2
	items_before = total_items(inv)
	p.global_position = monkey.global_position + Vector3(3.0, 0.1, 0)
	monkey.set_physics_process(true)
	for i in range(80):
		await wait(0.1)
		if not is_instance_valid(monkey):
			break
	check("kera yang lolos menghilang bersama barangnya", not is_instance_valid(monkey) and total_items(inv) == items_before - 1, total_items(inv))

	# --- Tas kosong: kera mencuri koin, kembali saat dikalahkan ---
	for slot in inv.slots:
		slot.clear()
	monkey = monkeys[2]
	var coins_before: int = p.get_coins()
	p.global_position = monkey.global_position + Vector3(3.0, 0.1, 0)
	monkey.set_physics_process(true)
	for i in range(50):
		await wait(0.1)
		if monkey.state == 7:
			break
	check("tas kosong: kera mencuri 15 koin", p.get_coins() == coins_before - 15, [coins_before, p.get_coins()])
	monkey.server_take_damage(999, p)
	var back: int = p.get_coins() - coins_before
	check("koin curian kembali ditambah hadiah 3-6", back >= 3 and back <= 6, back)
	await wait(0.3)

	# --- Arca penjaga ---
	var guardian = enemies_named("Arca Penjaga")[0]
	p._server_set_health(100)
	p.global_position = guardian.global_position + Vector3(0, 0.1, 2.2)
	guardian.set_physics_process(true)
	var saw_windup := false
	for i in range(40):
		await wait(0.1)
		if guardian.state == 3:
			saw_windup = true
		if p.health < 100:
			break
	check("arca ancang-ancang lalu menghantam (30 damage)", saw_windup and p.health == 70, p.health)
	var guardian_position: Vector3 = guardian.global_position
	guardian.server_take_damage(20, p)
	await wait(0.3)
	check("arca tidak terdorong saat dipukul", guardian.health == 160 and guardian.global_position.distance_to(guardian_position) < 0.6, guardian.health)
	guardian.set_physics_process(false)

	# Menjauh saat ancang-ancang: hantaman meleset.
	var guardian2 = enemies_named("Arca Penjaga")[1]
	p._server_set_health(100)
	p.global_position = guardian2.global_position + Vector3(0, 0.1, 2.2)
	guardian2.set_physics_process(true)
	for i in range(40):
		await wait(0.05)
		if guardian2.state == 3:
			break
	p.global_position = guardian2.global_position + Vector3(0, 0.1, 9.0)
	for i in range(30):
		await wait(0.05)
		if guardian2.state == 5:
			break
	check("menjauh saat ancang-ancang: hantaman meleset", guardian2.state == 5 and p.health == 100, [guardian2.state, p.health])
	guardian2.set_physics_process(false)

	# --- Jebakan duri ---
	var trap = level.environment_root.get_node("Candi/Traps/Trap1")
	p._server_set_health(100)
	p.global_position = trap.global_position + Vector3(0, 0.1, 0)
	var saw_active := false
	for i in range(36):
		await wait(0.1)
		if trap.phase == 2:
			saw_active = true
	var lost: int = 100 - p.health
	check("jebakan duri melukai 20 per naik", saw_active and (lost == 20 or lost == 40), lost)
	p.global_position = trap.global_position + Vector3(0, 0.1, 6.0)
	var health_after: int = p.health
	await wait(3.6)
	check("di luar jebakan tidak terluka", p.health == health_after, p.health)

	# --- Peti Pusaka ---
	var pusaka_chest = null
	for chest in level.chest_container.get_children():
		if chest.announce_name == "Peti Pusaka":
			pusaka_chest = chest
	check("Peti Pusaka ada dan lebih besar", pusaka_chest != null and absf(pusaka_chest.scale.x - 1.4) < 0.01)
	notices.clear()
	coins_before = p.get_coins()
	p.global_position = pusaka_chest.global_position + Vector3(0, 0.1, 2.0)
	await wait(0.6)
	check("Peti Pusaka dalam jangkauan dari atas altar", p._find_chest_in_reach() == pusaka_chest, p.global_position)
	p.request_open_chest(str(pusaka_chest.name))
	await wait(0.3)
	var gained: int = p.get_coins() - coins_before
	check("Peti Pusaka berisi Keris Pusaka", pusaka_chest.is_open and world_item_count("keris_pusaka") == 1)
	check("Peti Pusaka memberi 60-100 koin", gained >= 60 and gained <= 100, gained)
	check("pembukaan Peti Pusaka diumumkan", notices.size() == 1 and notices[0].ends_with("membuka Peti Pusaka!"), notices)

	# --- Keris Pusaka sebagai senjata ---
	check("Keris Pusaka masuk tas", p.request_add_single_item("keris_pusaka"))
	var keris_slot := -1
	for i in range(inv.slots.size()):
		if inv.slots[i].item_id == "keris_pusaka":
			keris_slot = i
	p.request_equip_item(keris_slot, 0)
	var keris_node = p.get_node("GodotRobot3D/RobotArmature/Skeleton3D/LeftHandAttach/KerisPusaka")
	check("Keris Pusaka terpasang: damage 45 dan terlihat di tangan", p.get_attack_damage() == 45 and keris_node.visible, p.get_attack_damage())

	print("SELESAI, gagal: ", failures)
	quit(1 if failures > 0 else 0)
