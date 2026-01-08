extends Node

class_name WorldGeneratorVector_V2

# CONFIGURATION
@export var noise_seed: int = randi()
const REFERENCE_WIDTH = 400.0
# Update your Enum to include COAST

########################################
########## World Generation ############
########################################

func generate_height_map(width: int, height: int) -> Dictionary:
	var map_data = {}
	
	# 0. CALCULATE RESOLUTION SCALE
	# If width is 400, scale is 2.0. If width is 200, scale is 1.0.
	var res_scale = float(width) / REFERENCE_WIDTH
	
	# --- 1. TERRAIN NOISE ---
	var terrain_noise = FastNoiseLite.new()
	terrain_noise.seed = noise_seed
	terrain_noise.frequency = 0.013 / res_scale
	terrain_noise.fractal_octaves = 6 

	# --- 2. SHAPE NOISE ---
	var shape_noise = FastNoiseLite.new()
	shape_noise.seed = noise_seed + 50
	shape_noise.frequency = 0.005 / res_scale
	shape_noise.fractal_octaves = 3

	# --- PHASE 1: GENERATE CONTINENT ---
	for x in range(width):
		for y in range(height):
			var nx: float = float(x) / width
			var ny: float = float(y) / height
			
			# --- STEP 1: CALCULATE DISTORTED MASK ---
			var current_distortion_strength = lerp(0.15, 0.04, ny)
			var distortion = shape_noise.get_noise_2d(x, y) * current_distortion_strength
			var dist_x = abs(nx - 0.5) + distortion
			var land_width = lerp(0.45, 0.50, ny) 
			var shape_mask = smoothstep(land_width, land_width - 0.15, dist_x)
			
			# --- STEP 2: THE SLANT ---
			var gradient_y = 1.0 - ny
			var slant_height = pow(gradient_y, 1.5)
			
			# --- STEP 3: ELEVATION VARIANCE ---
			var h_noise = terrain_noise.get_noise_2d(x, y)
			var roughness = lerp(1.0, 0.2, ny)
			
			# --- FINAL COMBINATION ---
			var final_elevation = slant_height
			final_elevation += h_noise * roughness
			final_elevation -= (1.0 - shape_mask) * 2.0
			final_elevation = max(final_elevation, -1.0)
			
			map_data[Vector2(x, y)] = final_elevation
			
	# --- PHASE 2: GENERATE SOUTHERN ISLANDS ---
	# We invoke the new function here to inject the islands into the ocean.
	# Params: map_data, width, height, belt_height (pixels), padding (pixels)
	_apply_southern_islands(map_data, width, height, 150, 15, 60, res_scale)
	
	# --- PHASE 3: OVERLAY THE ICE WALL ---
	_apply_ice_wall(map_data, width, res_scale)
	
	return map_data
	
	
func _apply_ice_wall(map_data: Dictionary, width: int, res_scale : float):
	var wall_base_height = int(15 * res_scale)
	var wall_variance = int(10 * res_scale)
	
	# Separate noise for the wall shape (Wobble)
	var wall_shape_noise = FastNoiseLite.new()
	wall_shape_noise.seed = noise_seed + 99
	wall_shape_noise.frequency = 0.02 / res_scale
	
	# Separate noise for the wall texture (Spikes)
	var wall_texture_noise = FastNoiseLite.new()
	wall_texture_noise.seed = noise_seed
	wall_texture_noise.frequency = 0.05 / res_scale
	
	for x in range(width):
		# 1. Determine how tall the wall is at this specific X coordinate
		var wobble = wall_shape_noise.get_noise_2d(x, 0.0) * wall_variance
		var current_wall_height = int(wall_base_height + wobble)
		
		# 2. Overwrite the top pixels with Wall Data
		for y in range(current_wall_height):
			var n = abs(wall_texture_noise.get_noise_2d(x, y))
			
			# Height: 1.2 (Base) + Noise. Guaranteed to be higher than the land.
			var wall_elevation = 1.2 + (n * 0.5)
			
			# This simply overwrites whatever land/ocean was generated there
			map_data[Vector2(x, y)] = wall_elevation

