class_name CompressorTablet
extends Node3D

signal activate_requested
signal transfer_requested

const FONT_SIZE_LARGE := 80

@export_group("SubViewport UI")
@export var viewport: SubViewport
@export var status_label: Label   # "Active" / "Ready: X" / "Idle — no recipe"
@export var psi_label: Label      # current / target PSI
@export var gas_label: Label      # remaining PressuredGas


func _ready() -> void:
	if status_label:
		_style_label(status_label)
	if psi_label:
		_style_label(psi_label)
	if gas_label:
		_style_label(gas_label)


@rpc("authority", "call_local", "reliable")
func update_status(text: String) -> void:
	if status_label:
		status_label.text = text


@rpc("authority", "call_local", "reliable")
func update_psi(current_psi: int, target_psi: int) -> void:
	if psi_label:
		psi_label.text = "%d PSI (target %d)" % [current_psi, target_psi]


@rpc("authority", "call_local", "reliable")
func update_gas(amount: int) -> void:
	if gas_label:
		gas_label.text = "Gas: %d" % amount


func _style_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", FONT_SIZE_LARGE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL


## Handles raycast hits forwarded from Player.gd — same pattern as the other
## tablets. Tag your 2 physical buttons with these groups:
##   "compressor_activate_button", "compressor_transfer_button"
@warning_ignore("unused_parameter")
func handle_ray_interaction(collider: Object, hit_point: Vector3, is_click: bool, scroll_step: float) -> void:
	if not is_click:
		return
	if collider.is_in_group("compressor_activate_button"):
		_send("activate")
	elif collider.is_in_group("compressor_transfer_button"):
		_send("transfer")


func _send(action: String) -> void:
	if multiplayer.is_server():
		_emit_local(action)
	else:
		_request_action.rpc_id(1, action)


func _emit_local(action: String) -> void:
	match action:
		"activate": activate_requested.emit()
		"transfer": transfer_requested.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_action(action: String) -> void:
	if not multiplayer.is_server():
		return
	_emit_local(action)
