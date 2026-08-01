## Furnace — stub for now. Just receives whatever the mixer's hose delivers
## and holds it. Cooking/temperature/fuel logic comes next.
class_name Furnace
extends Node3D

@export var input_socket: MachineSocket

var held_recipe: Recipe = null


func _ready() -> void:
	if input_socket:
		input_socket.owning_machine = self


## Called by MachineSocket.deliver() once a hose transfer completes.
func receive_from_hose(payload) -> void:
	held_recipe = payload
	var label: String = str(payload)
	if payload is Recipe:
		label = payload.recipe_name
	print("[Furnace] Received via hose: ", label)
