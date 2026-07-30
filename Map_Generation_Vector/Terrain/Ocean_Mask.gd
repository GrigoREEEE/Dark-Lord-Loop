extends Node
class_name Ocean_Identification


########################################
######## Water Identification ##########
########################################

# Returns a Dictionary where Key = Vector2(x,y) and Value = bool (True if Ocean, False if Land/Inland)
# Also populates the passed-in ocean_pool's all_cells array.
func ocean_vs_land2(
	terrain: Dictionary, 
	width: int, 
	height: int, 
	ocean_pool: Water_Pool, 
	water_level: float = 0.15
) -> Dictionary[Vector2, bool]:
	
	var is_ocean_map: Dictionary[Vector2, bool] = {}
	var open_set: Array[Vector2] = [] 
	
	# --- STEP 1: INITIALIZE DICTIONARY ---
	# We default everything to FALSE (Land) initially.
	for pos: Vector2 in terrain:
		is_ocean_map[pos] = false

	# --- STEP 2: SEED THE OCEAN FROM BORDERS ---
	# Check Top/Bottom edges
	for x in range(width):
		_check_ocean_seed(x, 0, terrain, water_level, open_set, is_ocean_map, ocean_pool)
		_check_ocean_seed(x, height - 1, terrain, water_level, open_set, is_ocean_map, ocean_pool)
		
	# Check Left/Right edges
	for y in range(height):
		_check_ocean_seed(0, y, terrain, water_level, open_set, is_ocean_map, ocean_pool)
		_check_ocean_seed(width - 1, y, terrain, water_level, open_set, is_ocean_map, ocean_pool)
	
	# --- STEP 3: FLOOD FILL (8-Way) ---
	var directions: Array[Vector2] = [
		Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0),
		Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)
	]
	
	while open_set.size() > 0:
		var current: Vector2 = open_set.pop_back()
		
		for d in directions:
			var neighbor: Vector2 = current + d
			
			if terrain.has(neighbor):
				# If neighbor is below water level AND not yet marked as ocean
				if terrain[neighbor] < water_level and is_ocean_map[neighbor] == false:
					is_ocean_map[neighbor] = true
					ocean_pool.all_cells.append(neighbor)
					open_set.append(neighbor)
					
	return is_ocean_map

# Helper to check borders
func _check_ocean_seed(
	x: int, 
	y: int, 
	terrain: Dictionary, 
	lvl: float, 
	queue: Array[Vector2], 
	ocean_map: Dictionary[Vector2, bool], 
	ocean_pool: Water_Pool
):
	var pos := Vector2(x, y)
	if terrain.has(pos) and terrain[pos] < lvl:
		if ocean_map[pos] == false:
			ocean_map[pos] = true
			ocean_pool.all_cells.append(pos)
			queue.append(pos)
			
########################################
######## Water Identification ##########
########################################

# Returns a Dictionary where Key = Vector2(x,y) and Value = true (Only contains Ocean cells)
# Also populates the passed-in ocean_pool's all_cells array.
func ocean_vs_land(
	world_data: World_Data,
	water_level: float = 0.15
) -> void:
	
	var terrain: Dictionary = world_data.map_data["terrain"]
	var width: int = world_data.grid_width
	var height: int = world_data.grid_height
	var ocean_pool: Water_Pool = world_data.ocean
	var is_ocean_map: Dictionary[Vector2, bool] = {} 
	var open_set: Array[Vector2] = [] 
	
	# --- OPTIMIZATION 1: SINGLE SEED ---
	# Since the ocean is guaranteed to be united, we only need to drop one "bucket of paint"
	# at the absolute bottom-right corner of the map grid.
	var seed_pos := Vector2(width - 1, height - 1)
	
	# Verify the seed is actually underwater just to be safe
	if terrain.get(seed_pos, 999.0) < water_level:
		is_ocean_map[seed_pos] = true
		ocean_pool.all_cells.append(seed_pos)
		open_set.append(seed_pos)
	else:
		push_warning("Ocean seed point is not underwater! Check your terrain generation.")

	# --- OPTIMIZATION 2: 4-WAY FLOOD FILL ---
	# Cuts the loop iterations exactly in half compared to 8-way.
	var directions: Array[Vector2] = [
		Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)
	]
	
	# --- STEP 3: EXECUTE FLOOD FILL ---
	while open_set.size() > 0:
		var current: Vector2 = open_set.pop_back()
		
		for d in directions:
			var neighbor: Vector2 = current + d
			
			# If we already marked it as ocean, skip it instantly.
			# Because we use a Sparse Dictionary, we only check .has()
			if is_ocean_map.has(neighbor):
				continue
				
			# --- OPTIMIZATION 3: COMBINED LOOKUP ---
			# We use .get(neighbor, 999.0). If the neighbor is out of bounds or missing 
			# from terrain, it returns 999.0 (a mountain), which fails the < water_level check automatically.
			if terrain.get(neighbor, 999.0) < water_level:
				is_ocean_map[neighbor] = true
				ocean_pool.all_cells.append(neighbor)
				open_set.append(neighbor)
					
	world_data.mask_data["ocean"] = is_ocean_map
