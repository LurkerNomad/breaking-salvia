## TheCompressor — stub for now, same pattern as the original Furnace stub.
## Just receives whatever the furnace's hose delivers and holds it.
## PSI/pressure logic comes next — will set recipe.pressurized when done.
class_name TheCompressor
extends Node3D

@export var input_socket: MachineSocket

var held_recipe: Recipe = null


func _ready() -> void:
	if input_socket:
		input_socket.owning_machine = self


## Called by MachineSocket.deliver() once a hose transfer completes.
func receive_from_hose(payload, from_socket: MachineSocket) -> void:
	held_recipe = payload
	if payload is Recipe:
		print("[TheCompressor] Received via hose: ", payload.recipe_name, " purity=", payload.purity, " cooked=", payload.cooked)
	else:
		print("[TheCompressor] Received via hose (unexpected type): ", payload)
