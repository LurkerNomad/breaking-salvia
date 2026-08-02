extends CharacterBody3D

const SPEED      = 10.0
const JUMP_FORCE = 5.0
const GRAVITY    = 9.8
const MOUSE_SENS = 0.002

@onready var head      : Node3D           = $Head
@onready var camera    : Camera3D         = $Head/Camera3D
@onready var body      : MeshInstance3D   = $BodyMesh
@onready var col_shape : CollisionShape3D = $CollisionShape3D
@onready var interact_ray : RayCast3D     = $Head/Camera3D/RayCast3D

var char_type           := ""
var _is_local           := false
var _target_pos         := Vector3.ZERO
var _target_body_rot_y  := 0.0          # ← new: left/right yaw
var _target_head_rot    := Vector3.ZERO

const INTERACT_RANGE := 3.0
var held_item: PhysicalIngredient = null   # locally tracked for UI purposes only; truth lives on the server


func _ready():
	_is_local = (name == str(multiplayer.get_unique_id()))

	if _is_local:
		set_multiplayer_authority(multiplayer.get_unique_id())
		camera.current = true
		body.visible   = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.current     = false
		body.visible       = true
		col_shape.disabled = true
		set_physics_process(false)
		_target_pos        = position
		_target_body_rot_y = rotation.y
		_target_head_rot   = head.rotation

	# Deferred so the rest of the scene (Furnace, Mixer, their tablets) has
	# finished _ready() before we scan for them.
	call_deferred("_cache_tablets")


func apply_character(type: String) -> void:
	char_type = type

	var old := get_node_or_null("CharacterModel")
	if old:
		old.queue_free()

	body.visible = false

	var scene_path := ""
	var model_scale := 1.0

	match type:
		"themanager":
			scene_path  = "res://Models/WalterWhite/WalterWhite.glb"
			model_scale = 1.0
		"theworker":
			scene_path  = "res://Models/Mike/Mike.glb"
			model_scale = 1.0
		"thejake":
			scene_path  = "res://Models/JakeTheDog/JakeTheDog.glb"
			model_scale = 6.0
		_:
			body.visible = not _is_local
			return
			
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("Could not load model: " + scene_path)
		body.visible = not _is_local
		return

	var model := packed.instantiate()
	model.name    = "CharacterModel"
	model.scale   = Vector3.ONE * model_scale
	model.visible = not _is_local
	add_child(model)

	if type == "themanager":
		model.position.y        = -0.7
		model.rotation_degrees.y = 180.0
	if type == "theworker":
		model.position.y        = -0.7
		model.rotation_degrees.y = 180.0
	if type == "thejake":
		model.position.y        = -0.7
		model.rotation_degrees.y = 180.0

func _process(delta):
	if _is_local:
		return
	position   = position.lerp(_target_pos, delta * 20.0)
	rotation.y = lerp_angle(rotation.y, _target_body_rot_y, delta * 20.0)  # ← yaw
	head.rotation = head.rotation.lerp(_target_head_rot, delta * 20.0)


func _unhandled_input(event):
	if not is_multiplayer_authority():
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		head.rotate_x(-event.relative.y * MOUSE_SENS)
		head.rotation.x = clamp(head.rotation.x, -PI / 2.2, PI / 2.2)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# _input runs BEFORE GUI Controls get a chance to consume the event, unlike
# _unhandled_input (which only fires for events the GUI didn't eat first).
# Interact/throw/scroll live here so a full-rect Control (e.g. your
# VirtualJoystick or Crossair overlay) can't silently swallow them.
func _input(event):
	if not is_multiplayer_authority():
		return

	if event.is_action_pressed("interact"):
		if _try_interact_button():
			pass  # handled — a tablet button consumed this press
		elif held_item:
			_do_drop()
		else:
			_try_pickup()

	if event.is_action_pressed("throw"):
		if held_item:
			_do_throw()

	if event.is_action_pressed("open_valve"):
		_try_toggle_valve()

	if held_item and event is InputEventMouseButton and event.pressed:
		var step := 0.0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step = 0.25
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step = -0.25
		if step != 0.0:
			var new_dist: float = held_item.carry_distance + step
			if multiplayer.is_server():
				held_item.set_carry_distance(int(name), new_dist)
			else:
				_request_carry_distance.rpc_id(1, held_item.get_path(), new_dist)


