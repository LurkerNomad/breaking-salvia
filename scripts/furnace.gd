## Furnace: receives a Recipe from the mixer (via recipe_input_socket) and
## fuel from a gas canister (via fuel_input_socket, hose added later).
## Cook button starts the temperature climbing automatically; press it again
## to stop. Quality is based on how close current_temperature was to the
## recipe's target when you stopped. Transfer sends a CookedProduct out to
## the compressor via output_socket.
class_name Furnace
extends Node3D

@export_group("Sockets")
@export var recipe_input_socket: MachineSocket   # from the mixer
@export var fuel_input_socket: MachineSocket     # from the gas canister (hose comes later)
@export var output_socket: MachineSocket         # to the compressor

@export_group("Tablet")
@export var furnace_tablet: FurnaceTablet

@export_group("Tuning")
@export var ambient_temperature: float = 20.0
@export var temp_rise_min: float = 1.0    # °C/sec climb while cooking, per original spec
@export var temp_rise_max: float = 3.0
@export var temp_button_step: float = 5.0
@export var fuel_per_second_cooking: int = 1
@export var quality_loss_per_degree_off: float = 0.02   # how harshly temp inaccuracy hurts quality

var loaded_recipe: Recipe = null
var has_cooked_this_batch: bool = false
var fuel_amount: int = 0
var _fuel_consume_accumulator: float = 0.0
var current_temperature: float = 20.0
var is_cooking: bool = false
var cook_elapsed: float = 0.0


func _ready() -> void:
	current_temperature = ambient_temperature
	if recipe_input_socket:
		recipe_input_socket.owning_machine = self
	if fuel_input_socket:
		fuel_input_socket.owning_machine = self

	if furnace_tablet:
		furnace_tablet.temp_up_requested.connect(_on_temp_up)
		furnace_tablet.temp_down_requested.connect(_on_temp_down)
		furnace_tablet.cook_requested.connect(_on_cook_pressed)
		furnace_tablet.transfer_requested.connect(_on_transfer_pressed)

	_sync_tablet()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_cooking:
		return

	if fuel_amount <= 0:
		print("[Furnace] Out of fuel — cooking halted")
		is_cooking = false
		_sync_tablet()
		return

	current_temperature += randf_range(temp_rise_min, temp_rise_max) * delta
	cook_elapsed += delta

	# Integer-safe consumption: accumulate fractional "owed" fuel in a float,
	# only ever subtract whole ints from fuel_amount — avoids float drift.
	_fuel_consume_accumulator += float(fuel_per_second_cooking) * delta
	var whole_consumed: int = int(_fuel_consume_accumulator)
	if whole_consumed >= 1:
		whole_consumed = min(whole_consumed, fuel_amount)
		_fuel_consume_accumulator -= whole_consumed
		fuel_amount -= whole_consumed

	_sync_tablet()


## ── Intake ───────────────────────────────────────────────────────────────
## Called by MachineSocket.deliver(). from_socket tells us which input this
## arrived on, since a furnace has two different inputs.
func receive_from_hose(payload, from_socket: MachineSocket) -> void:
	if from_socket == recipe_input_socket:
		if payload is Recipe:
			loaded_recipe = payload
			has_cooked_this_batch = false
			print("[Furnace] Recipe loaded: ", payload.recipe_name, " (target ", payload.temperature, "°C)")
			_sync_tablet()
		else:
			print("[Furnace] recipe_input_socket got a non-Recipe payload, ignoring: ", payload)

	elif from_socket == fuel_input_socket:
		var amount: int = 0
		if payload is int:
			amount = payload
		elif payload is float:
			amount = int(payload)  # canister always sends whole ints, but be defensive
		elif payload is ConsumableIngredient:
			amount = payload.amount
		else:
			print("[Furnace] fuel_input_socket got an unrecognized payload: ", payload)
			return
		fuel_amount += amount
		print("[Furnace] Fuel received: +", amount, " (total ", fuel_amount, ")")
		_sync_tablet()

	else:
		print("[Furnace] Payload arrived on an unrecognized socket: ", payload)


## ── Buttons ──────────────────────────────────────────────────────────────
func _on_temp_up() -> void:
	if not multiplayer.is_server():
		return
	current_temperature += temp_button_step
	_sync_tablet()


func _on_temp_down() -> void:
	if not multiplayer.is_server():
		return
	current_temperature = max(ambient_temperature, current_temperature - temp_button_step)
	_sync_tablet()


func _on_cook_pressed() -> void:
	if not multiplayer.is_server():
		return

	if not is_cooking:
		if loaded_recipe == null:
			print("[Furnace] Cook pressed but no recipe loaded")
			return
		is_cooking = true
		cook_elapsed = 0.0
		print("[Furnace] Cooking started")
	else:
		is_cooking = false
		has_cooked_this_batch = true
		print("[Furnace] Cooking stopped at ", current_temperature, "°C (target was ", loaded_recipe.temperature, "°C)")

	_sync_tablet()


func _on_transfer_pressed() -> void:
	if not multiplayer.is_server():
		return
	if is_cooking:
		print("[Furnace] Stop cooking before transferring")
		return
	if loaded_recipe == null:
		print("[Furnace] Nothing cooked to transfer")
		return
	if output_socket == null:
		print("[Furnace] No output_socket assigned")
		return

	# loaded_recipe already arrived as a private duplicate from the Mixer
	# (it duplicates before sending), so it's safe to mutate further here.
	var batch := loaded_recipe

	var stage_factor: float
	if has_cooked_this_batch:
		stage_factor = _calculate_temp_accuracy_factor()
		batch.cooked = true
		print("[Furnace] Transferring (cooked) ", batch.recipe_name, " temp_factor=", stage_factor)
	else:
		stage_factor = 0.8  # skipped cooking entirely — flat 20% quality penalty
		batch.cooked = false
		print("[Furnace] Transferring (SKIPPED cooking) ", batch.recipe_name, " — 20% quality penalty")

	batch.purity = clamp(batch.purity * stage_factor, 0.0, 1.0)

	print("[Furnace] Transferring ", batch.recipe_name, " purity=", batch.purity, " cooked=", batch.cooked)
	output_socket.send_payload(batch)

	loaded_recipe = null
	has_cooked_this_batch = false
	current_temperature = ambient_temperature
	cook_elapsed = 0.0
	_sync_tablet()


func _calculate_temp_accuracy_factor() -> float:
	if loaded_recipe == null:
		return 0.0
	var degrees_off: float = abs(current_temperature - loaded_recipe.temperature)
	return clamp(1.0 - degrees_off * quality_loss_per_degree_off, 0.0, 1.0)


## ── Tablet sync ──────────────────────────────────────────────────────────
func _sync_tablet() -> void:
	if furnace_tablet == null:
		return

	var target: float = loaded_recipe.temperature if loaded_recipe else ambient_temperature
	furnace_tablet.update_temperature.rpc(current_temperature, target)

	var status: String
	if is_cooking:
		status = "Cooking..."
	elif loaded_recipe:
		status = "Ready: " + loaded_recipe.recipe_name
	else:
		status = "Idle — no recipe"
	furnace_tablet.update_status.rpc(status)
	furnace_tablet.update_counter.rpc(cook_elapsed)
	furnace_tablet.update_fuel.rpc(fuel_amount)
