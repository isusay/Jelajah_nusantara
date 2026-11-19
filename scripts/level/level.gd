extends Node3D

const MAX_CHAT_MESSAGE_LENGTH := 160
const MIN_NICKNAME_HEIGHT := 2.0
const MAX_NICKNAME_HEIGHT := 8.0
const ENEMY_RESPAWN_SECONDS := 45.0
const ENEMY_RESPAWN_CHECK_SECONDS := 1.0
const SPAWN_RING_RADIUS := 8.0
const AUTOSAVE_SECONDS := 20.0
const ENEMY_SCENES := {
	"boar": preload("res://scenes/enemies/boar.tscn"),
	"monkey": preload("res://scenes/enemies/monkey.tscn"),
	"guardian": preload("res://scenes/enemies/guardian.tscn"),
	"tiger": preload("res://scenes/enemies/tiger.tscn"),
	"giant": preload("res://scenes/enemies/giant.tscn"),
}
const ZONE_TITLES := {
	"desa": "Desa Pelabuhan - zona aman",
	"pantai": "Pantai",
	"hutan": "Hutan Rimba",
	"candi": "Candi Pusaka",
	"gunung": "Gunung Api",
}

@export var player_scene: PackedScene
@export var chest_scene: PackedScene = preload("res://scenes/world/chest.tscn")

var chat_visible := false
var inventory_visible := false
var player_list_visible := false

var _player_nickname_heights: Dictionary = {}
var _nickname_heights_requested := false
var _nickname_height_requesters: Dictionary = {}
var _world_populated := false
var _enemy_slots: Array[Dictionary] = []
var _enemy_respawn_check := 0.0
var _autosave_time_left := AUTOSAVE_SECONDS

@onready var players_container: Node3D = $PlayersContainer
@onready var main_menu: MainMenuUI = $MainMenuUI
@onready var multiplayer_chat: MultiplayerChatUI = $MultiplayerChatUI
@onready var inventory_ui: InventoryUI = $InventoryUI
@onready var player_list_ui: PlayerListUI = $PlayerListUI
@onready var pause_menu: PauseMenuUI = $PauseMenuUI
@onready var hud_ui: HudUI = $HudUI
@onready var shop_ui: ShopUI = $ShopUI
@onready var environment_root: Node3D = $Environment
@onready var item_container: Node3D = $Environment/ItemContainer
@onready var enemy_container: Node3D = $Environment/EnemyContainer
@onready var chest_container: Node3D = $Environment/ChestContainer
@onready var enemy_spawns: Node3D = $Environment/Pantai/EnemySpawns
@onready var chest_spawns: Node3D = $Environment/Pantai/ChestSpawns


func _ready():
	after_ready()

	if DisplayServer.get_name() == "headless":
		Network.start_host("", "")

	pause_menu.hide_menu()
	main_menu.show_menu()
	multiplayer_chat.set_process_input(true)

	main_menu.host_pressed.connect(_on_host_pressed)
	main_menu.join_pressed.connect(_on_join_pressed)
	main_menu.quit_pressed.connect(_on_quit_pressed)
	pause_menu.resume_pressed.connect(_on_pause_resume_pressed)
	pause_menu.main_menu_pressed.connect(_on_pause_main_menu_pressed)
	pause_menu.quit_pressed.connect(_on_pause_quit_pressed)

	if inventory_ui:
		inventory_ui.inventory_closed.connect(_on_inventory_closed)
	shop_ui.shop_closed.connect(_update_mouse_mode)

	if multiplayer_chat:
		multiplayer_chat.message_sent.connect(_on_chat_message_sent)

	Network.server_disconnected.connect(_on_server_disconnected)
	Network.connect("player_connected", Callable(self, "_on_player_connected"))
	multiplayer.peer_disconnected.connect(_remove_player)
	_update_mouse_mode()
	_server_populate_world()
	AudioManager.set_zone("menu")


func _process(delta: float) -> void:
	_server_tick_enemy_respawns(delta)
	_server_tick_autosave(delta)
	var can_show_player_list := (
		not main_menu.is_menu_visible() and not pause_menu.is_menu_visible() and multiplayer.has_multiplayer_peer()
	)
	if Input.is_key_pressed(KEY_TAB) and can_show_player_list:
		if not player_list_visible:
			_show_player_list()
	elif player_list_visible:
		_hide_player_list()