func _physics_process(delta):
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var dir  := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move := (transform.basis * Vector3(dir.x, 0, dir.y)).normalized()
	velocity.x = move.x * SPEED
	velocity.z = move.z * SPEED

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_FORCE

	move_and_slide()
	_sync_state.rpc(position, rotation.y, head.rotation)  # ← added rotation.y


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _sync_state(pos: Vector3, body_rot_y: float, head_rot: Vector3):  # ← added body_rot_y
	_target_pos        = pos
	_target_body_rot_y = body_rot_y
	_target_head_rot   = head_rot


# ─────────────────────────────────────────────────────────────────────────────
# Pickup / carry / throw
# Client raycasts locally to find the candidate (cheap, instant feedback),
# then asks the server to actually grant the pickup. Server has final say.
# ─────────────────────────────────────────────────────────────────────────────
## Toggles a fuel canister's valve. Bound to its own "open_valve" input
## action (e.g. M) rather than overloaded onto "interact" — requires
## RayCast3D's "Collide With Areas" enabled in the Inspector, since valve
## areas are Area3D, not PhysicalIngredient.
func _try_toggle_valve() -> void:
	if not interact_ray.is_colliding():
		print("[Valve] Ray not colliding with anything")
		return
	var candidate = interact_ray.get_collider()
	print("[Valve] Ray hit: ", candidate.name if candidate is Node else candidate, " (", candidate.get_class(), ") is_area3d=", candidate is Area3D, " groups=", candidate.get_groups() if candidate is Node else "n/a")

	if not (candidate is Area3D and candidate.is_in_group("fuel_valve")):
		print("[Valve] Not a fuel_valve Area3D — ignoring")
		return

	var valve_area := candidate as Area3D
	var canister := valve_area.get_parent()
	print("[Valve] Parent node: ", canister.name if canister else "null", " has toggle_valve=", canister.has_method("toggle_valve") if canister else false)

	if canister == null or not canister.has_method("toggle_valve"):
		print("[Valve] No valid canister parent with toggle_valve() — aborting")
		return

	print("[Valve] Sending toggle request. is_server=", multiplayer.is_server())
	if multiplayer.is_server():
		canister.toggle_valve(int(name))
	else:
		_request_valve_toggle.rpc_id(1, canister.get_path())


func _try_pickup() -> void:
	if not interact_ray.is_colliding():
		return
	var candidate = interact_ray.get_collider()

	# A HoseEnd's own connect_area (Area3D, used for auto-docking) often sits
	# right on/around the hose end and can intercept the raycast before it
	# reaches the actual RigidBody3D — especially now that "Collide With
	# Areas" is enabled on this ray for valve support. If that's what we hit,
	# redirect the pickup target to the HoseEnd itself.
	if candidate is Area3D:
		var maybe_owner = candidate.get_parent()
		if maybe_owner is HoseEnd and maybe_owner.connect_area == candidate:
			candidate = maybe_owner

	if not (candidate is PhysicalIngredient):
		return

	if multiplayer.is_server():
		# We ARE the server (host) — run the logic directly. Calling an
		# "any_peer"/"call_remote" RPC targeting ourselves is illegal in Godot,
		# so hosts must never rpc_id(1, ...) to themselves.
		_do_pickup(int(name), candidate)
	else:
		_request_pickup.rpc_id(1, candidate.get_path())


## Checks whether the raycast is currently aiming at a physical button
## Checks whether the raycast is aiming at any node tagged into a "*_button"
## group. If so, broadcasts the click to every known tablet (see
## _cache_tablets) — each tablet's own handle_ray_interaction() already
## checks group membership internally, so only the one that actually owns
## this button will act; the rest silently no-op. This avoids assuming any
## particular scene hierarchy between a button and its tablet.
func _try_interact_button() -> bool:
	if not interact_ray.is_colliding():
		return false
	var candidate = interact_ray.get_collider()
	if not (candidate is Node):
		return false

	var is_button := false
	for g in candidate.get_groups():
		if String(g).ends_with("_button"):
			is_button = true
			break
	if not is_button:
		return false

	var hit_point := interact_ray.get_collision_point()
	if multiplayer.is_server():
		_broadcast_to_tablets(candidate, hit_point)
	else:
		_request_tablet_interaction.rpc_id(1, candidate.get_path(), hit_point)
	return true


