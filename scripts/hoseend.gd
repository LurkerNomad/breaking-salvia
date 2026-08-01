## One end of a transfer hose. Pickupable (inherits all pickup/carry/throw
## networking from PhysicalIngredient). Connects to another HoseEnd of the
## SAME connector_type (input<->input, output<->output, per spec) when its
## Area3D overlaps one that isn't already connected.
class_name HoseEnd
extends PhysicalIngredient

enum ConnectorType { INPUT, OUTPUT }

@export var connector_type: ConnectorType = ConnectorType.INPUT
@export var connect_area: Area3D           # child Area3D — detection range for nearby hose ends
@export var snap_on_connect: bool = true   # pull the other end exactly onto this socket when connected

signal hose_connected(other: HoseEnd)
signal hose_disconnected

var connected_to: HoseEnd = null
var socketed_to: MachineSocket = null


func _ready() -> void:
	super._ready()
	if connect_area:
		connect_area.body_entered.connect(_on_area_body_entered)
		connect_area.area_entered.connect(_on_area_area_entered)


func _on_area_area_entered(area: Area3D) -> void:
	if not multiplayer.is_server():
		return
	if connected_to != null or socketed_to != null:
		return
	if holder_id != -1:
		return
	if not (area is MachineSocket):
		return

	var socket := area as MachineSocket
	if socket.try_accept(self):
		socketed_to = socket


func _on_area_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if connected_to != null:
		return  # already connected to something
	if holder_id != -1:
		return  # don't auto-connect while someone's still carrying it
	if not (body is HoseEnd):
		return

	var other := body as HoseEnd
	if other == self or other.connected_to != null or other.holder_id != -1 or other.socketed_to != null:
		return
	if other.connector_type != connector_type:
		return  # input only binds to input, output only to output

	_do_connect(other)


func _do_connect(other: HoseEnd) -> void:
	connected_to = other
	other.connected_to = self

	if snap_on_connect and connect_area:
		other.global_position = connect_area.global_position

	_sync_connect.rpc(other.get_path())
	other._sync_connect.rpc(get_path())

	hose_connected.emit(other)
	other.hose_connected.emit(self)

	print("[HoseEnd] Connected: ", name, " <-> ", other.name)


func disconnect_hose() -> void:
	if not multiplayer.is_server():
		return
	if connected_to == null:
		return
	var other := connected_to
	connected_to = null
	other.connected_to = null

	_sync_disconnect.rpc()
	other._sync_disconnect.rpc()

	hose_disconnected.emit()
	other.hose_disconnected.emit()

	print("[HoseEnd] Disconnected: ", name)


## Grabbing a connected end pulls it free automatically, same as unplugging
## a real hose — you shouldn't be able to carry it while still snapped in.
func request_pickup(requester_id: int, requester_node: Node3D) -> void:
	if connected_to != null:
		disconnect_hose()
	if socketed_to != null:
		var socket := socketed_to
		socketed_to = null
		socket.release(self)
	super.request_pickup(requester_id, requester_node)


@rpc("authority", "call_local", "reliable")
func _sync_connect(other_path: NodePath) -> void:
	connected_to = get_node_or_null(other_path) as HoseEnd


@rpc("authority", "call_local", "reliable")
func _sync_disconnect() -> void:
	connected_to = null
