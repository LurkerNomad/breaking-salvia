## Root node for a transfer hose: two pickupable HoseEnd children joined by a
## non-pickupable stretchy cable. The cable is purely visual + a soft length
## constraint — not a physics joint. Direct-position correction is simple and
## stable enough for a "leash" feel; if it ever looks janky under Jolt with
## both ends free-falling at once, that's the first thing to revisit.
class_name TransferHose
extends Node3D

@export var input_end: HoseEnd
@export var output_end: HoseEnd
@export var cable_mesh: MeshInstance3D   # a CylinderMesh instance works well
@export var max_length: float = 6.0
@export var transfer_time: float = 2.5

const CABLE_COLOR_IDLE := Color(0, 0, 0)
const CABLE_COLOR_TRANSFERRING := Color(0.2, 0.4, 1.0)

var _cable_material: StandardMaterial3D


func _ready() -> void:
	# CylinderMesh resources are shared by default — duplicate so resizing
	# THIS hose's cable doesn't resize every other hose using the same mesh.
	if cable_mesh and cable_mesh.mesh:
		cable_mesh.mesh = cable_mesh.mesh.duplicate()

	# Same deal for the material — duplicate so color changes are per-hose.
	if cable_mesh:
		var mat := cable_mesh.get_surface_override_material(0)
		if mat == null and cable_mesh.mesh:
			mat = cable_mesh.mesh.surface_get_material(0)
		if mat is StandardMaterial3D:
			_cable_material = mat.duplicate()
		else:
			_cable_material = StandardMaterial3D.new()
		_cable_material.albedo_color = CABLE_COLOR_IDLE
		cable_mesh.set_surface_override_material(0, _cable_material)


## Called by MachineSocket.send_payload() on the OUTPUT-side machine.
## Figures out which end sent it and which end should receive it, flashes
## the cable blue, waits transfer_time seconds, then delivers and flashes
## back to white.
func transfer_payload(payload, from_socket: MachineSocket) -> void:
	if not multiplayer.is_server():
		return

	var to_end: HoseEnd = null
	if input_end and input_end.socketed_to == from_socket:
		to_end = output_end
	elif output_end and output_end.socketed_to == from_socket:
		to_end = input_end

	if to_end == null or to_end.socketed_to == null:
		print("[TransferHose] Cannot deliver — other end isn't connected to a machine")
		return

	var to_socket := to_end.socketed_to
	print("[TransferHose] Transfer started (", transfer_time, "s): ", payload)

	_set_cable_color.rpc(CABLE_COLOR_TRANSFERRING)
	await get_tree().create_timer(transfer_time).timeout
	_set_cable_color.rpc(CABLE_COLOR_IDLE)

	to_socket.deliver(payload)
	print("[TransferHose] Transfer arrived")


@rpc("authority", "call_local", "reliable")
func _set_cable_color(color: Color) -> void:
	if _cable_material:
		_cable_material.albedo_color = color


func _physics_process(_delta: float) -> void:
	if input_end == null or output_end == null:
		return
	_enforce_length_constraint()
	_update_cable_visual()


func _enforce_length_constraint() -> void:
	if not multiplayer.is_server():
		return

	var a := input_end.global_position
	var b := output_end.global_position
	var diff := b - a
	var dist := diff.length()

	if dist <= max_length or dist < 0.001:
		return

	var excess := dist - max_length
	var dir := diff / dist

	var a_free := input_end.holder_id == -1
	var b_free := output_end.holder_id == -1

	# Don't yank an end out of someone's hands — only pull free ends.
	if a_free and b_free:
		input_end.global_position += dir * excess * 0.5
		output_end.global_position -= dir * excess * 0.5
	elif a_free:
		input_end.global_position += dir * excess
	elif b_free:
		output_end.global_position -= dir * excess
	# if both ends are held (two players carrying opposite ends), let it
	# stretch visually rather than fighting both players' movement.


func _update_cable_visual() -> void:
	if cable_mesh == null:
		return

	var a := input_end.global_position
	var b := output_end.global_position
	var dist := a.distance_to(b)

	cable_mesh.global_position = (a + b) * 0.5
	if dist > 0.001:
		cable_mesh.look_at(b, Vector3.UP)
		cable_mesh.rotate_object_local(Vector3.RIGHT, PI / 2.0)  # CylinderMesh's long axis is Y by default

	if cable_mesh.mesh is CylinderMesh:
		cable_mesh.mesh.height = dist
