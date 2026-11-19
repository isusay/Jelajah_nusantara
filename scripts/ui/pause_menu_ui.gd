class_name PauseMenuUI
extends Control

signal resume_pressed
signal main_menu_pressed
signal quit_pressed

const SAFE_AREA_MARGIN := 16.0

@onready var resume_button: Button = $Overlay/Panel/MarginContainer/Buttons/Resume
@onready var panel: PanelContainer = $Overlay/Panel


func _ready() -> void:
	_add_volume_sliders()
	resized.connect(_update_responsive_layout)
	call_deferred("_update_responsive_layout")
	hide()


func show_menu() -> void:
	show()
	call_deferred("_update_responsive_layout")
	resume_button.grab_focus()


func hide_menu() -> void:
	hide()


func is_menu_visible() -> bool:
	return visible


func _update_responsive_layout() -> void:
	if not panel:
		return
	var available_size := Vector2(
		maxf(1.0, size.x - SAFE_AREA_MARGIN * 2.0), maxf(1.0, size.y - SAFE_AREA_MARGIN * 2.0)
	)
	var panel_size := panel.size
	if panel_size.x <= 0.0 or panel_size.y <= 0.0:
		return
	var scale_factor := minf(1.0, minf(available_size.x / panel_size.x, available_size.y / panel_size.y))
	panel.pivot_offset = panel_size * 0.5
	panel.scale = Vector2.ONE * scale_factor


func _on_resume_pressed() -> void:
	resume_pressed.emit()


func _on_main_menu_pressed() -> void:
	main_menu_pressed.emit()


func _on_quit_pressed() -> void:
	quit_pressed.emit()


# --- Pengaturan suara ---


func _add_volume_sliders() -> void:
	var buttons := resume_button.get_parent()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	buttons.add_child(box)
	buttons.move_child(box, resume_button.get_index())
	_add_volume_row(box, "Musik", AudioManager.music_volume, AudioManager.set_music_volume)
	_add_volume_row(box, "Efek suara", AudioManager.sfx_volume, AudioManager.set_sfx_volume)


func _add_volume_row(parent: Control, title: String, value: float, on_changed: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)

	var label := Label.new()
	label.text = title
	label.custom_minimum_size = Vector2(140, 0)
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(220, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(on_changed)
	row.add_child(slider)
