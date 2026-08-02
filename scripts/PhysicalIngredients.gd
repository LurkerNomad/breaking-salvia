# This class tells a specific 3D item that it is associated with a specific ingredient.
# Also handles server-authoritative pickup / carry / throw networking.
class_name PhysicalIngredient
extends RigidBody3D

signal picked_up(by_peer_id: int)
signal dropped
signal thrown

@export var ingredient_type: Ingredient
@export var carry_distance: float = 4.0     # how far in front of the camera it sits
@export var throw_force: float = 12.0

## How "loosely" the item chases the carry point — higher = snappier/stiffer,
## lower = more lag/sway. This is a proportional velocity controller, not a
## hard position lock, so the item still collides normally with the world
## while held (walls, other objects) instead of passing through everything.
@export var carry_follow_strength: float = 100.0
@export var carry_max_speed: float = 100.0
## If something blocks the item hard enough that it falls this far behind
## the target carry position, it auto-drops instead of clipping/fighting
## physics forever (e.g. wedged against a doorframe or another object).
@export var carry_max_deviation: float = 4.0

## Which collision bit represents PLAYER bodies. While carried, we only strip
## THIS bit from collision_mask — not the whole layer/mask — so the item
## stops physically shoving the carrying player around, but keeps colliding
## with walls/windows (no tunneling through geometry while held) AND stays
## detectable by Area3Ds (hose connect points, machine sockets) so docking
## works while still carrying the item, not just after dropping it.
## Set this to match whatever layer bit your Player's CharacterBody3D uses.
@export_flags_3d_physics var player_collision_mask_bit: int = 2

var holder_id: int = -1          # -1 = nobody holding it
var _held_node: Node3D = null    # the camera/attach node currently holding this, if any

var _orig_collision_layer: int = 0
var _orig_collision_mask: int = 0


func _ready() -> void:
	# Server owns physics truth for every ingredient; clients just display
	# whatever the server broadcasts. Same pattern as Player.gd authority.
	set_multiplayer_authority(1)  # 1 = server
	if not multiplayer.is_server():
		freeze = true


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return

	if holder_id != -1 and is_instance_valid(_held_node):
		var target_pos: Vector3 = _held_node.global_transform * Vector3(0, 0, -carry_distance)
		var to_target := target_pos - global_position
		var dist := to_target.length()

		if dist > carry_max_deviation:
			# Something's blocking it hard enough that it can't keep up with
			# the carry point — auto-drop rather than fighting physics or
			# clipping through whatever's in the way.
			print("[PhysicalIngredient] ", name, " blocked while carried (", dist, "m behind target) — auto-dropping")
			request_drop()
		else:
			var desired_velocity := to_target * carry_follow_strength
			if desired_velocity.length() > carry_max_speed:
				desired_velocity = desired_velocity.normalized() * carry_max_speed
			linear_velocity = desired_velocity

			# Rotate toward the holder's facing the same way — via angular
			# velocity, not a hard rotation set, so it still responds to
			# collisions rather than clipping through geometry to match angle.
			var target_quat := _held_node.global_transform.basis.get_rotation_quaternion()
			var current_quat := global_transform.basis.get_rotation_quaternion()
			var diff_quat := target_quat * current_quat.inverse()
			var angle := diff_quat.get_angle()
			if angle > 0.01:
				angular_velocity = diff_quat.get_axis() * angle * carry_follow_strength
			else:
				angular_velocity = Vector3.ZERO

	_sync_transform.rpc(global_position, global_rotation)


## ── Called by a Player (via server RPC) to change holder state ─────────────
func request_pickup(requester_id: int, requester_node: Node3D) -> void:
	if not multiplayer.is_server():
		push_error("PhysicalIngredient.request_pickup must be called on the server")
		return
	if holder_id != -1:
		return
	holder_id = requester_id
	_held_node = requester_node
	# NOT frozen — stays a real dynamic body so it can be velocity-driven
	# toward the carry point (see _physics_process) and still collide with
	# the world instead of passing through everything while held.

	# Keep collision_layer UNTOUCHED — Area3Ds detect this item by checking
	# their monitor mask against this item's layer, so zeroing it (as before)
	# silently broke hose docking and machine socket detection while carried.
	# Only strip the player bit from the MASK so it stops solid-colliding
	# with whoever's carrying it, while still colliding with walls/windows.
	_orig_collision_layer = collision_layer
	_orig_collision_mask = collision_mask
	collision_mask = collision_mask & ~player_collision_mask_bit

	_confirm_pickup.rpc(requester_id, collision_layer, collision_mask)


