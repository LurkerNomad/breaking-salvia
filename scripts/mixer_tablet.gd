class_name MixerTablet
extends Node3D

signal mix_requested
signal transfer_requested

const FONT_SIZE_LARGE := 80
const FONT_SIZE_COUNTDOWN := 96

@export_group("SubViewport UI")
@export var viewport: SubViewport
@export var ingredients_vbox: VBoxContainer
@export var scroll_container: ScrollContainer
@export var countdown_label: Label   # separate label shown only while mixing

@export_group("3D Buttons")
@export var mix_button_csg: CSGBox3D
@export var transfer_button_csg: CSGBox3D


func _ready() -> void:
	if countdown_label:
		countdown_label.visible = false
		_style_label(countdown_label, FONT_SIZE_COUNTDOWN)


## Network-synced UI refresh called from the server — itemized ingredient list.
## Only used while NOT mixing; the list stays frozen during a mix (we simply
## don't call this again until the mix finishes or resets).
@rpc("authority", "call_local", "reliable")
func update_display(contents: Dictionary) -> void:
	if ingredients_vbox == null:
		return

	_clear_vbox()

	if contents.is_empty():
		_add_centered_label("Mixer: Empty")
		return

	for item_name in contents.keys():
		var count: int = contents[item_name]
		_add_centered_label("%s x%d" % [item_name, count])


## Called when the mix timer starts — keeps the current ingredient list on
## screen and shows a countdown label alongside it.
@rpc("authority", "call_local", "reliable")
func mix_started() -> void:
	if countdown_label:
		countdown_label.visible = true
		countdown_label.text = "Mixing..."


## Called once per second while mixing.
@rpc("authority", "call_local", "reliable")
func update_countdown(seconds_left: int) -> void:
	if countdown_label:
		countdown_label.text = "Mixing... %ds" % seconds_left


## Called when the mix finishes — clears the itemized ingredient list
## entirely and shows just the finished product's name.
@rpc("authority", "call_local", "reliable")
func show_result(result_name: String) -> void:
	if countdown_label:
		countdown_label.visible = false

	_clear_vbox()
	_add_centered_label(result_name)


func _clear_vbox() -> void:
	for child in ingredients_vbox.get_children():
		child.queue_free()


func _add_centered_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	_style_label(label, FONT_SIZE_LARGE)
	ingredients_vbox.add_child(label)


func _style_label(label: Label, font_size: int) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL


## Handles raycast hits forwarded from Player.gd
func handle_ray_interaction(collider: Object, hit_point: Vector3, is_click: bool, scroll_step: float) -> void:
	if collider.is_in_group("mix_button") and is_click:
		if multiplayer.is_server():
			print("MIX")
			mix_requested.emit()
		else:
			print("MIX")
			_request_mix.rpc_id(1)
		return

	if collider.is_in_group("transfer_button") and is_click:
		if multiplayer.is_server():
			print("TRANSFER")
			transfer_requested.emit()
		else:
			print("TRANSFER")
			_request_transfer.rpc_id(1)
		return


@rpc("any_peer", "call_remote", "reliable")
func _request_mix() -> void:
	if not multiplayer.is_server():
		return
	mix_requested.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_transfer() -> void:
	if not multiplayer.is_server():
		return
	transfer_requested.emit()
