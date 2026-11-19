class_name Item
extends Resource

enum ItemType { WEAPON, CONSUMABLE, TOOL, MISC, HAT, BACKPACK }

enum ItemRarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

enum ContextOptions {
	DROP,
	EQUIP,
	UNEQUIP,
	USE,
}

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var icon: Texture2D

@export var stackable: bool = true
@export var max_stack: int = 99

@export var item_type: ItemType = ItemType.MISC
@export var rarity: ItemRarity = ItemRarity.COMMON
@export var value: int = 0
@export var context_options: Array[Item.ContextOptions] = []

@export var scene_path: String = ""

## Damage per pukulan saat dipakai sebagai senjata (0 = bukan senjata).
@export var damage: int = 0
## Darah yang dipulihkan saat dimakan (0 = tidak bisa dimakan).
@export var heal_amount: int = 0
