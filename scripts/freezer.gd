## Freezer: just an Area3D + one button. Button toggles freezing on/off.
## While active, any tray with an unfrozen product sitting in freezing_area
## for freeze_duration seconds (20s) gets marked frozen and shows a green
## tint. Multiple trays can freeze at once, each on their own timer.
class_name Freezer
extends Node3D

@export var freezing_area: Area3D
@export var freeze_duration: float = 20.0

var is_active: bool = false
var _tray_timers: Dictionary = {}   # Tray -> float elapsed


func _ready() -> void:
	if freezing_area:
		# Area-to-Area against the tray's detection_area — same pattern as
		# the drainer.
		freezing_area.area_entered.connect(_on_tray_area_entered)
		freezing_area.area_exited.connect(_on_tray_area_exited)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if not is_active:
		return

	# Iterate a copy of the keys since _freeze_tray() mutates the dict mid-loop.
	for tray in _tray_timers.keys().duplicate():
		if not is_instance_valid(tray):
			_tray_timers.erase(tray)
			continue

		_tray_timers[tray] += delta

		if _tray_timers[tray] >= freeze_duration:
			_freeze_tray(tray)


func _on_tray_area_entered(area: Area3D) -> void:
	if not multiplayer.is_server():
		return
	var tray := area.get_parent()
	if not (tray is Tray):
		return
	if tray.held_recipe == null:
		return  # nothing to freeze
	if tray.held_recipe.frozen:
		return  # already frozen

	_tray_timers[tray] = 0.0
	print("[Freezer] Tray entered: ", tray.name)


func _on_tray_area_exited(area: Area3D) -> void:
	if not multiplayer.is_server():
		return
	var tray := area.get_parent()
	if _tray_timers.has(tray):
		_tray_timers.erase(tray)
		print("[Freezer] Tray left early, progress reset: ", tray.name)


func _freeze_tray(tray: Tray) -> void:
	_tray_timers.erase(tray)
	if tray.held_recipe:
		tray.held_recipe.frozen = true
	tray.show_frozen_indicator()
	print("[Freezer] Frozen: ", tray.name)


## ── Button ───────────────────────────────────────────────────────────────
func handle_ray_interaction(collider: Object, hit_point: Vector3, is_click: bool, scroll_step: float) -> void:
	if not is_click:
		return
	if not collider.is_in_group("freezer_button"):
		return

	if multiplayer.is_server():
		_toggle_active()
	else:
		_request_toggle.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_toggle() -> void:
	if not multiplayer.is_server():
		return
	_toggle_active()


func _toggle_active() -> void:
	is_active = not is_active
	print("[Freezer] ", "Activated" if is_active else "Deactivated")
	if not is_active:
		_tray_timers.clear()  # stop all in-progress freezing when turned off