func after_ready():
	var ip_address: String
	if OS.has_feature("windows"):
		if OS.has_environment("COMPUTERNAME"):
			ip_address = IP.resolve_hostname(str(OS.get_environment("COMPUTERNAME")), IP.TYPE_IPV4)
	elif OS.has_feature("x11"):
		if OS.has_environment("HOSTNAME"):
			ip_address = IP.resolve_hostname(str(OS.get_environment("HOSTNAME")), IP.TYPE_IPV4)
	elif OS.has_feature("OSX"):
		if OS.has_environment("HOSTNAME"):
			ip_address = IP.resolve_hostname(str(OS.get_environment("HOSTNAME")), IP.TYPE_IPV4)
	main_menu.address_input.text = ip_address


func _on_server_disconnected():
	_reset_session_ui()


func _reset_session_ui() -> void:
	for child in players_container.get_children():
		child.queue_free()

	for container in [item_container, enemy_container, chest_container]:
		for child in container.get_children():
			child.queue_free()
	_world_populated = false
	_enemy_slots.clear()
	hud_ui.unbind_player()
	shop_ui.close_shop()
	AudioManager.set_zone("menu")

	chat_visible = false
	inventory_visible = false
	_hide_player_list()
	_player_nickname_heights.clear()
	_nickname_heights_requested = false
	_nickname_height_requesters.clear()
	multiplayer_chat.close_chat()
	multiplayer_chat.clear_chat()
	if inventory_ui:
		inventory_ui.close_inventory()
		inventory_ui.current_player = null
	_hide_pause_menu(false)
	main_menu.show_menu()
	_update_mouse_mode()


func _on_player_connected(peer_id, player_info):
	var player = _add_player(peer_id, player_info)
	if multiplayer.is_server() and player:
		_server_restore_player(player, peer_id)
		player.call_deferred("_sync_inventory_to_owner")
	if multiplayer.is_server():
		if peer_id != 1:
			call_deferred("_sync_nickname_heights_to_peer", peer_id)
	elif not _nickname_heights_requested:
		_nickname_heights_requested = true
		call_deferred("_request_nickname_heights")
	_refresh_player_list()


func _on_host_pressed(nickname: String, skin: String):
	var error = Network.start_host(nickname, skin)
	if error:
		push_warning("Failed to host game. Error: " + str(error))
		main_menu.show_menu()
		_update_mouse_mode()
		return
	main_menu.hide_menu()
	_update_mouse_mode()
	_server_populate_world()


func _on_join_pressed(nickname: String, skin: String, address: String):
	var error = Network.join_game(nickname, skin, address)
	if error:
		push_warning("Failed to join game. Error: " + str(error))
		main_menu.show_menu()
		_update_mouse_mode()
		return
	main_menu.hide_menu()
	_update_mouse_mode()


func _add_player(id: int, player_info: Dictionary) -> Character:
	if DisplayServer.get_name() == "headless" and id == 1:
		return null

	if players_container.has_node(str(id)):
		return players_container.get_node(str(id)) as Character

	var player = player_scene.instantiate()
	player.name = str(id)
	player.position = get_spawn_point(id)
	players_container.add_child(player, true)

	var nick = Network.sanitize_nickname(str(player_info.get("nick", "")), "Player_" + str(id))
	player.nickname.text = nick

	var skin_enum = Network.sanitize_skin_value(player_info.get("skin", Character.SkinColor.BLUE))
	player.set_player_skin(skin_enum)
	_apply_player_nickname_height(id)
	if id == multiplayer.get_unique_id():
		hud_ui.bind_player(player)
	return player


func get_spawn_point(id: int) -> Vector3:
	# Posisi lokal terhadap PlayersContainer, tepat di atas permukaan pasir.
	var spawn_angle := fmod(float(id) * 2.399963229728653, 2.0 * PI)
	var spawn_point := Vector2.from_angle(spawn_angle) * SPAWN_RING_RADIUS
	var ground := Vector3(spawn_point.x, environment_root.global_position.y + 0.1, spawn_point.y)
	return players_container.to_local(ground)


