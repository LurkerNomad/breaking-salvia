class_name ExtractorQualityTablet
extends Node3D

const FONT_SIZE_LARGE := 80

@export_group("SubViewport UI")
@export var viewport: SubViewport
@export var quality_label: Label


func _ready() -> void:
	if quality_label:
		_style_label(quality_label)


@rpc("authority", "call_local", "reliable")
func update_quality(quality_fraction: float) -> void:
	print("[ExtractorQualityTablet] update_quality called: ", quality_fraction, " quality_label assigned=", quality_label != null)
	if quality_label:
		quality_label.text = "%.0f%%" % (quality_fraction * 100.0)
	else:
		print("[ExtractorQualityTablet] WARNING: quality_label is not assigned in the Inspector")


func _style_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", FONT_SIZE_LARGE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
