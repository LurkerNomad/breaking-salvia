class_name MixerTablet
extends Node3D

signal mix_requested
signal transfer_requested

@export_group("SubViewport UI")
@export var viewport: SubViewport
@export var ingredients_vbox: VBoxContainer
@export var scroll_container: ScrollContainer

@export_group("3D Buttons")
@export var mix_button_csg: CSGBox3D
@export var transfer_button_csg: CSGBox3D


## Network-synced UI refresh called from the server
@rpc("authority", "call_local", "reliable")
func update_display(contents: Dictionary) -> void:
	if ingredients_vbox == null:
		return

	for child in ingredients_vbox.get_children():
		child.queue_free()

	if contents.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Mixer: Empty"
		ingredients_vbox.add_child(empty_label)
		return

	for item_name in contents.keys():
		var count: int = contents[item_name]
		var label := Label.new()
		label.text = "%s x%d" % [item_name, count]
		label.add_theme_font_size_override("font_size", 24)
		ingredients_vbox.add_child(label)


## Handles raycast hits forwarded from Player.gd
func handle_ray_interaction(collider: Object, hit_point: Vector3, is_click: bool, scroll_step: float) -> void:
	print("[MixerTablet] Collider:", collider)
	print("[MixerTablet] Mix button:", mix_button_csg)
	print("[MixerTablet] Transfer button:", transfer_button_csg)

	if collider.is_in_group("mix_button") and is_click:
		print("[MixerTablet] Mix pressed")

		if multiplayer.is_server():
			mix_requested.emit()
		else:
			_request_mix.rpc_id(1)

		return

	if collider.is_in_group("transfer_button") and is_click:
		print("[MixerTablet] Transfer pressed")

		if multiplayer.is_server():
			transfer_requested.emit()
		else:
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
