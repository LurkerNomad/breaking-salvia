class_name Recipe
extends Resource

@export var recipe_name: String = ""

@export var recipe_icon: Texture2D

# Structură: {"NumeIngredient": CantitateInt}
# Exemplu: {"Salvia": 3, "Mint": 2, "Water": 1}
@export var required_ingredients: Dictionary = {}

@export var cook_time: int = 0
@export var temperature: int = 0
@export var pressure: int = 0

# Purity are valoarea implicită 1.0 (float)
@export var purity: float = 1.0

# Funcție care calculează automat toate prețurile rețetei
func calculate_prices(ingredient_resources: Array[Ingredient]) -> Dictionary:
	if recipe_name == "Useless Garbage":
		return {
			"total_ingredients_price": 0,
			"base_price": 0.0,
			"final_price": 0.0
		}
	
	var total_ingredients_price: int = 0
	
	# 1. Calculăm prețul total al ingredientelor folosite
	for item_name in required_ingredients.keys():
		var count: int = required_ingredients[item_name]
		var found_price: int = 0
		
		# Căutăm resursa ingredientului pentru a-i afla prețul unitar
		for ing in ingredient_resources:
			if ing.item_name == item_name:
				found_price = ing.price
				break
				
		total_ingredients_price += found_price * count
		
	# 2. Calculăm base_price (Preț total + 10%)
	var base_price: float = total_ingredients_price + (0.1 * total_ingredients_price)
	
	# 3. Calculăm final_price în funcție de puritate
	var final_price: float = purity * base_price
	
	# Returnăm toate prețurile calculate sub formă de dicționar utilitar
	return {
		"total_ingredients_price": total_ingredients_price,
		"base_price": base_price,
		"final_price": final_price
	}
