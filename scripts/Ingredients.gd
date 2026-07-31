#This script defines the ingredients used for the recipes in the game.
class_name Ingredient
extends Resource

@export var item_name: String =""

#This holds the specific physical item associated with the ingredient.
#@export var physical_scene: PackedScene

#This assigns a price for each ingredient
@export var price: int = 0