func _remove_player(id):
	_player_nickname_heights.erase(id)
	if not players_container.has_node(str(id)):
		call_deferred("_refresh_player_list")
		return
	var player_node = players_container.get_node(str(id))
	if player_node:
		if Network.is_hosting():
			server_save_player(player_node as Character)
			SaveGame.flush()
		player_node.queue_free()
	Network.forget_player_token(id)
	call_deferred("_refresh_player_list")


func _on_quit_pressed() -> void:
	server_save_all()
	Network.leave_game()
	get_tree().quit()


func toggle_chat():
	if main_menu.is_menu_visible() or is_gameplay_input_blocked():
		return

	multiplayer_chat.toggle_chat()
	chat_visible = multiplayer_chat.is_chat_visible()
	_update_mouse_mode()


func is_chat_visible() -> bool:
	return multiplayer_chat.is_chat_visible()


func _input(event):
	if event.is_action_pressed("pause"):
		_handle_pause_action()
		get_viewport().set_input_as_handled()
		return

	if is_gameplay_input_blocked():
		return

	if event.is_action_pressed("toggle_chat"):
		toggle_chat()
	elif chat_visible and multiplayer_chat.message.has_focus():
		pass
	elif event.is_action_pressed("inventory"):
		toggle_inventory()
	elif event.is_action_pressed("use_food"):
		var local_player := _get_local_player()
		if local_player and not is_camera_input_blocked():
			local_player.use_first_food()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_debug_add_item()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		_debug_print_inventory()


func _on_chat_message_sent(message_text: String) -> void:
	chat_visible = multiplayer_chat.is_chat_visible()
	_update_mouse_mode()

	var trimmed_message = _sanitize_chat_message(message_text)
	if trimmed_message.is_empty():
		return

	if multiplayer.is_server():
		_broadcast_chat_message(multiplayer.get_unique_id(), trimmed_message)
	else:
		submit_chat_message.rpc_id(1, trimmed_message)


@rpc("any_peer", "reliable")
func submit_chat_message(message_text: String):
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var trimmed_message = _sanitize_chat_message(message_text)
	if trimmed_message.is_empty():
		return
	_broadcast_chat_message(sender_id, trimmed_message)


func _broadcast_chat_message(sender_id: int, message_text: String):
	var player_info = Network.players.get(sender_id, {})
	var nick = Network.sanitize_nickname(str(player_info.get("nick", "")), "Player_" + str(sender_id))
	show_chat_message.rpc(nick, message_text)


@rpc("authority", "call_local", "reliable")
func show_chat_message(nick: String, msg: String):
	multiplayer_chat.add_message(nick, msg)
	if nick == "Kabar" and msg.contains("Peti Pusaka"):
		AudioManager.play("pusaka")


func _sanitize_chat_message(message_text: String) -> String:
	var clean = message_text.strip_edges()
	if clean.length() > MAX_CHAT_MESSAGE_LENGTH:
		clean = clean.substr(0, MAX_CHAT_MESSAGE_LENGTH)
	return clean


func toggle_inventory():
	if main_menu.is_menu_visible() or is_gameplay_input_blocked():
		return

	var local_player = _get_local_player()
	if not local_player or shop_ui.visible:
		return

	inventory_visible = !inventory_visible
	if inventory_visible:
		inventory_ui.open_inventory(local_player)
	else:
		inventory_ui.close_inventory()
	_update_mouse_mode()


func is_inventory_visible() -> bool:
	return inventory_visible


func _show_player_list() -> void:
	if main_menu.is_menu_visible() or pause_menu.is_menu_visible() or not multiplayer.has_multiplayer_peer():
		return
	player_list_visible = true
	player_list_ui.show_players(Network.players, multiplayer.get_unique_id())


func _hide_player_list() -> void:
	player_list_visible = false
	if player_list_ui:
		player_list_ui.hide_players()


func _refresh_player_list() -> void:
	if player_list_visible and player_list_ui:
		player_list_ui.refresh_players(Network.players, multiplayer.get_unique_id())


