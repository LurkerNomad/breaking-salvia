extends CharacterBody3D

const SPEED      = 10.0
const JUMP_FORCE = 5.0
const GRAVITY    = 9.8
const MOUSE_SENS = 0.002

@onready var head      : Node3D           = $Head
@onready var camera    : Camera3D         = $Head/Camera3D
@onready var body      : MeshInstance3D   = $BodyMesh
@onready var col_shape : CollisionShape3D = $CollisionShape3D

var char_type           := ""
var _is_local           := false
var _target_pos         := Vector3.ZERO
var _target_body_rot_y  := 0.0          # ← new: left/right yaw
var _target_head_rot    := Vector3.ZERO


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
