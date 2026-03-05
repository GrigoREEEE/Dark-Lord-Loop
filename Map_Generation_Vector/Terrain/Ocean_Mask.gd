extends Node
class_name Ocean_Identification


########################################
######## Water Identification ##########
########################################

# Returns a Dictionary where Key = Vector2(x,y) and Value = bool (True if Ocean, False if Land/Inland)
# Also populates the passed-in ocean_pool's all_cells array.
func ocean_vs_land(
	map_data: Dictionary, 
	width: int, 
	height: int, 
	ocean_pool: Pool, 
	water_level: float = 0.15
) -> Dictionary[Vector2, bool]:
	
	var is_ocean_map: Dictionary[Vector2, bool] = {}
	var open_set: Array[Vector2] = [] 
	
	# --- STEP 1: INITIALIZE DICTIONARY ---
	# We default everything to FALSE (Land) initially.
	for pos: Vector2 in map_data:
		is_ocean_map[pos] = false

	# --- STEP 2: SEED THE OCEAN FROM BORDERS ---
	# Check Top/Bottom edges
	for x in range(width):
		_check_ocean_seed(x, 0, map_data, water_level, open_set, is_ocean_map, ocean_pool)
		_check_ocean_seed(x, height - 1, map_data, water_level, open_set, is_ocean_map, ocean_pool)
		
	# Check Left/Right edges
	for y in range(height):
		_check_ocean_seed(0, y, map_data, water_level, open_set, is_ocean_map, ocean_pool)
		_check_ocean_seed(width - 1, y, map_data, water_level, open_set, is_ocean_map, ocean_pool)
	
	# --- STEP 3: FLOOD FILL (8-Way) ---
	var directions: Array[Vector2] = [
		Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0),
		Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)
	]
	
	while open_set.size() > 0:
		var current: Vector2 = open_set.pop_back()
		
		for d in directions:
			var neighbor: Vector2 = current + d
			
			if map_data.has(neighbor):
				# If neighbor is below water level AND not yet marked as ocean
				if map_data[neighbor] < water_level and is_ocean_map[neighbor] == false:
					is_ocean_map[neighbor] = true
					ocean_pool.all_cells.append(neighbor)
					open_set.append(neighbor)
					
	return is_ocean_map

# Helper to check borders
func _check_ocean_seed(
	x: int, 
	y: int, 
	map_data: Dictionary, 
	lvl: float, 
	queue: Array[Vector2], 
	ocean_map: Dictionary[Vector2, bool], 
	ocean_pool: Pool
):
	var pos := Vector2(x, y)
	if map_data.has(pos) and map_data[pos] < lvl:
		if ocean_map[pos] == false:
			ocean_map[pos] = true
			ocean_pool.all_cells.append(pos)
			queue.append(pos)
