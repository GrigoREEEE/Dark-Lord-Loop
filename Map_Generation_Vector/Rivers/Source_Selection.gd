class_name Source_Selection

#func select_river_source(
	#map_data: Dictionary, 
	#ocean_mask: Dictionary, 
	#width: int, 
	#boundaries: Dictionary[String, int],
	#noise_seed : int,
	#elevation_power: float = 5.0,
#) -> Vector2:
	#var min_y: int = boundaries["min_y"]
	#var max_y: int = boundaries["max_y"]
	#var min_x: int = boundaries["min_x"]
	#var max_x: int = boundaries["max_x"]

# Selects a river source within a specific latitude band (Y-coordinates).
# - min_y, max_y: The band limits on the map grid.
# - elevation_power: Higher values make mountains exponentially more likely to be chosen.
func select_river_source(
	map_data: Dictionary, 
	ocean_mask: Dictionary, 
	width: int, 
	min_y: int,
	max_y: int,
	noise_seed : int,
	elevation_power: float = 5.0,
) -> Vector2:
	var valid_cells = []
	var total_weight: float = 0.0
	
	# --- 1. COLLECT CELLS & CALCULATE WEIGHTS ---
	for y in range(min_y, max_y + 1):
		for x in range(width):
			var pos = Vector2(x, y)
			
			# Check 1: Must not be ocean
			if ocean_mask.get(pos, false) == true:
				continue
				
			# Check 2: Must exist in map data
			if not map_data.has(pos):
				continue
				
			var elevation = map_data[pos]
			
			# Optional Check 3: Prevent rivers from spawning directly on the beach/marsh
			if elevation < 0.2:
				continue
				
			# Calculate Weight
			# Using pow() creates a stark contrast. 
			# e.g., Elevation 0.8^3 = 0.512 weight. Elevation 0.3^3 = 0.027 weight.
			var weight = pow(max(0.0, elevation), elevation_power)
			
			valid_cells.append({ "pos": pos, "weight": weight })
			total_weight += weight
			
	# Fallback if the entire band is ocean or invalid
	if valid_cells.is_empty():
		push_warning("No valid land found in the specified latitude band!")
		return Vector2(width / 2.0, (min_y + max_y) / 2.0)
		
	# --- 2. ROULETTE WHEEL SELECTION ---
	var rng = RandomNumberGenerator.new()
	rng.seed = noise_seed
	
	# "Spin the wheel"
	var spin = rng.randf_range(0.0, total_weight)
	var current_sum = 0.0
	
	# Find where the wheel stopped
	for cell in valid_cells:
		current_sum += cell.weight
		if current_sum >= spin:
			return cell.pos
			
	# Fallback for floating-point inaccuracies
	return valid_cells.back().pos
