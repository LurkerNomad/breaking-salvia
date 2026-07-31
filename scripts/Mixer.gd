class_name Mixer
extends Node3D

## Emitted on the server when mixing completes or spoils.
signal mix_completed(outcome_recipe: Recipe, purity: float)

@export_group("Nodes")
@export var item_receiver: ItemReceiver
@export var mixer_tablet: MixerTablet
@export var spawn_point: Marker3D

@export_group("Recipes & Outputs")
## Array of all valid recipes the mixer can output
@export var available_recipes: Array[Recipe] = []
## Fallback Recipe resource used when the mix fails ("Useless Garbage")
@export var garbage_recipe: Recipe
## The Physical Scene to spawn when spawning Garbage (or link inside Recipe)
@export var garbage_physical_scene: PackedScene
## Default fallback ingredient resource to assign to physical trash items
@export var garbage_ingredient_resource: Ingredient

@export_group("Decay Settings")
## Time in seconds before unused ingredients degrade purity
@export var decay_interval: float = 5.0
## Purity lost per decay tick (0.0 to 1.0)
@export var purity_decay_rate: float = 0.05
## Minimum purity floor
@export var min_purity: float = 0.1

# Server state
var current_contents: Dictionary = {}  # e.g. {"Salvia": 2, "Water": 3}
var current_purity: float = 1.0
var decay_timer: Timer


func _ready() -> void:
	if item_receiver:
		item_receiver.item_received.connect(_on_item_received)

	if mixer_tablet:
		mixer_tablet.mix_requested.connect(_on_mix_requested)
		mixer_tablet.transfer_requested.connect(_on_transfer_requested)

	if multiplayer.is_server():
		_setup_decay_timer()


func _setup_decay_timer() -> void:
	decay_timer = Timer.new()
	decay_timer.wait_time = decay_interval
	decay_timer.one_shot = false
	decay_timer.autostart = false
	decay_timer.timeout.connect(_on_decay_tick)
	add_child(decay_timer)


func _on_item_received(item: PhysicalIngredient) -> void:
	if not multiplayer.is_server():
		return

	if item.ingredient_type == null or item.ingredient_type.item_name == "":
		return

	var item_name := item.ingredient_type.item_name
	current_contents[item_name] = current_contents.get(item_name, 0) + 1

	if decay_timer and decay_timer.is_stopped():
		decay_timer.start()

	_sync_tablet_display()


## Triggered when the user presses the 3D "Mix" button
func _on_mix_requested() -> void:
	if not multiplayer.is_server():
		return

	if current_contents.is_empty():
		return

	_evaluate_and_process_mix()


## Reserved for future logic (e.g. dumping contents into a container)
func _on_transfer_requested() -> void:
	if not multiplayer.is_server():
		return
	pass


func _evaluate_and_process_mix() -> void:
	var matched_recipe: Recipe = null

	for recipe in available_recipes:
		if _check_exact_match(recipe):
			matched_recipe = recipe
			break

	if matched_recipe != null:
		_finish_mixing(matched_recipe)
	else:
		_spoil_batch()


func _check_exact_match(recipe: Recipe) -> bool:
	var req := recipe.required_ingredients

	# Ensure no extra ingredients exist beyond what the recipe requires
	for item_name in current_contents.keys():
		if not req.has(item_name):
			return false
		if current_contents[item_name] != req[item_name]:
			return false

	# Ensure all required ingredients are present
	for item_name in req.keys():
		if current_contents.get(item_name, 0) != req[item_name]:
			return false

	return true


func _on_decay_tick() -> void:
	if current_contents.is_empty():
		decay_timer.stop()
		return

	current_purity = maxf(min_purity, current_purity - purity_decay_rate)


func _finish_mixing(recipe: Recipe) -> void:
	if decay_timer:
		decay_timer.stop()

	recipe.purity = current_purity
	mix_completed.emit(recipe, current_purity)

	_spawn_recipe_output(recipe)
	_reset_mixer()


func _spoil_batch() -> void:
	if decay_timer:
		decay_timer.stop()

	if garbage_recipe:
		garbage_recipe.purity = 0.0

	mix_completed.emit(garbage_recipe, 0.0)
	_spawn_recipe_output(garbage_recipe)
	_reset_mixer()


func _spawn_recipe_output(recipe: Recipe) -> void:
	var scene_to_spawn: PackedScene = null
	var ing_res: Ingredient = null

	if recipe == garbage_recipe:
		scene_to_spawn = garbage_physical_scene
		ing_res = garbage_ingredient_resource

	if scene_to_spawn == null:
		return

	var spawn_trans := global_transform if spawn_point == null else spawn_point.global_transform
	var spawned_item := scene_to_spawn.instantiate() as PhysicalIngredient

	if spawned_item:
		if ing_res:
			spawned_item.ingredient_type = ing_res
		get_parent().add_child(spawned_item, true)
		spawned_item.global_transform = spawn_trans


func _reset_mixer() -> void:
	current_contents.clear()
	current_purity = 1.0
	_sync_tablet_display()


func _sync_tablet_display() -> void:
	if mixer_tablet:
		mixer_tablet.update_display.rpc(current_contents)
