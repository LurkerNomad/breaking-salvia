## A physics hammer. Pickupable/carryable/throwable like any PhysicalIngredient.
## Its head (a child Area3D) registers a "hit" whenever it contacts a Tray
## holding a frozen, unbroken product — 3 hits and it's broken, ready for
## packaging (packaging itself comes later).
class_name Hammer
extends PhysicalIngredient

@export var hammer_head: Area3D    # child Area3D on the striking end
@export var hit_cooldown: float = 0.4   # prevents one continuous overlap from counting as many hits

var _cooldown_timer: float = 0.0


func _ready() -> void:
	super._ready()
	if hammer_head:
		hammer_head.body_entered.connect(_on_head_contact)


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func _on_head_contact(body: Node) -> void:
	if not multiplayer.is_server():
		return
	if _cooldown_timer > 0.0:
		return
	if not (body is Tray):
		return

	var tray := body as Tray
	var recipe := tray.held_recipe
	if recipe == null:
		return
	if not recipe.frozen:
		print("[Hammer] Tray isn't frozen yet — nothing to break")
		return
	if recipe.broken:
		return  # already fully broken

	_cooldown_timer = hit_cooldown
	recipe.hits_left = max(0, recipe.hits_left - 1)
	print("[Hammer] Hit tray: ", tray.name, " — ", recipe.hits_left, " hits left")

	if recipe.hits_left <= 0:
		recipe.broken = true
		print("[Hammer] Tray broken and ready for packaging: ", tray.name)