func _apply_southern_islands(map_data: Dictionary, width: int, height: int, belt_height: int, bottom_padding: int, side_padding: int, res_scale : float):
	belt_height = int(belt_height * res_scale)
	bottom_padding = int(bottom_padding * res_scale)
	side_padding = int(side_padding * res_scale)
	
	# 1. NOISE SETUP
	var shape_noise = FastNoiseLite.new()
	shape_noise.seed = noise_seed + 200
	shape_noise.frequency = 0.02 / res_scale
	shape_noise.fractal_octaves = 3 

	var terrain_noise = FastNoiseLite.new()
	terrain_noise.seed = noise_seed
	terrain_noise.frequency = 0.013 / res_scale
	terrain_noise.fractal_octaves = 6
	
	var belt_end_y = height - bottom_padding
	var belt_start_y = belt_end_y - belt_height
	
	# --- CHANGE 1: LOOP THE FULL WIDTH ---
	# We iterate the full width so we can handle the fade logic per-pixel.
	# We rely on math to hide the islands, not the loop range.
	for x in range(width):
		for y in range(belt_start_y, belt_end_y):
			var pos = Vector2(x, y)
			
			# --- CHANGE 2: CALCULATE EDGE FADE ---
			# We measure how close we are to the nearest Left/Right edge.
			var dist_to_edge = min(x, width - x)
			
			# If we are inside the padding zone, this multiplier drops to 0.0.
			# If we are safe inside the map, it is 1.0.
			# We use a smooth transition so it looks like a natural beach slope.
			var edge_fade = smoothstep(0.0, float(side_padding), float(dist_to_edge))
			
			# --- VERTICAL MASK ---
			var belt_progress = float(y - belt_start_y) / float(belt_height)
			var belt_mask = sin(belt_progress * PI)
			
			# --- GENERATE TERRAIN ---
			var base_shape = shape_noise.get_noise_2d(x, y)
			var detail = terrain_noise.get_noise_2d(x, y)
			var elevation = (base_shape * 0.7) + (detail * 0.4)
			
			# Apply Vertical Mask (North/South fade)
			elevation *= belt_mask
			
			# --- CHANGE 3: APPLY EDGE FADE ---
			# This pushes the land underwater as it nears the left/right border.
			elevation *= edge_fade
			
			# Add offset
			elevation += 0.05 * belt_mask
			
			# --- THRESHOLD CHECK ---
			# Only write if it's actually land/beach.
			if elevation > 0.12:
				var existing_height = map_data.get(pos, -1.0)
				map_data[pos] = max(existing_height, elevation)

########################################
######## Water Identification ##########
########################################

# Returns a Dictionary where Key = Vector2(x,y) and Value = bool (True if Ocean, False if Land/Inland)
func ocean_vs_land(map_data: Dictionary, width: int, height: int, water_level: float = 0.15) -> Dictionary:
	var is_ocean_map = {}
	var open_set = [] # Queue for Flood Fill
	
	# --- STEP 1: INITIALIZE DICTIONARY ---
	# We default everything to FALSE (Land) initially.
	for pos in map_data:
		is_ocean_map[pos] = false

	# --- STEP 2: SEED THE OCEAN FROM BORDERS ---
	# Check Top/Bottom edges
	for x in range(width):
		_check_ocean_seed(x, 0, map_data, water_level, open_set, is_ocean_map)
		_check_ocean_seed(x, height - 1, map_data, water_level, open_set, is_ocean_map)
		
	# Check Left/Right edges
	for y in range(height):
		_check_ocean_seed(0, y, map_data, water_level, open_set, is_ocean_map)
		_check_ocean_seed(width - 1, y, map_data, water_level, open_set, is_ocean_map)
	
	# --- STEP 3: FLOOD FILL (8-Way) ---
	var directions = [
		Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0),
		Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)
	]
	
	while open_set.size() > 0:
		var current = open_set.pop_back()
		
		for d in directions:
			var neighbor = current + d
			
			if map_data.has(neighbor):
				# If neighbor is below water level AND not yet marked as ocean
				if map_data[neighbor] < water_level and is_ocean_map[neighbor] == false:
					is_ocean_map[neighbor] = true
					open_set.append(neighbor)
					
	return is_ocean_map

# Helper to check borders
func _check_ocean_seed(x: int, y: int, map_data: Dictionary, lvl: float, queue: Array, ocean_map: Dictionary):
	var pos = Vector2(x, y)
	if map_data.has(pos) and map_data[pos] < lvl:
		if ocean_map[pos] == false:
			ocean_map[pos] = true
			queue.append(pos)

########################################
######## Beach Identification ##########
########################################

# Returns a Dictionary[Vector2, bool]
# True = Within 'max_dist' of the ocean (Real Beach)
# False = Too far from ocean (Inland Lowland)
func get_beach_mask(ocean_mask: Dictionary, width: int, height: int, max_dist: int = 8) -> Dictionary:
	var beach_mask = {}
	var distance_map = {} # Stores distance to nearest ocean
	var queue = []        # For BFS
	
	# --- STEP 1: INITIALIZE BFS ---
	# Add ALL Ocean cells to the queue with distance 0.
	# Initialize all Land cells with "Infinity" distance (-1).
	for pos in ocean_mask:
		if ocean_mask[pos] == true:
			distance_map[pos] = 0
			queue.append(pos)
		else:
			distance_map[pos] = -1 # Unvisited Land
			
	# --- STEP 2: MULTI-SOURCE FLOOD FILL ---
	var directions = [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
	
	# We use a standard pointer-based queue for speed in GDScript
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		
		var current_dist = distance_map[current]
		
		# Optimization: If we are already at max_dist, we don't need to check neighbors,
		# because any neighbor would be dist+1 (which is too far).
		if current_dist >= max_dist:
			continue
			
		for d in directions:
			var neighbor = current + d
			
			if distance_map.has(neighbor):
				# If neighbor is unvisited (-1), we found a shorter path to it!
				if distance_map[neighbor] == -1:
					distance_map[neighbor] = current_dist + 1
					queue.append(neighbor)
					
	# --- STEP 3: BUILD THE BOOLEAN MASK ---
	# Now simply check the distance map.
	for pos in ocean_mask:
		# We only care about LAND cells.
		if ocean_mask[pos] == false:
			var dist = distance_map.get(pos, -1)
			
			# If visited and within range -> True Beach
			if dist != -1 and dist <= max_dist:
				beach_mask[pos] = true
			else:
				beach_mask[pos] = false
				
	return beach_mask
