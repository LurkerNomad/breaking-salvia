## A fixed connection point on a piece of machinery (mixer output, furnace
## input, etc). A HoseEnd of the matching connector_type snaps to this
## socket's Marker3D when it overlaps. Tag machine sockets and hose connect
## points with matching groups in the editor for easy identification:
##   - this node:            group "machine_socket"
##   - HoseEnd.connect_area:  group "hose_connector"
## (grouping is for organization/debug filtering — actual matching logic
## uses connector_type, not group name).
class_name MachineSocket
extends Area3D

@export var connector_type: HoseEnd.ConnectorType = HoseEnd.ConnectorType.INPUT
@export var socket_marker: Marker3D       # exact snap position + rotation; defaults to self if unset
@export var owning_machine: Node          # e.g. the Mixer or Furnace this socket belongs to

var connected_hose_end: HoseEnd = null


func _ready() -> void:
	add_to_group("machine_socket")


## Returns the snap transform: the assigned Marker3D if set, otherwise this
## socket's own transform. (Can't just assign `self` to socket_marker — it's
## typed Marker3D and this node is an Area3D, so that's a type mismatch.)
func _get_snap_transform() -> Transform3D:
	if socket_marker:
		return socket_marker.global_transform
	return global_transform


## Called by a HoseEnd when its connect_area overlaps this socket.
func try_accept(hose_end: HoseEnd) -> bool:
	if not multiplayer.is_server():
		return false
	if connected_hose_end != null:
		return false
	if hose_end.connector_type != connector_type:
		return false
	if hose_end.connected_to != null or hose_end.socketed_to != null:
		return false

	connected_hose_end = hose_end
	var snap_transform := _get_snap_transform()
	hose_end.global_position = snap_transform.origin
	hose_end.global_rotation = snap_transform.basis.get_euler()
	hose_end.freeze = true

	print("[MachineSocket] ", name, " accepted hose end: ", hose_end.name)
	return true


func release(hose_end: HoseEnd) -> void:
	if connected_hose_end == hose_end:
		connected_hose_end = null
		print("[MachineSocket] ", name, " released hose end: ", hose_end.name)


## Called by TransferHose once a payload finishes its 2.5s transit and
## arrives at this socket. Forwards to whatever machine owns this socket,
## passing itself along so machines with more than one input socket (e.g.
## Furnace: recipe input vs fuel input) can tell them apart.
func deliver(payload) -> void:
	if owning_machine and owning_machine.has_method("receive_from_hose"):
		owning_machine.receive_from_hose(payload, self)
	else:
		print("[MachineSocket] ", name, " has no owning_machine with receive_from_hose() — payload dropped: ", payload)


## For continuous streams (e.g. a fuel canister's valve, not a discrete
## batch), returns the socket on the OTHER end of the currently connected
## hose, if any — bypasses TransferHose's blue-flash/delay theatrics, which
## are meant for one-shot batch sends, not a steady drip.
func get_other_end_socket() -> MachineSocket:
	if connected_hose_end == null:
		return null
	var hose := connected_hose_end.get_parent() as TransferHose
	if hose == null:
		return null
	var other_end: HoseEnd = hose.output_end if hose.input_end == connected_hose_end else hose.input_end
	if other_end == null:
		return null
	return other_end.socketed_to


## Called by the OUTPUT-side machine (e.g. Mixer) to push a payload out
## through whatever hose is currently connected here.
func send_payload(payload) -> void:
	if connected_hose_end == null:
		print("[MachineSocket] ", name, " — no hose connected, cannot send")
		return
	var hose := connected_hose_end.get_parent() as TransferHose
	if hose == null:
		print("[MachineSocket] ", name, " — connected hose end has no TransferHose parent")
		return
	hose.transfer_payload(payload, self)
