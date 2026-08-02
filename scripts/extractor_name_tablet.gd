class_name ExtractorNameTablet
extends Node3D

const FONT_SIZE_LARGE := 80

@export_group("SubViewport UI")
@export var viewport: SubViewport
@export var name_label: Label
@export var quantity_label: Label


func _ready() -> void:
	if name_label:
		_style_label(name_label)
	if quantity_label:
		_style_label(quantity_label)


@rpc("authority", "call_local", "reliable")
func update_display(product_name: String, quantity_remaining: int) -> void:
	if name_label:
		name_label.text = product_name
	if quantity_label:
		quantity_label.text = "x%d" % quantity_remaining


func _style_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", FONT_SIZE_LARGE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
