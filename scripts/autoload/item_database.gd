extends Node

const FEDORA_ICON: Texture2D = preload("res://assets/items/hats/icons/fedora.png")
const HEADPHONES_ICON: Texture2D = preload("res://assets/items/hats/icons/headphones.png")
const PIRATE_HAT_ICON: Texture2D = preload("res://assets/items/hats/icons/pirate_hat.png")
const SHERIFF_HAT_ICON: Texture2D = preload("res://assets/items/hats/icons/sheriff_hat.png")
const SOMBRERO_ICON: Texture2D = preload("res://assets/items/hats/icons/sombrero.png")
const WIZARD_HAT_ICON: Texture2D = preload("res://assets/items/hats/icons/wizard_hat.png")
const BACKPACK_ICON: Texture2D = preload("res://assets/items/backpacks/icons/backpack.png")
const SWORD_ICON: Texture2D = preload("res://assets/items/weapons/icons/sword.png")
const SWORD_BIG_ICON: Texture2D = preload("res://assets/items/weapons/icons/sword_big.png")
const AXE_ICON: Texture2D = preload("res://assets/items/weapons/icons/axe.png")
const CHICKEN_LEG_ICON: Texture2D = preload("res://assets/items/misc/icons/chicken_leg.png")
const BONE_ICON: Texture2D = preload("res://assets/items/misc/icons/bone.png")
const CHALICE_ICON: Texture2D = preload("res://assets/items/misc/icons/chalice.png")
const KERIS_PUSAKA_ICON: Texture2D = preload("res://assets/items/pusaka/icons/keris_pusaka.png")
const TOMBAK_PUSAKA_ICON: Texture2D = preload("res://assets/items/pusaka/icons/tombak_pusaka.png")
const MAHKOTA_PUSAKA_ICON: Texture2D = preload("res://assets/items/pusaka/icons/mahkota_pusaka.png")
const CAPING_ICON: Texture2D = preload("res://assets/items/hats/icons/caping.png")
const PISANG_ICON: Texture2D = preload("res://assets/items/misc/icons/pisang.png")

const HATS := "res://scenes/items/hats/"
const WEAPONS := "res://scenes/items/weapons/"
const MISC := "res://scenes/items/misc/"

var items: Dictionary = {}


func _ready():
	_create_items()


func get_item(item_id: String) -> Item:
	return items.get(item_id)


func get_all_items() -> Dictionary:
	return items


func _create_items() -> void:
	# Topi: kosmetik, hadiah dari peti.
	_add_equipment(
		"fedora", "Topi Fedora", "Topi laken yang tak lekang waktu.", Item.ItemType.HAT, HATS + "fedora.tscn", FEDORA_ICON, 25
	)
	_add_equipment(
		"headphones",
		"Headphone",
		"Headphone empuk penutup telinga.",
		Item.ItemType.HAT,
		HATS + "headphones.tscn",
		HEADPHONES_ICON,
		25
	)
	_add_equipment(
		"pirate_hat",
		"Topi Bajak Laut",
		"Topi lusuh milik perompak pemberani.",
		Item.ItemType.HAT,
		HATS + "pirate_hat.tscn",
		PIRATE_HAT_ICON,
		25
	)
	_add_equipment(
		"sheriff_hat",
		"Topi Sheriff",
		"Topi koboi berlencana.",
		Item.ItemType.HAT,
		HATS + "sheriff_hat.tscn",
		SHERIFF_HAT_ICON,
		25
	)
	_add_equipment(
		"sombrero", "Sombrero", "Topi lebar penuh warna.", Item.ItemType.HAT, HATS + "sombrero.tscn", SOMBRERO_ICON, 25
	)
	_add_equipment(
		"wizard_hat",
		"Topi Penyihir",
		"Topi runcing bergaya gaib.",
		Item.ItemType.HAT,
		HATS + "wizard_hat.tscn",
		WIZARD_HAT_ICON,
		25
	)

	_add_equipment(
		"caping", "Caping", "Topi kerucut anyaman bambu, peneduh para petani.", Item.ItemType.HAT, HATS + "caping.tscn", CAPING_ICON, 30
	)
	_add_equipment(
		"mahkota_pusaka",
		"Mahkota Pusaka",
		"Mahkota emas raja lama, disembunyikan di sarang harimau.",
		Item.ItemType.HAT,
		"res://scenes/items/pusaka/mahkota_pusaka.tscn",
		MAHKOTA_PUSAKA_ICON,
		350,
		Item.ItemRarity.LEGENDARY
	)

	_add_equipment(
		"backpack",
		"Tas Punggung",
		"Tas kokoh. Menambah 4 slot barang saat dipakai.",
		Item.ItemType.BACKPACK,
		"res://scenes/items/backpacks/backpack.tscn",
		BACKPACK_ICON,
		60,
		Item.ItemRarity.UNCOMMON
	)

	# Senjata: damage per pukulan. Tangan kosong = Character.UNARMED_DAMAGE.
	_add_weapon("sword", "Golok", "Golok serbaguna, bekal setiap penjelajah.", WEAPONS + "sword.tscn", SWORD_ICON, 80, 20)
	_add_weapon(
		"axe",
		"Kapak",
		"Kapak kecil bermata baja tajam.",
		WEAPONS + "axe.tscn",
		AXE_ICON,
		95,
		28,
		Item.ItemRarity.UNCOMMON
	)
	_add_weapon(
		"sword_big",
		"Pedang Besar",
		"Pedang dua tangan yang berat dan mematikan.",
		WEAPONS + "sword_big.tscn",
		SWORD_BIG_ICON,
		120,
		35,
		Item.ItemRarity.RARE
	)

	# Pusaka: hadiah utama tiap zona. Kuat sebagai senjata, mahal bila dijual.
	_add_weapon(
		"keris_pusaka",
		"Keris Pusaka",
		"Keris bertuah peninggalan leluhur, dijaga arca di dalam candi.",
		"res://scenes/items/pusaka/keris_pusaka.tscn",
		KERIS_PUSAKA_ICON,
		400,
		45,
		Item.ItemRarity.LEGENDARY
	)

	_add_weapon(
		"tombak_pusaka",
		"Tombak Pusaka",
		"Tombak bermata api dari puncak gunung. Senjata terkuat.",
		"res://scenes/items/pusaka/tombak_pusaka.tscn",
		TOMBAK_PUSAKA_ICON,
		800,
		60,
		Item.ItemRarity.LEGENDARY
	)

	_add_food("pisang", "Pisang", "Sesisir pisang hutan. Memulihkan sedikit darah.", MISC + "pisang.tscn", PISANG_ICON, 3, 15)
	_add_food("chicken_leg", "Ayam Bakar", "Paha ayam bakar. Memulihkan darah.", MISC + "chicken_leg.tscn", CHICKEN_LEG_ICON, 5, 30)

	_add_misc("bone", "Tulang", "Tulang tua yang sudah lapuk.", MISC + "bone.tscn", BONE_ICON, 2)
	_add_misc(
		"chalice",
		"Cawan Emas",
		"Cawan emas peninggalan lama. Laku mahal.",
		MISC + "chalice.tscn",
		CHALICE_ICON,
		60,
		Item.ItemRarity.RARE
	)


