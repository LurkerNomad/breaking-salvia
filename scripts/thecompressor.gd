## The Compressor: receives a Recipe from the furnace (recipe_input_socket)
## and PressuredGas from a gas canister (gas_input_socket, via FuelCanister.gd
## reused on the gas prop). Activate button climbs PSI by exactly 1/sec while
## consuming 8 gas/sec, tied to the same per-second tick so they never drift
## apart. Press Activate again to stop; quality is based on how close
## current_psi landed to the recipe's target. Transfer sends the Recipe on
## to the (dummy, for now) extractor via output_socket.
class_name TheCompressor
extends Node3D

@export_group("Sockets")
@export var recipe_input_socket: MachineSocket   # from the furnace
@export var gas_input_socket: MachineSocket      # from the PressuredGas canister
@export var output_socket: MachineSocket         # to the extractor

@export_group("Tablet")
@export var compressor_tablet: CompressorTablet

@export_group("Tuning")
@export var psi_rise_per_second: int = 1
@export var gas_cost_per_second: int = 8
@export var quality_loss_per_psi_off: float = 0.02

var loaded_recipe: Recipe = null
var gas_amount: int = 0
var current_psi: int = 0
var is_active: bool = false
var _second_accumulator: float = 0.0


func _ready() -> void:
	if recipe_input_socket:
		recipe_input_socket.owning_machine = self
	if gas_input_socket:
		gas_input_socket.owning_machine = self

	if compressor_tablet:
		compressor_tablet.activate_requested.connect(_on_activate_pressed)
		compressor_tablet.transfer_requested.connect(_on_transfer_pressed)

	_sync_tablet()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_active:
		return

	if gas_amount <= 0:
		print("[TheCompressor] Out of gas — halted")
		is_active = false
		_sync_tablet()
		return

	# Tied to a single per-second tick (not two separate accumulators) so
	# "1 PSI, -8 gas" always happen together exactly as specified, never
	# drifting apart across frames.
	_second_accumulator += delta
	var changed := false
	while _second_accumulator >= 1.0:
		_second_accumulator -= 1.0
		current_psi += psi_rise_per_second
		gas_amount = max(0, gas_amount - gas_cost_per_second)
		changed = true
		if gas_amount <= 0:
			print("[TheCompressor] Ran out of gas mid-cycle — halted")
			is_active = false
			break

	if changed:
		_sync_tablet()


## ── Intake ───────────────────────────────────────────────────────────────
func receive_from_hose(payload, from_socket: MachineSocket) -> void:
	if from_socket == recipe_input_socket:
		if payload is Recipe:
			loaded_recipe = payload
			current_psi = 0
			print("[TheCompressor] Recipe loaded: ", payload.recipe_name, " (target ", payload.pressure, " PSI)")
			_sync_tablet()
		else:
			print("[TheCompressor] recipe_input_socket got a non-Recipe payload, ignoring: ", payload)

	elif from_socket == gas_input_socket:
		var amount: int = 0
		if payload is int:
			amount = payload
		elif payload is float:
			amount = int(payload)
		elif payload is ConsumableIngredient:
			amount = payload.amount
		else:
			print("[TheCompressor] gas_input_socket got an unrecognized payload: ", payload)
			return
		gas_amount += amount
		print("[TheCompressor] Gas received: +", amount, " (total ", gas_amount, ")")
		_sync_tablet()

	else:
		print("[TheCompressor] Payload arrived on an unrecognized socket: ", payload)


## ── Buttons ──────────────────────────────────────────────────────────────
func _on_activate_pressed() -> void:
	if not multiplayer.is_server():
		return

	if not is_active:
		if loaded_recipe == null:
			print("[TheCompressor] Activate pressed but no recipe loaded")
			return
		is_active = true
		print("[TheCompressor] Activated")
	else:
		is_active = false
		print("[TheCompressor] Deactivated at ", current_psi, " PSI (target was ", loaded_recipe.pressure, ")")

	_sync_tablet()


func _on_transfer_pressed() -> void:
	if not multiplayer.is_server():
		return
	if is_active:
		print("[TheCompressor] Deactivate before transferring")
		return
	if loaded_recipe == null:
		print("[TheCompressor] Nothing to transfer")
		return
	if output_socket == null:
		print("[TheCompressor] No output_socket assigned")
		return

	var batch := loaded_recipe
	var psi_off: float = abs(current_psi - batch.pressure)
	var stage_factor: float = clamp(1.0 - psi_off * quality_loss_per_psi_off, 0.0, 1.0)
	batch.purity = clamp(batch.purity * stage_factor, 0.0, 1.0)
	batch.pressurized = true

	print("[TheCompressor] Transferring ", batch.recipe_name, " purity=", batch.purity, " pressurized=", batch.pressurized)
	output_socket.send_payload(batch)

	loaded_recipe = null
	current_psi = 0
	_sync_tablet()


## ── Tablet sync ──────────────────────────────────────────────────────────
func _sync_tablet() -> void:
	if compressor_tablet == null:
		return

	var target: int = loaded_recipe.pressure if loaded_recipe else 0
	compressor_tablet.update_psi.rpc(current_psi, target)
	compressor_tablet.update_gas.rpc(gas_amount)

	var status: String
	if is_active:
		status = "Active"
	elif loaded_recipe:
		status = "Ready: " + loaded_recipe.recipe_name
	else:
		status = "Idle — no recipe"
	compressor_tablet.update_status.rpc(status)
