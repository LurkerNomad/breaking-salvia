## A fuel canister. Pickupable/carryable/throwable just like any other
## PhysicalIngredient — but it ALSO has an output hose socket to feed a
## furnace, and a valve you can toggle on/off.
##
## fuel_resource should be a ConsumableIngredient marked "Local to Scene" in
## the Inspector (right-click the property -> Make Unique) — since there are
## multiple canisters, each needs its OWN independent .amount rather than
## every canister sharing (and draining) the same .tres asset.
class_name FuelCanister
extends PhysicalIngredient

@export var output_socket: MachineSocket
@export var valve_area: Area3D                    # tag this node in group "fuel_valve" in the editor
@export var fuel_resource: ConsumableIngredient   # make this Local to Scene per-instance!
@export var drain_time: float = 3.0               # seconds to fully empty once the valve is open

var valve_open: bool = false
var _start_amount: int = 100      # captured at _ready — drain rate is based on the FULL tank, not whatever's left
var _drain_accumulator: float = 0.0


func _ready() -> void:
	super._ready()
	if output_socket:
		output_socket.owning_machine = self
	if fuel_resource:
		_start_amount = fuel_resource.amount


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not valve_open or fuel_resource == null or fuel_resource.amount <= 0:
		return

	# Integer-safe draining: accumulate fractional "units owed" in a float,
	# only ever subtract whole ints from fuel_resource.amount once a full
	# unit has accrued. Avoids float drift (3.00000003-style amounts).
	var drain_rate: float = float(_start_amount) / drain_time  # units/sec
	_drain_accumulator += drain_rate * delta

	var whole: int = int(_drain_accumulator)
	if whole >= 1:
		whole = min(whole, fuel_resource.amount)
		_drain_accumulator -= whole
		fuel_resource.amount -= whole

		if output_socket:
			var dest := output_socket.get_other_end_socket()
			if dest:
				dest.deliver(whole)   # sends a plain int — see Furnace.receive_from_hose

		if fuel_resource.amount <= 0:
			print("[FuelCanister] Empty")


## Called via Player's raycast when it hits valve_area.
func toggle_valve(requester_id: int) -> void:
	if not multiplayer.is_server():
		return
	valve_open = not valve_open
	print("[FuelCanister] Valve ", "OPENED" if valve_open else "CLOSED", " by peer ", requester_id)
	_sync_valve.rpc(valve_open)


@rpc("authority", "call_local", "reliable")
func _sync_valve(open: bool) -> void:
	valve_open = open
	# Hook here later to swap a valve handle mesh/material for visual feedback.