func request_drop() -> void:
	if not multiplayer.is_server():
		return
	if holder_id == -1:
		return
	var prev_holder := holder_id   # capture BEFORE resetting — see note on _confirm_drop
	holder_id = -1
	_held_node = null
	freeze = false
	collision_layer = _orig_collision_layer
	collision_mask = _orig_collision_mask
	_confirm_drop.rpc(prev_holder, collision_layer, collision_mask)


func request_throw(from_node: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if holder_id == -1:
		return
	var dir := -from_node.global_transform.basis.z
	var prev_holder := holder_id   # capture BEFORE resetting — see note on _confirm_throw
	holder_id = -1
	_held_node = null
	freeze = false
	collision_layer = _orig_collision_layer
	collision_mask = _orig_collision_mask
	linear_velocity = dir * throw_force
	_confirm_throw.rpc(prev_holder, global_position, dir * throw_force, collision_layer, collision_mask)


## Called by the holder's Player script when they scroll to adjust distance.
## requester_id must match current holder_id or the request is ignored — this
## keeps randoms from adjusting an item they're not holding.
func set_carry_distance(requester_id: int, new_distance: float) -> void:
	if not multiplayer.is_server():
		return
	if holder_id != requester_id:
		return
	carry_distance = clamp(new_distance, 0.75, 4.0)
	_sync_carry_distance.rpc(carry_distance)


## ── RPCs: server → everyone ─────────────────────────────────────────────────
@rpc("authority", "call_local", "reliable")
func _confirm_pickup(by_peer_id: int, new_layer: int, new_mask: int) -> void:
	holder_id = by_peer_id
	collision_layer = new_layer
	collision_mask = new_mask
	picked_up.emit(by_peer_id)
	_set_holder_tracking(by_peer_id, self)


@rpc("authority", "call_local", "reliable")
func _confirm_drop(prev_holder: int, new_layer: int, new_mask: int) -> void:
	holder_id = -1
	collision_layer = new_layer
	collision_mask = new_mask
	dropped.emit()
	_set_holder_tracking(prev_holder, null)


@rpc("authority", "call_local", "reliable")
func _confirm_throw(prev_holder: int, pos: Vector3, velocity: Vector3, new_layer: int, new_mask: int) -> void:
	holder_id = -1
	global_position = pos
	collision_layer = new_layer
	collision_mask = new_mask
	if multiplayer.is_server():
		linear_velocity = velocity
	thrown.emit()
	_set_holder_tracking(prev_holder, null)


## Runs identically on every peer (this RPC is call_local) so each peer's own
## Player node gets its held_item kept in sync without needing manual signal
## wiring at the call site.
func _set_holder_tracking(peer_id: int, item_or_null) -> void:
	if peer_id == -1:
		return
	var player := get_tree().root.get_node_or_null("World/" + str(peer_id))
	if player and "held_item" in player:
		player.held_item = item_or_null


@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_transform(pos: Vector3, rot: Vector3) -> void:
	if multiplayer.is_server():
		return
	global_position = pos
	global_rotation = rot


@rpc("authority", "call_remote", "reliable")
func _sync_carry_distance(new_distance: float) -> void:
	carry_distance = new_distance


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# If the item gets queue_free'd while held, reset player holder tracking
		if holder_id != -1:
			_set_holder_tracking(holder_id, null)


## Server-authoritative despawn trigger
func request_despawn() -> void:
	print("[PhysicalIngredient] request_despawn called on ", name)

	if not multiplayer.is_server():
		print("[PhysicalIngredient] Not server")
		return

	_despawn.rpc()


@rpc("authority", "call_local", "reliable")
func _despawn() -> void:
	if holder_id != -1:
		_set_holder_tracking(holder_id, null)
		holder_id = -1
	queue_free()
