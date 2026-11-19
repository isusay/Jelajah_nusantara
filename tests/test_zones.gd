extends SceneTree
# Tes Tahap 4 (Hutan, Gunung, item baru, audio):
#   godot --headless --path . -s tests/test_zones.gd -- --save-suffix=_test

var level: Node
var failures := 0
var g := 0.0


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


func find_slot(inventory, item_id: String) -> int:
	for i in range(inventory.slots.size()):
		if inventory.slots[i].item_id == item_id:
			return i
	return -1


func find_chest(announce_name: String):
	for chest in level.chest_container.get_children():
		if chest.announce_name == announce_name:
			return chest
	return null


## Titik pertama di sepanjang rute yang terhalang benda padat, atau null bila rute bersih.
## Tiap titik rute: Vector3(x, tinggi lantai relatif, z).
func first_blocked_point(route: Array) -> Variant:
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 2
	for i in range(route.size() - 1):
		var a: Vector3 = route[i]
		var b: Vector3 = route[i + 1]
		var steps := maxi(1, int(a.distance_to(b) / 1.5))
		for s in range(steps + 1):
			var point := a.lerp(b, float(s) / steps)
			query.transform = Transform3D(Basis.IDENTITY, Vector3(point.x, g + point.y + 1.05, point.z))
			if not space.intersect_shape(query, 1).is_empty():
				return point
	return null


