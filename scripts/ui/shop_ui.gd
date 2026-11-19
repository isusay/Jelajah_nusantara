class_name ShopUI
extends Control
## Jendela jual-beli dengan pedagang. Tampilannya dibangun lewat kode; semua
## transaksi dikirim ke server lewat RPC di Character dan baru terlihat di sini
## setelah server menyinkronkan inventory kembali.

signal shop_closed

const ROW_ICON_SIZE := Vector2(40, 40)
const PANEL_SIZE := Vector2(820, 500)

var _player: Character
var _merchant: Merchant

var _title_label: Label
var _coins_label: Label
var _buy_rows: VBoxContainer
var _sell_rows: VBoxContainer
var _panel: PanelContainer


func _ready() -> void:
	_build_layout()
	hide()


func is_shop_visible() -> bool:
	return visible


func open_shop(player: Character, merchant: Merchant) -> void:
	if not player or not merchant:
		return
	_player = player
	_merchant = merchant
	_title_label.text = merchant.display_name
	refresh()
	show()


func close_shop() -> void:
	var was_visible := visible
	hide()
	_player = null
	_merchant = null
	if was_visible:
		shop_closed.emit()


func _process(_delta: float) -> void:
	if not visible:
		return
	# Tutup sendiri bila pemain tumbang, terputus, atau menjauh dari pedagang.
	if not is_instance_valid(_player) or not is_instance_valid(_merchant) or _player.is_downed:
		close_shop()
	elif _player.global_position.distance_to(_merchant.global_position) > Character.TRADE_RANGE + 1.0:
		close_shop()


func refresh() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_merchant):
		return
	var inventory := _player.get_inventory()
	if not inventory:
		return
	_coins_label.text = "Koin: %d" % inventory.coins

	_clear(_buy_rows)
	for item_id in _merchant.stock:
		var item := ItemDatabase.get_item(item_id)
		if not item:
			continue
		var price := _merchant.get_buy_price(item)
		var row := _add_row(_buy_rows, item, item.name, price)
		var buy_button := _add_button(row, "Beli")
		if inventory.coins < price:
			buy_button.disabled = true
			buy_button.tooltip_text = "Koin tidak cukup"
		elif not inventory.can_add_item(item):
			buy_button.disabled = true
			buy_button.tooltip_text = "Tas penuh"
		buy_button.pressed.connect(_on_buy_pressed.bind(item_id))

	_clear(_sell_rows)
	var has_sellable := false
	for slot_index in range(inventory.get_active_slot_count()):
		var slot := inventory.get_slot(slot_index)
		if not slot or slot.is_empty():
			continue
		var item := ItemDatabase.get_item(slot.item_id)
		if not item:
			continue
		var price := _merchant.get_sell_price(item)
		if price <= 0:
			continue
		has_sellable = true
		var label := item.name if slot.quantity <= 1 else "%s x%d" % [item.name, slot.quantity]
		var row := _add_row(_sell_rows, item, label, price)
		_add_button(row, "Jual").pressed.connect(_on_sell_pressed.bind(slot_index, 1))
		if slot.quantity > 1:
			_add_button(row, "Semua").pressed.connect(_on_sell_pressed.bind(slot_index, slot.quantity))
	if not has_sellable:
		var empty := Label.new()
		empty.text = "Tidak ada barang untuk dijual."
		empty.modulate = Color(1, 1, 1, 0.6)
		_sell_rows.add_child(empty)


func _on_buy_pressed(item_id: String) -> void:
	if is_instance_valid(_player) and is_instance_valid(_merchant):
		_player.request_buy_item.rpc_id(1, str(_merchant.name), item_id)


func _on_sell_pressed(slot_index: int, quantity: int) -> void:
	if is_instance_valid(_player) and is_instance_valid(_merchant):
		_player.request_sell_item.rpc_id(1, str(_merchant.name), slot_index, quantity)


# --- Penyusunan tampilan ---


func _clear(container: Control) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _add_row(container: VBoxContainer, item: Item, text: String, price: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	container.add_child(row)

	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.custom_minimum_size = ROW_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.tooltip_text = item.description
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(name_label)

	var price_label := Label.new()
	price_label.text = "%d koin" % price
	price_label.modulate = Color(1.0, 0.85, 0.35)
	row.add_child(price_label)
	return row


func _add_button(row: HBoxContainer, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(64, 32)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(AudioManager.play.bind("ui_click"))
	row.add_child(button)
	return button


func _build_column(parent: HBoxContainer, heading: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	parent.add_child(column)

	var heading_label := Label.new()
	heading_label.text = heading
	heading_label.add_theme_font_size_override("font_size", 20)
	heading_label.modulate = Color(1.0, 0.93, 0.75)
	column.add_child(heading_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	return rows


func _build_layout() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.45)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.1, 0.94)
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = Color(0.75, 0.6, 0.3, 0.8)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	content.add_child(header)

	_title_label = Label.new()
	_title_label.text = "Pedagang"
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title_label)

	_coins_label = Label.new()
	_coins_label.text = "Koin: 0"
	_coins_label.add_theme_font_size_override("font_size", 22)
	_coins_label.modulate = Color(1.0, 0.85, 0.35)
	header.add_child(_coins_label)

	var close_button := Button.new()
	close_button.text = "Tutup [Esc]"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(close_shop)
	header.add_child(close_button)

	content.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	content.add_child(columns)

	_buy_rows = _build_column(columns, "Beli")
	columns.add_child(VSeparator.new())
	_sell_rows = _build_column(columns, "Jual barangmu")
