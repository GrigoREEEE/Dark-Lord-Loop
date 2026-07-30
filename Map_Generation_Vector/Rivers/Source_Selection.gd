class_name Source_Selection

# Selects a river source within a specific 2D grid cell.
# - min_x, max_x, min_y, max_y: The boundaries of the cell on the map grid.
# - elevation_power: Higher values make the top end of the valid range exponentially more likely.
func select_river_source(
	world_data: World_Data,
	cell_data: Dictionary[String, int],
	elevation_power: float = 5.0
) -> Vector2:
	var noise_seed: int = world_data.noise_seed
	var terrain: Dictionary = world_data.map_data["terrain"]
	var ocean_mask: Dictionary = world_data.mask_data["ocean"]
	var min_x: int = cell_data["start_x"]
	var max_x: int = cell_data["end_x"]
	var min_y: int = cell_data["start_y"]
	var max_y: int = cell_data["end_y"]
	var valid_cells: Array[Dictionary] = []
	var total_weight: float = 0.0
	
	# --- 1. COLLECT CELLS & CALCULATE WEIGHTS ---
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var pos := Vector2(x, y)
			
			# Check 1: Must not be ocean
			if ocean_mask.has(pos):
				continue
				
			# Check 2: Must exist in map cell_data
			if not terrain.has(pos):
				continue
				
			var elevation: float = terrain[pos]
			
			# Check 3: Prevent rivers from spawning directly on the beach/marsh
			if elevation < 0.2:
				continue
				
			# Check 4: Hard cutoff — never start higher than 0.8
			if elevation > 0.8:
				continue
				
			# Calculate Weight
			# Normalize the elevation to scale cleanly from 0.0 to 1.0 within our allowed range.
			# This ensures the elevation_power exponentially favors the 0.5 to 0.8 sweet spot
			# while severely penalizing the 0.2 to 0.4 range.
			var normalized_elevation: float = (elevation - 0.2) / (0.8 - 0.2)
			var weight: float = pow(max(0.0, normalized_elevation), elevation_power)
			
			valid_cells.append({ "pos": pos, "weight": weight })
			total_weight += weight
			
	# Fallback if the entire cell is ocean or invalid
	if valid_cells.is_empty():
		push_warning("No valid land found in the specified map cell!")
		return Vector2((min_x + max_x) / 2.0, (min_y + max_y) / 2.0)
		
	# --- 2. ROULETTE WHEEL SELECTION ---
	var rng = RandomNumberGenerator.new()
	rng.seed = noise_seed
	
	# "Spin the wheel"
	var spin: float = rng.randf_range(0.0, total_weight)
	var current_sum: float = 0.0
	
	# Find where the wheel stopped
	for cell in valid_cells:
		current_sum += cell.weight
		if current_sum >= spin:
			return cell.pos
			
	# Fallback for floating-point inaccuracies
	return valid_cells.back().pos