func _new_item(
	item_id: String,
	item_name: String,
	item_description: String,
	item_type: Item.ItemType,
	scene_path: String,
	item_icon: Texture2D,
	item_value: int,
	item_rarity: Item.ItemRarity
) -> Item:
	var item := Item.new()
	item.id = item_id
	item.name = item_name
	item.description = item_description
	item.item_type = item_type
	item.rarity = item_rarity
	item.value = item_value
	item.icon = item_icon
	item.scene_path = scene_path
	items[item.id] = item
	return item


func _add_equipment(
	item_id: String,
	item_name: String,
	item_description: String,
	item_type: Item.ItemType,
	scene_path: String,
	item_icon: Texture2D,
	item_value: int,
	item_rarity: Item.ItemRarity = Item.ItemRarity.COMMON
) -> Item:
	var item := _new_item(
		item_id, item_name, item_description, item_type, scene_path, item_icon, item_value, item_rarity
	)
	item.stackable = false
	item.max_stack = 1
	item.context_options.append(Item.ContextOptions.EQUIP)
	item.context_options.append(Item.ContextOptions.DROP)
	return item


func _add_weapon(
	item_id: String,
	item_name: String,
	item_description: String,
	scene_path: String,
	item_icon: Texture2D,
	item_value: int,
	item_damage: int,
	item_rarity: Item.ItemRarity = Item.ItemRarity.COMMON
) -> void:
	var item := _add_equipment(
		item_id, item_name, item_description, Item.ItemType.WEAPON, scene_path, item_icon, item_value, item_rarity
	)
	item.damage = item_damage


func _add_food(
	item_id: String,
	item_name: String,
	item_description: String,
	scene_path: String,
	item_icon: Texture2D,
	item_value: int,
	item_heal: int
) -> void:
	var item := _new_item(
		item_id,
		item_name,
		item_description,
		Item.ItemType.CONSUMABLE,
		scene_path,
		item_icon,
		item_value,
		Item.ItemRarity.COMMON
	)
	item.stackable = true
	item.max_stack = 99
	item.heal_amount = item_heal
	item.context_options.append(Item.ContextOptions.USE)
	item.context_options.append(Item.ContextOptions.DROP)


func _add_misc(
	item_id: String,
	item_name: String,
	item_description: String,
	scene_path: String,
	item_icon: Texture2D,
	item_value: int,
	item_rarity: Item.ItemRarity = Item.ItemRarity.COMMON
) -> void:
	var item := _new_item(
		item_id, item_name, item_description, Item.ItemType.MISC, scene_path, item_icon, item_value, item_rarity
	)
	item.stackable = true
	item.max_stack = 99
	item.context_options.append(Item.ContextOptions.DROP)