## Scans the WHOLE scene tree once (deferred, after everything's _ready())
## for any node with a handle_ray_interaction method — MixerTablet,
## FurnaceTablet, future ones too. No hierarchy assumption: buttons don't
## need to be children of their tablet.
var _tablets_cache: Array = []

func _cache_tablets() -> void:
	_tablets_cache.clear()
	var root := get_tree().current_scene
	if root:
		_collect_tablets(root)
	print("[Interact] Cached ", _tablets_cache.size(), " tablet(s): ", _tablets_cache.map(func(t): return t.name))


func _collect_tablets(node: Node) -> void:
	if node.has_method("handle_ray_interaction"):
		_tablets_cache.append(node)
	for child in node.get_children():
		_collect_tablets(child)


func _broadcast_to_tablets(collider: Node, hit_point: Vector3) -> void:
	for tablet in _tablets_cache:
		if is_instance_valid(tablet):
			tablet.handle_ray_interaction(collider, hit_point, true, 0.0)


@rpc("any_peer", "call_remote", "reliable")
func _request_tablet_interaction(collider_path: NodePath, hit_point: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var collider: Node = get_node_or_null(collider_path)
	if collider:
		_broadcast_to_tablets(collider, hit_point)


func _do_drop() -> void:
	if multiplayer.is_server():
		if held_item:
			held_item.request_drop()
	else:
		_request_drop.rpc_id(1)


func _do_throw() -> void:
	if multiplayer.is_server():
		if held_item:
			held_item.request_throw(self)
	else:
		_request_throw.rpc_id(1)


## Shared pickup logic — called either directly (host) or from the RPC below (clients).
func _do_pickup(requester_id: int, item: PhysicalIngredient) -> void:
	var requester := get_tree().root.get_node_or_null("World/" + str(requester_id)) as Node3D
	if requester == null:
		return
	if requester.global_position.distance_to(item.global_position) > INTERACT_RANGE * 1.5:
		return
	# Attach to the CAMERA, not the player root — the root only tracks yaw,
	# so carrying relative to it ignored up/down look and floated in the
	# wrong spot. The camera transform includes head pitch too.
	var attach_node := requester.get_node_or_null("Head/Camera3D") as Node3D
	if attach_node == null:
		attach_node = requester  # fallback, shouldn't normally happen
	item.request_pickup(requester_id, attach_node)


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup(item_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var requester_id := multiplayer.get_remote_sender_id()
	var item := get_node_or_null(item_path) as PhysicalIngredient
	if item == null:
		return
	_do_pickup(requester_id, item)


@rpc("any_peer", "call_remote", "reliable")
func _request_drop() -> void:
	if not multiplayer.is_server():
		return
	if held_item:
		held_item.request_drop()


@rpc("any_peer", "call_remote", "reliable")
func _request_throw() -> void:
	if not multiplayer.is_server():
		return
	if held_item:
		held_item.request_throw(self)


@rpc("any_peer", "call_remote", "reliable")
func _request_carry_distance(item_path: NodePath, new_distance: float) -> void:
	if not multiplayer.is_server():
		return
	var requester_id := multiplayer.get_remote_sender_id()
	var item := get_node_or_null(item_path) as PhysicalIngredient
	if item == null:
		return
	item.set_carry_distance(requester_id, new_distance)


@rpc("any_peer", "call_remote", "reliable")
func _request_valve_toggle(canister_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var requester_id := multiplayer.get_remote_sender_id()
	var canister: Node = get_node_or_null(canister_path)
	if canister and canister.has_method("toggle_valve"):
		canister.toggle_valve(requester_id)


# held_item is now kept in sync automatically by PhysicalIngredient's
# _set_holder_tracking (called from its call_local confirm RPCs) — no manual
# signal wiring needed here.
