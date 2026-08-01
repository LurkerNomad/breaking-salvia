extends Area3D
class_name ItemReceiver

signal item_received(item: PhysicalIngredient)

@export var accepted_types: Array[String] = []   # empty = accept anything
@export var consume_item: bool = true             # despawn the item once accepted


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

	if not accepted_types.is_empty():
		if item.ingredient_type == null or not accepted_types.has(item.ingredient_type.item_name):
			print("[ItemReceiver] Rejected — not an accepted type:", item.ingredient_type.item_name if item.ingredient_type else "null")
			return

	print("[ItemReceiver] Before emit")
	item_received.emit(item)
	print("[ItemReceiver] After emit")
	print("[ItemReceiver] consume_item =", consume_item)

	# Consumable ingredients (fuel/oxygen canisters — ConsumableIngredient)
	# get drained over time, not destroyed on first contact. PhysicalIngredient
	# auto-tags itself into "consumable_ingredient" based on resource type.
	if consume_item and not item.is_in_group("consumable_ingredient"):
		print("[ItemReceiver] Requesting despawn")
		item.request_despawn()
	elif item.is_in_group("consumable_ingredient"):
		print("[ItemReceiver] Consumable — leaving physical item intact")
