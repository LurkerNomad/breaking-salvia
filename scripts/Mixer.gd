class_name Mixer
extends Node3D

## Emitted on the server when mixing completes or spoils.
signal mix_completed(outcome_recipe: Recipe, purity: float)

@export_group("Nodes")
@export var item_receiver: ItemReceiver
@export var mixer_tablet: MixerTablet
@export var spawn_point: Marker3D
@export var output_socket: MachineSocket   # the hose connection point that feeds the furnace

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

@export_group("Mixing")
## How long a mix takes, in seconds. Lower this during debugging so you're
## not waiting 30s every test run.
@export var mix_duration: float = 30.0

# Server state
var current_contents: Dictionary = {}  # e.g. {"Salvia": 2, "Water": 3}
var current_purity: float = 1.0
var decay_timer: Timer

var is_mixing: bool = false
var _mix_time_remaining: float = 0.0
var _last_synced_second: int = -1
var last_result: Recipe = null   # what the transfer button will send out


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
	if is_mixing:
		return  # don't let contents change mid-mix
	if last_result != null:
		return  # a finished batch is waiting for transfer — clear it out first

	if item.ingredient_type == null or item.ingredient_type.item_name == "":
		return

	var item_name := item.ingredient_type.item_name
	current_contents[item_name] = current_contents.get(item_name, 0) + 1

	if item_receiver:
		item_receiver.consume(item)  # now that we've accepted it, it's safe to despawn

	if decay_timer and decay_timer.is_stopped():
		decay_timer.start()

	_sync_tablet_display()


## Triggered when the user presses the 3D "Mix" button
func _on_mix_requested() -> void:
	print("[Mixer] Mix requested. is_mixing=", is_mixing, " contents=", current_contents)

	if not multiplayer.is_server():
		return

	if is_mixing or current_contents.is_empty():
		print("[Mixer] Ignored — already mixing or empty")
		return

	if decay_timer:
		decay_timer.stop()  # no decay while actively mixing

	is_mixing = true
	_mix_time_remaining = mix_duration
	_last_synced_second = -1

	print("[Mixer] Mixing STARTED. duration=", mix_duration, " mixer_tablet assigned=", mixer_tablet != null)

	if mixer_tablet:
		mixer_tablet.mix_started.rpc()
	else:
		print("[Mixer] WARNING: mixer_tablet is not assigned — countdown will never reach the tablet")


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_mixing:
		return

	_mix_time_remaining -= delta
	var whole_seconds := int(ceil(_mix_time_remaining))

	if whole_seconds != _last_synced_second:
		_last_synced_second = whole_seconds
		print("[Mixer] Countdown: ", whole_seconds, "s remaining")
		if mixer_tablet:
			mixer_tablet.update_countdown.rpc(maxi(whole_seconds, 0))

	if _mix_time_remaining <= 0.0:
		is_mixing = false
		print("[Mixer] Mixing FINISHED — evaluating recipe")
		_evaluate_and_process_mix()


## Reserved for future logic (e.g. dumping contents into a container)
func _on_transfer_requested() -> void:
	if not multiplayer.is_server():
		return
	if last_result == null:
		print("[Mixer] Transfer pressed but nothing to send")
		return
	if output_socket == null:
		print("[Mixer] Transfer pressed but no output_socket assigned")
		return

	output_socket.send_payload(last_result)
	last_result = null
	current_contents.clear()
	_sync_tablet_display()  # back to "Mixer: Empty" — don't leave "Result: X" showing


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

	# Work on a private copy — 'recipe' here is the shared .tres asset;
	# mutating it directly would corrupt every other batch using the same recipe.
	var batch := recipe.duplicate() as Recipe
	batch.purity = current_purity
	last_result = batch
	mix_completed.emit(batch, current_purity)

	_spawn_recipe_output(batch)
	_reset_mixer(batch.recipe_name)


func _spoil_batch() -> void:
	if decay_timer:
		decay_timer.stop()

	var batch: Recipe = null
	if garbage_recipe:
		batch = garbage_recipe.duplicate() as Recipe
		batch.purity = 0.0
	last_result = batch

	mix_completed.emit(batch, 0.0)
	_spawn_recipe_output(batch)
	_reset_mixer(batch.recipe_name if batch else "Useless Garbage")


func _spawn_recipe_output(recipe: Recipe) -> void:
	var scene_to_spawn: PackedScene = null
	var ing_res: Ingredient = null

	# recipe is now always a duplicate() (see _finish_mixing/_spoil_batch),
	# so compare by name rather than reference identity.
	if recipe and garbage_recipe and recipe.recipe_name == garbage_recipe.recipe_name:
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


## Clears the "primary" ingredients used in the batch and shows the finished
## product name on the tablet in their place. result_name stays displayed
## until the next mix starts filling the list again.
func _reset_mixer(result_name: String = "") -> void:
	current_contents.clear()
	current_purity = 1.0

	if mixer_tablet:
		if result_name != "":
			mixer_tablet.show_result.rpc(result_name)
		else:
			_sync_tablet_display()


func _sync_tablet_display() -> void:
	if mixer_tablet:
		mixer_tablet.update_display.rpc(current_contents)
