extends Area3D
class_name ItemReceiver

signal item_received(item: PhysicalIngredient)

@export var accepted_types: Array[String] = []   # empty = accept anything
@export var consume_item: bool = true             # queue_free the item once accepted


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	print("[ItemReceiver] Body entered:", body.name)

	if not multiplayer.is_server():
		return

	if not (body is PhysicalIngredient):
		print("[ItemReceiver] Not a PhysicalIngredient")
		return

	var item := body as PhysicalIngredient

	print("[ItemReceiver] Ingredient detected:", item.name)

	if item.holder_id != -1:
		print("[ItemReceiver] Still being held")
		return

	print("[ItemReceiver] Before emit")
	item_received.emit(item)
	print("[ItemReceiver] After emit")

	print("[ItemReceiver] consume_item =", consume_item)
	
	if consume_item:
		
		print("[ItemReceiver] Requesting despawn")
		item.request_despawn()
