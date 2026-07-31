#class_name Tray
#extends RigidBody3D
#
## --- Node References (Assign in Inspector) ---
#@export var content_mesh: GeometryInstance3D 
#
## --- Attached Data Variables ---
#var current_batch: Recipe = null 
#var final_price: float = 0.0
#var has_content: bool = false
#
#func _ready() -> void:
	#if content_mesh:
		#content_mesh.visible = false
#
## --- Function to load the cooked batch onto the tray ---
#func load_cooked_batch(cooked_batch_instance: Recipe) -> void:
	#if cooked_batch_instance == null:
		#print("[Tray] Error: Tried to load empty batch data.")
		#return
		#
	## Bind the specific batch instance to this physical tray
	#current_batch = cooked_batch_instance
	#has_content = true
	#
	## DIRECT IMPORT: Pulling the final price directly from the batch resource
	#final_price = current_batch.final_price
	#
	## Update the tray visual appearance using the batch's icon texture
	#if content_mesh and current_batch.recipe_icon:
		#_apply_content_texture(current_batch.recipe_icon)
		#content_mesh.visible = true
		#
	#print("[Tray] Loaded unique batch: ", current_batch.recipe_name)
	#print("[Tray] Imported Price: $", final_price)
#
## --- Helper to create a dynamic material for the content mesh ---
#func _apply_content_texture(texture: Texture2D) -> void:
	#var new_material = StandardMaterial3D.new()
	#new_material.albedo_texture = texture
	#new_material.roughness = 0.2
	#content_mesh.material_override = new_material
