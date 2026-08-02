## A tray. Pickupable/carryable/throwable like any PhysicalIngredient — EXCEPT
## while `locked` is true (the extractor's drainer is actively filling it),
## during which it can't be picked up at all.
class_name Tray
extends PhysicalIngredient

@export var product_texture: CSGBox3D   # displays the recipe's icon once filled
@export var detection_area: Area3D      # for slot detection (drainer, freezer, etc) —
										  # separate from the tray's own physical
										  # collision shape, same Area-to-Area
										  # pattern as the hose docking system

var held_recipe: Recipe = null
var locked: bool = false   # true while sitting in the extractor's drainer mid-drain

var _tray_material: StandardMaterial3D


func _ready() -> void:
	super._ready()
	if product_texture:
		# Duplicate the material so setting THIS tray's icon doesn't repaint
		# every other tray sharing the same base material resource.
		var mat := product_texture.material
		if mat is StandardMaterial3D:
			_tray_material = mat.duplicate()
		else:
			_tray_material = StandardMaterial3D.new()
		product_texture.material = _tray_material


func request_pickup(requester_id: int, requester_node: Node3D) -> void:
	if locked:
		return  # can't grab a tray mid-drain
	super.request_pickup(requester_id, requester_node)


## Called by Extractor once a drain cycle finishes.
func load_product(recipe: Recipe) -> void:
	if not multiplayer.is_server():
		return
	held_recipe = recipe
	var icon_path := ""
	if recipe and recipe.recipe_icon:
		icon_path = recipe.recipe_icon.resource_path
	_sync_product.rpc(icon_path)


func clear_product() -> void:
	if not multiplayer.is_server():
		return
	held_recipe = null
	_sync_product.rpc("")


@rpc("authority", "call_local", "reliable")
func _sync_product(icon_path: String) -> void:
	if _tray_material == null:
		return
	if icon_path == "":
		_tray_material.albedo_texture = null
	else:
		_tray_material.albedo_texture = load(icon_path) as Texture2D


## Called by Freezer once a tray finishes its freeze_duration.
func show_frozen_indicator() -> void:
	if not multiplayer.is_server():
		return
	_sync_frozen_visual.rpc(true)


@rpc("authority", "call_local", "reliable")
func _sync_frozen_visual(is_frozen: bool) -> void:
	if _tray_material == null:
		return
	_tray_material.albedo_color = Color(0.6, 1.0, 0.6) if is_frozen else Color(1, 1, 1)
