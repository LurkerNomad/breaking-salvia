extends Area3D
class_name ItemReceiver

## IMPORTANT CONTRACT: item_received is just a notification — it does NOT
## mean the item will be consumed. The listener must call consume(item)
## itself once it has actually decided to accept the ingredient (e.g. after
## checking is_mixing / last_result guards). This avoids silently destroying
## ingredients that the listener rejected.
signal item_received(item: PhysicalIngredient)

@export var accepted_types: Array[String] = []   # empty = accept anything
@export var consume_item: bool = true             # despawn the item once the listener confirms via consume()


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
		# Walking a held ingredient into a valid intake auto-releases it from
		# whoever's carrying it, same pattern as hose docking — no need to
		# manually drop first. request_drop() is server-authoritative and
		# synchronously clears holder_id + the holder's held_item tracking
		# (via its call_local confirm RPC) before we continue below, so this
		# is safe even in multiplayer — no client ever decides this, only
		# the server (we're already inside the `is_server()` guard above).
		print("[ItemReceiver] Held — auto-dropping before intake")
		item.request_drop()

	if not accepted_types.is_empty():
		if item.ingredient_type == null or not accepted_types.has(item.ingredient_type.item_name):
			print("[ItemReceiver] Rejected — not an accepted type:", item.ingredient_type.item_name if item.ingredient_type else "null")
			return

	print("[ItemReceiver] Before emit")
	item_received.emit(item)
	print("[ItemReceiver] After emit — awaiting listener to call consume() if accepted")


## Call this from the listener ONLY once it has actually accepted the item
## (e.g. Mixer calls this after passing its is_mixing / last_result guards).
## Consumable ingredients (fuel/oxygen canisters) are still left physically
## intact regardless, since they're drained over time, not single-use.
func consume(item: PhysicalIngredient) -> void:
	if not multiplayer.is_server():
		return
	if consume_item and not item.is_in_group("consumable_ingredient"):
		print("[ItemReceiver] Requesting despawn")
		item.request_despawn()
	elif item.is_in_group("consumable_ingredient"):
		print("[ItemReceiver] Consumable — leaving physical item intact")
