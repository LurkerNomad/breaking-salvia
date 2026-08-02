## Extractor: receives one Recipe batch from the compressor and splits it into
## trays_per_batch (3) separate product deliveries. A tray placed in
## drainer_area gets locked and filled over drain_duration seconds; only one
## tray can occupy the drainer at a time. The single Extractor button only
## checks whether a tray is currently present — nothing else gates it.
class_name Extractor
extends Node3D

@export var input_socket: MachineSocket    # from the compressor
@export var drainer_area: Area3D           # where a tray must be placed

@export_group("Tablets")
@export var name_tablet: ExtractorNameTablet
@export var quality_tablet: ExtractorQualityTablet

@export_group("Tuning")
@export var drain_duration: float = 5.0
@export var trays_per_batch: int = 3

var pending_batches: Array[Recipe] = []
var current_batch_name: String = ""
var current_batch_quality: float = 0.0

var current_tray: Tray = null
var is_draining: bool = false
var _drain_timer: float = 0.0


func _ready() -> void:
	if input_socket:
		input_socket.owning_machine = self
	if drainer_area:
		# Area-to-Area detection against the tray's own detection_area — same
		# pattern as the hose docking system. More reliable than body_entered,
		# which depends on the tray's physical RigidBody collision layer/mask
		# lining up exactly with the drainer's monitor settings.
		drainer_area.area_entered.connect(_on_tray_area_entered)
		drainer_area.area_exited.connect(_on_tray_area_exited)

	_sync_display()


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_draining:
		return

	_drain_timer += delta
	if _drain_timer >= drain_duration:
		_finish_drain()


## ── Intake ───────────────────────────────────────────────────────────────
func receive_from_hose(payload, from_socket: MachineSocket) -> void:
	if not (payload is Recipe):
		print("[Extractor] Unexpected payload: ", payload)
		return

	pending_batches.clear()
	for i in trays_per_batch:
		pending_batches.append(payload.duplicate() as Recipe)

	current_batch_name = payload.recipe_name
	current_batch_quality = payload.purity
	print("[Extractor] Batch received: ", payload.recipe_name, " split into ", trays_per_batch, " trays, quality=", payload.purity)
	_sync_display()


## ── Tray detection (Area-to-Area against the tray's detection_area) ────────
func _on_tray_area_entered(area: Area3D) -> void:
	if not multiplayer.is_server():
		return
	var tray := area.get_parent()
	if not (tray is Tray):
		return
	if current_tray != null:
		print("[Extractor] Drainer already occupied — ignoring extra tray")
		return
	current_tray = tray
	print("[Extractor] Tray detected in drainer: ", tray.name)


func _on_tray_area_exited(area: Area3D) -> void:
	if not multiplayer.is_server():
		return
	var tray := area.get_parent()
	if tray != current_tray:
		return
	if is_draining:
		return  # tray is locked mid-drain, shouldn't be able to leave anyway
	current_tray = null


## ── Button (implements handle_ray_interaction directly — no separate tablet
## needed for a single button; Player.gd's broadcast system picks this up
## automatically since it has the method). ─────────────────────────────────
func handle_ray_interaction(collider: Object, hit_point: Vector3, is_click: bool, scroll_step: float) -> void:
	if not is_click:
		return
	print("[Extractor] handle_ray_interaction called with collider=", collider.name if collider is Node else collider, " groups=", collider.get_groups() if collider is Node else "n/a")
	if not collider.is_in_group("extractor_button"):
		return
	print("[Extractor] Button group matched — activating")

	if multiplayer.is_server():
		_try_activate()
	else:
		_request_activate.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_activate() -> void:
	if not multiplayer.is_server():
		return
	_try_activate()


func _try_activate() -> void:
	if is_draining:
		print("[Extractor] Already draining")
		return
	if current_tray == null:
		print("[Extractor] No tray in drainer — button does nothing")
		return
	if current_tray.held_recipe != null:
		# Guards against physics jitter: a tray resting right at the Area3D's
		# boundary can flicker in/out of overlap and re-fire area_entered
		# even though it never physically left — that would otherwise let a
		# single tray get refilled repeatedly without ever being swapped out.
		print("[Extractor] This tray is already filled — swap in an empty one")
		return
	if pending_batches.is_empty():
		print("[Extractor] Nothing to dispense")
		return

	is_draining = true
	_drain_timer = 0.0
	current_tray.locked = true
	print("[Extractor] Draining started into tray: ", current_tray.name)


func _finish_drain() -> void:
	is_draining = false

	if current_tray and not pending_batches.is_empty():
		var product: Recipe = pending_batches.pop_front()
		current_tray.load_product(product)
		print("[Extractor] Tray filled with: ", product.recipe_name, " quality=", product.purity)

	if current_tray:
		current_tray.locked = false
	current_tray = null

	_sync_display()


## ── Tablet sync ──────────────────────────────────────────────────────────
func _sync_display() -> void:
	print("[Extractor] _sync_display: name_tablet assigned=", name_tablet != null, " quality_tablet assigned=", quality_tablet != null, " batch=", current_batch_name, " quality=", current_batch_quality, " pending=", pending_batches.size())
	if name_tablet:
		name_tablet.update_display.rpc(current_batch_name, pending_batches.size())
	else:
		print("[Extractor] WARNING: name_tablet is not assigned in the Inspector")
	if quality_tablet:
		quality_tablet.update_quality.rpc(current_batch_quality)
	else:
		print("[Extractor] WARNING: quality_tablet is not assigned in the Inspector")