func _run() -> void:
	await wait(0.6)
	g = level.environment_root.global_position.y
	var p = level.player_scene.instantiate()
	p.name = "1"
	p.position = level.get_spawn_point(1)
	level.players_container.add_child(p, true)
	await wait(0.8)
	var inv = p.get_inventory()
	for e in level.enemy_container.get_children():
		e.set_physics_process(false)

	# --- Isi dunia ---
	check("3 harimau dan 1 raksasa api", enemies_named("Harimau").size() == 3 and enemies_named("Raksasa Api").size() == 1)
	check("8 pisang tergeletak di hutan", world_item_count("pisang") == 8, world_item_count("pisang"))
	var giant = enemies_named("Raksasa Api")[0]
	check("raksasa berdiri di puncak (teras 6 m)", absf(giant.global_position.y - (g + 6.0)) < 0.4, giant.global_position.y - g)
	var giant_slot_ok := false
	for slot in level._enemy_slots:
		if slot["type"] == "giant" and is_equal_approx(float(slot["respawn_seconds"]), 300.0):
			giant_slot_ok = true
	check("raksasa baru muncul lagi setelah 300 detik", giant_slot_ok)

	# --- Rute tidak terhalang pohon, batu, atau dinding ---
	var hutan_routes := {
		"pantai ke hutan": [Vector3(-52, 0, 0), Vector3(-88, 0, 0)],
		"hutan ke gerbang gunung": [Vector3(-88, 0, 0), Vector3(-98, 0, -20), Vector3(-107, 0, -38), Vector3(-107, 0, -50)],
		"hutan ke peti barat": [Vector3(-88, 0, 0), Vector3(-112, 0, 4), Vector3(-128, 0, -14), Vector3(-139, 0, -20)],
		"hutan ke sarang harimau": [Vector3(-112, 0, 4), Vector3(-118, 0, 24), Vector3(-132, 0, 30), Vector3(-137, 0, 33.5)],
		"hutan ke peti selatan": [Vector3(-88, 0, 0), Vector3(-80, 0, 18), Vector3(-78, 0, 31.5)],
		"pantai ke candi": [Vector3(0, 0, -12), Vector3(0, 0, -60)],
	}
	for route_name in hutan_routes:
		var blocked: Variant = first_blocked_point(hutan_routes[route_name])
		check("rute bersih: " + route_name, blocked == null, blocked)
	var gunung_route := [
		Vector3(-107, 0, -50), Vector3(-107, 0, -63.5), Vector3(-107, 3.3, -70.6), Vector3(-107, 3, -75),
		Vector3(-125.5, 3, -77), Vector3(-125.5, 3, -91), Vector3(-85, 3, -91), Vector3(-85, 3, -91.6),
		Vector3(-85, 6.3, -98.6), Vector3(-85, 6, -102), Vector3(-107, 6, -108), Vector3(-107, 6, -118),
	]
	var blocked_gunung: Variant = first_blocked_point(gunung_route)
	check("rute bersih: kaki gunung ke puncak lewat jembatan", blocked_gunung == null, blocked_gunung)

	# Tanjakan benar-benar bisa dipijak.
	p.global_position = Vector3(-107, g + 2.2, -67)
	await wait(0.6)
	check("tanjakan pertama bisa dipijak", p.is_on_floor() and absf(p.global_position.y - (g + 1.5)) < 0.35, p.global_position.y - g)
	p.global_position = Vector3(-85, g + 5.2, -95)
	await wait(0.6)
	check("tanjakan kedua bisa dipijak", p.is_on_floor() and absf(p.global_position.y - (g + 4.5)) < 0.35, p.global_position.y - g)

	# --- Nama zona ---
	var zones := {
		"desa": Vector3(0, g, 10), "pantai": Vector3(30, g, -20), "hutan": Vector3(-100, g, 5),
		"candi": Vector3(0, g, -70), "gunung": Vector3(-100, g, -80),
	}
	var zones_ok := true
	for zone_name in zones:
		if level.get_zone_at(zones[zone_name]) != zone_name:
			zones_ok = false
			print("  zona salah: ", zone_name, " -> ", level.get_zone_at(zones[zone_name]))
	check("nama zona dikenali di kelima wilayah", zones_ok)

	# --- Lahar ---
	p._server_set_health(100)
	p.global_position = Vector3(-95, g + 3.1, -84)
	await wait(0.35)
	check("lahar melukai 12", p.health == 88, p.health)
	await wait(1.3)
	check("lahar terus melukai selama diinjak", p.health <= 64, p.health)
	p._server_set_health(100)
	p.global_position = Vector3(-125.5, g + 3.2, -84)
	await wait(1.5)
	check("jembatan batu aman dari lahar", p.health == 100, p.health)

	# --- Harimau ---
	var tiger = enemies_named("Harimau")[0]
	p.global_position = tiger.global_position + Vector3(0, 0.1, 6.0)
	tiger.set_physics_process(true)
	for i in range(50):
		await wait(0.1)
		if p.health < 100:
			break
	check("harimau menerkam (25 damage)", p.health == 75, p.health)
	tiger.set_physics_process(false)

	# --- Raksasa api ---
	p._server_set_health(100)
	p.global_position = giant.global_position + Vector3(0, 0.1, 3.0)
	giant.set_physics_process(true)
	for i in range(50):
		await wait(0.1)
		if p.health < 100:
			break
	check("raksasa api menghantam (40 damage)", p.health == 60, p.health)
	giant.set_physics_process(false)
	giant.server_take_damage(60, p)
	check("Tombak Pusaka kelak butuh 8 pukulan (450 darah)", giant.health == 390, giant.health)

	# --- Pisang ---
	p._server_set_health(50)
	p.request_add_single_item("pisang")
	p.request_use_item(find_slot(inv, "pisang"))
	check("pisang memulihkan 15 darah", p.health == 65, p.health)

	# --- Peti pusaka hutan dan gunung ---
	for entry in [["Peti Pusaka Hutan", "mahkota_pusaka", 80, 120], ["Peti Pusaka Gunung", "tombak_pusaka", 120, 180]]:
		var chest = find_chest(entry[0])
		var coins_before: int = p.get_coins()
		p.global_position = chest.global_position + chest.global_basis.z * 2.1 + Vector3.UP * 0.2
		await wait(0.7)
		p.request_open_chest(str(chest.name))
		await wait(0.3)
		var gained: int = p.get_coins() - coins_before
		check("%s berisi pusaka dan %d-%d koin" % [entry[0], entry[2], entry[3]], chest != null and chest.is_open and world_item_count(entry[1]) == 1 and gained >= entry[2] and gained <= entry[3], gained)

	# --- Perlengkapan baru ---
	for item_id in ["tombak_pusaka", "mahkota_pusaka", "caping"]:
		p.request_add_single_item(item_id)
	p.request_equip_item(find_slot(inv, "tombak_pusaka"), 0)
	var hand := "GodotRobot3D/RobotArmature/Skeleton3D/LeftHandAttach/"
	var head := "GodotRobot3D/RobotArmature/Skeleton3D/HeadAttach/"
	check("Tombak Pusaka: damage 60 dan terlihat di tangan", p.get_attack_damage() == 60 and p.get_node(hand + "TombakPusaka").visible, p.get_attack_damage())
	var bare_height: float = p.get_current_nickname_height()
	p.request_equip_item(find_slot(inv, "mahkota_pusaka"), 4)
	check("Mahkota Pusaka terlihat di kepala", p.get_node(head + "MahkotaPusaka").visible and not p.get_node(head + "Caping").visible)
	check("nama pemain naik di atas mahkota", p.get_current_nickname_height() > bare_height, [bare_height, p.get_current_nickname_height()])
	p.request_equip_item(find_slot(inv, "caping"), 4)
	check("Caping menggantikan mahkota di kepala", p.get_node(head + "Caping").visible and not p.get_node(head + "MahkotaPusaka").visible)

	# --- Pedagang ---
	var merchant = get_nodes_in_group("merchants")[0]
	var database = root.get_node("ItemDatabase")
	check("pedagang menjual caping (60) dan pisang (6)", merchant.sells("caping") and merchant.sells("pisang") and merchant.get_buy_price(database.get_item("caping")) == 60 and merchant.get_buy_price(database.get_item("pisang")) == 6)

	# --- Audio ---
	var audio = root.get_node("AudioManager")
	var missing: Array[String] = []
	for sfx_name in audio.SFX_NAMES:
		if not ResourceLoader.exists(audio.SFX_DIR + sfx_name + ".wav"):
			missing.append(sfx_name)
	for music_name in audio.MUSIC_NAMES:
		if not ResourceLoader.exists(audio.MUSIC_DIR + music_name + ".wav"):
			missing.append(music_name)
	for ambience_name in audio.AMBIENCE_NAMES:
		if not ResourceLoader.exists(audio.AMBIENCE_DIR + ambience_name + ".wav"):
			missing.append(ambience_name)
	check("semua berkas audio ada dan terimpor", missing.is_empty(), missing)
	var zone_audio_ok := true
	for zone_name in level.ZONE_TITLES:
		if not audio.ZONE_AUDIO.has(zone_name):
			zone_audio_ok = false
	check("tiap zona punya musik dan ambience", zone_audio_ok and audio.ZONE_AUDIO.has("menu"))
	var enemy_sounds_ok := true
	for e in level.enemy_container.get_children():
		if not audio.SFX_NAMES.has(e.windup_sound):
			enemy_sounds_ok = false
	check("suara ancang-ancang tiap musuh terdaftar", enemy_sounds_ok)

	print("SELESAI, gagal: ", failures)
	quit(1 if failures > 0 else 0)