func register_player_nickname_height(player_id: int, height: float) -> void:
	if not multiplayer.is_server() or player_id <= 0:
		return
	var normalized_height := _normalize_nickname_height(height)
	_store_and_apply_player_nickname_height(player_id, normalized_height)
	sync_player_nickname_height.rpc(player_id, normalized_height)


@rpc("authority", "reliable")
func sync_player_nickname_height(player_id: int, height: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_store_and_apply_player_nickname_height(player_id, _normalize_nickname_height(height))


func _request_nickname_heights() -> void:
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		return
	request_nickname_heights.rpc_id(1)


@rpc("any_peer", "reliable")
func request_nickname_heights() -> void:
	if not multiplayer.is_server():
		return
	var requester_id := multiplayer.get_remote_sender_id()
	if requester_id <= 0 or _nickname_height_requesters.has(requester_id):
		return
	_nickname_height_requesters[requester_id] = true
	_sync_nickname_heights_to_peer(requester_id)


func _sync_nickname_heights_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return
	for child in players_container.get_children():
		var player := child as Character
		if not player:
			continue
		var player_id := str(player.name).to_int()
		var height := float(_player_nickname_heights.get(player_id, player.get_current_nickname_height()))
		sync_player_nickname_height.rpc_id(peer_id, player_id, _normalize_nickname_height(height))


func _store_and_apply_player_nickname_height(player_id: int, height: float) -> void:
	if player_id <= 0:
		return
	_player_nickname_heights[player_id] = height
	_apply_player_nickname_height(player_id)


func _apply_player_nickname_height(player_id: int) -> void:
	if not _player_nickname_heights.has(player_id):
		return
	var player := players_container.get_node_or_null(str(player_id)) as Character
	if player:
		player.apply_synced_nickname_height(float(_player_nickname_heights[player_id]))


func _normalize_nickname_height(height: float) -> float:
	if is_nan(height) or is_inf(height):
		return MIN_NICKNAME_HEIGHT
	return clampf(height, MIN_NICKNAME_HEIGHT, MAX_NICKNAME_HEIGHT)


func _on_inventory_closed():
	inventory_visible = false
	_update_mouse_mode()


func is_gameplay_input_blocked() -> bool:
	return pause_menu.is_menu_visible()


func is_camera_input_blocked() -> bool:
	return (
		is_gameplay_input_blocked() or inventory_visible or shop_ui.visible or multiplayer_chat.is_chat_visible()
	)


func _handle_pause_action() -> void:
	if shop_ui.visible:
		shop_ui.close_shop()
		return
	if inventory_visible:
		_close_inventory()
		return
	if multiplayer_chat.is_chat_visible():
		_close_chat()
		return
	if pause_menu.is_menu_visible():
		_hide_pause_menu()
		return
	if main_menu.is_menu_visible() or not multiplayer.has_multiplayer_peer():
		return
	_show_pause_menu()


func _show_pause_menu() -> void:
	pause_menu.show_menu()
	_update_mouse_mode()


func _hide_pause_menu(restore_mouse_mode: bool = true) -> void:
	if not pause_menu.is_menu_visible():
		return
	pause_menu.hide_menu()
	if restore_mouse_mode:
		_update_mouse_mode()


func _close_chat() -> void:
	multiplayer_chat.close_chat()
	chat_visible = false
	_update_mouse_mode()


func _close_inventory() -> void:
	inventory_ui.close_inventory()
	inventory_visible = false
	_update_mouse_mode()


func _update_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var ui_requires_cursor := (
		main_menu.is_menu_visible()
		or pause_menu.is_menu_visible()
		or inventory_visible
		or shop_ui.visible
		or not multiplayer.has_multiplayer_peer()
	)
	if ui_requires_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_pause_resume_pressed() -> void:
	_hide_pause_menu()


func _on_pause_main_menu_pressed() -> void:
	_hide_pause_menu(false)
	server_save_all()
	Network.leave_game()
	if not main_menu.is_menu_visible():
		_reset_session_ui()


func _on_pause_quit_pressed() -> void:
	server_save_all()
	Network.leave_game()
	get_tree().quit()


func update_local_inventory_display():
	if inventory_ui:
		inventory_ui.refresh_display()
	if shop_ui.visible:
		shop_ui.refresh()


func _get_local_player() -> Character:
	var local_player_id = multiplayer.get_unique_id()
	if players_container.has_node(str(local_player_id)):
		return players_container.get_node(str(local_player_id)) as Character
	return null


func _debug_add_item():
	if not OS.is_debug_build() or not multiplayer.is_server():
		return
	var local_player = _get_local_player()
	if local_player:
		var test_items: Array[String] = []
		for item_id in ItemDatabase.get_all_items():
			test_items.append(str(item_id))
		if test_items.is_empty():
			return
		var random_item = test_items[randi() % test_items.size()]
		local_player.request_add_item.rpc_id(1, random_item, 1)


func _debug_print_inventory():
	var local_player = _get_local_player()
	if local_player and local_player.get_inventory():
		var inventory = local_player.get_inventory()
		print("=== Inventory Debug ===")
		for i in range(inventory.slots.size()):
			var slot = inventory.get_slot(i)
			if slot and not slot.is_empty():
				print("Slot ", i, ": ", slot.item_id, " x", slot.quantity)
		print("=====================")
	else:
		print("No inventory found for local player")


# --- Dunia: musuh, peti, dan item (server) ---


func _server_populate_world() -> void:
	if _world_populated or not Network.is_hosting():
		return
	_world_populated = true

	# Tiap zona (Pantai, Candi, ...) boleh punya node EnemySpawns dan ChestSpawns
	# berisi Marker3D. Metadata marker mengatur jenis musuh dan isi peti.
	_enemy_slots.clear()
	for zone in environment_root.get_children():
		var zone_enemy_spawns := zone.get_node_or_null("EnemySpawns")
		if zone_enemy_spawns:
			for marker in zone_enemy_spawns.get_children():
				var spawn := marker as Node3D
				if not spawn:
					continue
				var slot := {
					"position": spawn.global_position,
					"type": str(spawn.get_meta("enemy_type", "boar")),
					"respawn_seconds": float(spawn.get_meta("respawn_seconds", ENEMY_RESPAWN_SECONDS)),
					"enemy": null,
					"respawn_at_msec": -1
				}
				_enemy_slots.append(slot)
				_server_spawn_enemy(slot)

		var zone_chest_spawns := zone.get_node_or_null("ChestSpawns")
		if zone_chest_spawns and chest_scene:
			for marker in zone_chest_spawns.get_children():
				var spawn := marker as Node3D
				if not spawn:
					continue
				var chest := chest_scene.instantiate() as Chest
				chest.position = chest_container.to_local(spawn.global_position)
				chest.rotation = spawn.global_rotation
				chest.configure_from_marker(spawn)
				chest_container.add_child(chest, true)

		# Item yang tergeletak di dunia sejak awal sesi (misalnya pisang di hutan).
		var zone_item_spawns := zone.get_node_or_null("ItemSpawns")
		if zone_item_spawns:
			for marker in zone_item_spawns.get_children():
				var spawn := marker as Node3D
				if spawn and spawn.has_meta("item_id"):
					server_spawn_world_item(str(spawn.get_meta("item_id")), spawn.global_position)


func _server_spawn_enemy(slot: Dictionary) -> void:
	var enemy_scene: PackedScene = ENEMY_SCENES.get(str(slot.get("type", "boar")), ENEMY_SCENES["boar"])
	var enemy := enemy_scene.instantiate() as Enemy
	if not enemy:
		return
	var spawn_position: Vector3 = slot["position"]
	enemy.position = enemy_container.to_local(spawn_position + Vector3.UP * 0.1)
	enemy.rotation.y = randf_range(0.0, TAU)
	enemy_container.add_child(enemy, true)
	slot["enemy"] = enemy
	slot["respawn_at_msec"] = -1


func _server_tick_enemy_respawns(delta: float) -> void:
	if not _world_populated or not Network.is_hosting():
		return
	_enemy_respawn_check -= delta
	if _enemy_respawn_check > 0.0:
		return
	_enemy_respawn_check = ENEMY_RESPAWN_CHECK_SECONDS

	var now := Time.get_ticks_msec()
	for slot in _enemy_slots:
		var enemy: Variant = slot["enemy"]
		if is_instance_valid(enemy) and not (enemy as Enemy).is_dead():
			continue
		if int(slot["respawn_at_msec"]) < 0:
			slot["enemy"] = null
			slot["respawn_at_msec"] = now + int(float(slot.get("respawn_seconds", ENEMY_RESPAWN_SECONDS)) * 1000.0)
		elif now >= int(slot["respawn_at_msec"]) and not _is_player_near(slot["position"], 18.0):
			_server_spawn_enemy(slot)


func _is_player_near(world_position: Vector3, radius: float) -> bool:
	for child in players_container.get_children():
		var player := child as Character
		if player and player.global_position.distance_to(world_position) <= radius:
			return true
	return false


## Memunculkan item di dunia. Hanya server; MultiplayerSpawner yang menyalinnya ke client.
func server_spawn_world_item(item_id: String, world_position: Vector3, impulse: Vector3 = Vector3.ZERO) -> void:
	if not Network.is_hosting():
		return
	var item := ItemDatabase.get_item(item_id)
	if not item or item.scene_path.is_empty() or not ResourceLoader.exists(item.scene_path):
		push_warning("Cannot spawn world item: '" + item_id + "'")
		return
	var packed_scene := load(item.scene_path) as PackedScene
	if not packed_scene:
		return
	var instance := packed_scene.instantiate() as Node3D
	if not instance:
		return
	instance.position = item_container.to_local(world_position)
	item_container.add_child(instance, true)
	var body := instance as RigidBody3D
	if body and not impulse.is_zero_approx():
		body.apply_central_impulse(impulse * body.mass)


# --- Pedagang ---


func open_shop(merchant: Merchant) -> void:
	if main_menu.is_menu_visible() or is_gameplay_input_blocked() or shop_ui.visible:
		return
	var local_player := _get_local_player()
	if not local_player or local_player.is_downed:
		return
	if inventory_visible:
		_close_inventory()
	if multiplayer_chat.is_chat_visible():
		_close_chat()
	shop_ui.open_shop(local_player, merchant)
	_update_mouse_mode()


func is_shop_visible() -> bool:
	return shop_ui.visible


# --- Pengumuman ---


## Mengirim kabar ke semua pemain (chat dan HUD).
func server_announce(text: String) -> void:
	if not Network.is_hosting():
		return
	show_chat_message.rpc("Kabar", text)
	for child in players_container.get_children():
		var player := child as Character
		if player:
			player.server_notify(text)


# --- Simpan progres (server) ---


func _server_restore_player(player: Character, peer_id: int) -> void:
	var token := Network.get_player_token(peer_id)
	if token.is_empty():
		return
	var saved := SaveGame.load_player_inventory(token)
	if not saved.is_empty():
		player.server_apply_saved_inventory(saved)


func server_save_player(player: Character) -> void:
	if not player or not player.get_inventory():
		return
	var token := Network.get_player_token(player.get_multiplayer_authority())
	if token.is_empty():
		return
	SaveGame.store_player(token, player.nickname.text, player.get_inventory().to_dict())


func server_save_all() -> void:
	if not Network.is_hosting():
		return
	for child in players_container.get_children():
		server_save_player(child as Character)
	SaveGame.flush()


func _server_tick_autosave(delta: float) -> void:
	if not Network.is_hosting():
		return
	_autosave_time_left -= delta
	if _autosave_time_left <= 0.0:
		_autosave_time_left = AUTOSAVE_SECONDS
		server_save_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		server_save_all()


# --- Zona ---


## Nama zona di suatu posisi dunia: "desa", "pantai", "hutan", "candi", atau "gunung".
## Dipakai HUD untuk judul zona dan AudioManager untuk musik.
func get_zone_at(world_position: Vector3) -> String:
	for node in get_tree().get_nodes_in_group("safe_zones"):
		var zone := node as Node3D
		if not zone:
			continue
		var offset := world_position - zone.global_position
		if Vector2(offset.x, offset.z).length() <= float(zone.get_meta("radius", 20.0)):
			return "desa"
	var local := environment_root.to_local(world_position)
	if local.x < -67.0:
		return "hutan" if local.z > -45.0 else "gunung"
	if local.z < -50.0 and absf(local.x) < 36.0:
		return "candi"
	return "pantai"
