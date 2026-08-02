class_name FurnaceTablet
extends Node3D
signal temp_up_requested
signal temp_down_requested
signal cook_requested
signal transfer_requested
const FONT_SIZE_LARGE := 80
@export_group("SubViewport UI")
@export var viewport: SubViewport
@export var temperature_label: Label
@export var status_label: Label   # e.g. "Cooking..." / "Idle" / "Result: X (Q 82%)"
@export var counter_label: Label  # elapsed cook time — counts up while cooking
@export var fuel_label: Label     # current fuel amount — can fill infinitely, just a display

func _ready() -> void:
	if temperature_label:
		_style_label(temperature_label)
	if status_label:
		_style_label(status_label)
	if counter_label:
		_style_label(counter_label)
	if fuel_label:
		_style_label(fuel_label)

@rpc("authority", "call_local", "reliable")
func update_counter(seconds_elapsed: float) -> void:
	if counter_label:
		counter_label.text = "%.1fs" % seconds_elapsed

@rpc("authority", "call_local", "reliable")
func update_fuel(amount: int) -> void:
	if fuel_label:
		fuel_label.text = "Fuel: %d" % amount

@rpc("authority", "call_local", "reliable")
func update_temperature(current_temp: float, target_temp: float) -> void:
	if temperature_label:
		temperature_label.text = "%.0f°C (target %.0f°C)" % [current_temp, target_temp]
@rpc("authority", "call_local", "reliable")
func update_status(text: String) -> void:
	if status_label:
		status_label.text = text
func _style_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", FONT_SIZE_LARGE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
## Handles raycast hits forwarded from Player.gd — same pattern as MixerTablet.
## Tag your 4 physical buttons with these groups in the editor:
##   "furnace_temp_up_button", "furnace_temp_down_button",
##   "furnace_cook_button", "furnace_transfer_button"
func handle_ray_interaction(collider: Object, hit_point: Vector3, is_click: bool, scroll_step: float) -> void:
	if not is_click:
		return
	if collider.is_in_group("furnace_temp_up_button"):
		_send("temp_up")
	elif collider.is_in_group("furnace_temp_down_button"):
		_send("temp_down")
	elif collider.is_in_group("furnace_cook_button"):
		_send("cook")
	elif collider.is_in_group("furnace_transfer_button"):
		_send("transfer")
func _send(action: String) -> void:
	if multiplayer.is_server():
		_emit_local(action)
	else:
		_request_action.rpc_id(1, action)
func _emit_local(action: String) -> void:
	match action:
		"temp_up": temp_up_requested.emit()
		"temp_down": temp_down_requested.emit()
		"cook": cook_requested.emit()
		"transfer": transfer_requested.emit()
@rpc("any_peer", "call_remote", "reliable")
func _request_action(action: String) -> void:
	if not multiplayer.is_server():
		return
	_emit_local(action)
