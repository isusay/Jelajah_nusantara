extends Node
## Simpan progres pemain (isi tas, barang yang dipakai, koin) di sisi server.
##
## Tiap pemain dikenali lewat token acak yang dibuat sekali dan disimpan di
## komputernya sendiri (`user://jelajah_profile.cfg`). Server menyimpan progres
## per token di `user://jelajah_save.json`, jadi progres ikut ke server tempat
## pemain itu bermain, bukan ke komputer pemain.
##
## Argumen baris perintah (setelah `--`):
##   --save-suffix=_nama   pakai berkas simpanan terpisah (dipakai tes otomatis)
##   --no-save             matikan simpan dan muat

const SAVE_VERSION := 1
const TOKEN_LENGTH := 32

var enabled := true
var suffix := ""

var _data := {"version": SAVE_VERSION, "players": {}}
var _loaded := false
var _local_token := ""


# Dibaca di _init supaya sudah berlaku sebelum node lain mulai berjalan.
func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--no-save":
			enabled = false
		elif argument.begins_with("--save-suffix="):
			suffix = argument.trim_prefix("--save-suffix=").validate_filename().substr(0, 24)


func get_save_path() -> String:
	return "user://jelajah_save%s.json" % suffix


func get_profile_path() -> String:
	return "user://jelajah_profile%s.cfg" % suffix


func is_valid_token(token: String) -> bool:
	return token.length() == TOKEN_LENGTH and token.is_valid_hex_number()


## Token milik komputer ini; dibuat saat pertama kali dibutuhkan.
func get_local_token() -> String:
	if not _local_token.is_empty():
		return _local_token
	var profile := ConfigFile.new()
	if profile.load(get_profile_path()) == OK:
		var stored := str(profile.get_value("player", "token", ""))
		if is_valid_token(stored):
			_local_token = stored
			return _local_token
	_local_token = Crypto.new().generate_random_bytes(TOKEN_LENGTH / 2).hex_encode()
	profile.set_value("player", "token", _local_token)
	profile.save(get_profile_path())
	return _local_token


## Membaca ulang berkas simpanan dari disk.
func reload() -> void:
	_data = {"version": SAVE_VERSION, "players": {}}
	_loaded = true
	if not enabled or not FileAccess.file_exists(get_save_path()):
		return
	var file := FileAccess.open(get_save_path(), FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and parsed.get("players") is Dictionary:
		_data["players"] = parsed["players"]
	else:
		push_warning("Berkas simpanan rusak, diabaikan: " + get_save_path())


func has_player(token: String) -> bool:
	if not _loaded:
		reload()
	return enabled and is_valid_token(token) and _data["players"].has(token)


## Mengembalikan isi tas tersimpan dalam bentuk yang aman untuk
## `PlayerInventory.from_dict`, atau kamus kosong bila belum ada.
func load_player_inventory(token: String) -> Dictionary:
	if not has_player(token):
		return {}
	var entry: Variant = _data["players"][token]
	if not (entry is Dictionary) or not (entry.get("inventory") is Dictionary):
		return {}
	return _clean_inventory(entry["inventory"])


func store_player(token: String, nickname: String, inventory: Dictionary) -> void:
	if not enabled or not is_valid_token(token):
		return
	if not _loaded:
		reload()
	_data["players"][token] = {
		"nick": nickname,
		"saved_at": Time.get_datetime_string_from_system(),
		"inventory": _clean_inventory(inventory)
	}


## Menulis semua progres ke disk.
func flush() -> void:
	if not enabled or not _loaded:
		return
	var file := FileAccess.open(get_save_path(), FileAccess.WRITE)
	if not file:
		push_warning("Gagal menulis berkas simpanan: " + get_save_path())
		return
	file.store_string(JSON.stringify(_data, "\t"))


func delete_save() -> void:
	if FileAccess.file_exists(get_save_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(get_save_path()))
	_data = {"version": SAVE_VERSION, "players": {}}
	_loaded = true


# JSON mengembalikan semua angka sebagai float dan isinya bisa saja diubah
# tangan, jadi setiap nilai dipaksa ke tipe yang benar di sini.
func _clean_slot(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {"item_id": "", "quantity": 0}
	return {"item_id": str(raw.get("item_id", "")), "quantity": int(raw.get("quantity", 0))}


func _clean_inventory(raw: Dictionary) -> Dictionary:
	var slots: Array = []
	var raw_slots: Variant = raw.get("slots", [])
	if raw_slots is Array:
		for raw_slot in raw_slots:
			if slots.size() >= PlayerInventory.MAX_INVENTORY_SIZE:
				break
			slots.append(_clean_slot(raw_slot))
	return {
		"slots": slots,
		"equipped_weapon": _clean_slot(raw.get("equipped_weapon")),
		"equipped_hat": _clean_slot(raw.get("equipped_hat")),
		"equipped_backpack": _clean_slot(raw.get("equipped_backpack")),
		"coins": clampi(int(raw.get("coins", 0)), 0, PlayerInventory.MAX_COINS)
	}
