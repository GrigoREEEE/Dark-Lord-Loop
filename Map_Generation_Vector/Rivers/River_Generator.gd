extends Node

class_name River_Generator



# Generates a natural river flowing in ANY specified direction.
# - start_pos: Pixel coordinate where the river begins.
# - target_dir: The general "Gravity" direction (e.g., Vector2.RIGHT for West->East).
# - max_length: Maximum allowed tile length. If exceeded, returns an empty/invalid river. (0 = no limit)
func generate_natural_river(
	world_data: World_Data,
	start_pos: Vector2,
	target_dir: Vector2,
	max_length: int = 1000000
	) -> River:
		
	var width: int = world_data.grid_width
	var height: int = world_data.grid_height
	var ocean: Water_Pool = world_data.ocean
	var river_data: Dictionary = world_data.map_data["river"]
	var noise_seed: int = world_data.noise_seed
	var res_scale: float = world_data.res_scale
	var river = River.new()
	river.id = "RI" + str(randi() % 9999).pad_zeros(4)
	river.river_type = "Natural"
	
	# --- 1. CONFIGURATION ---
	var noise = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.01 / res_scale 
	
	var gravity_strength: float = 0.2
	var steer_strength: float = 0.5 
	var noise_cursor: float = 0.0

	# --- 2. INITIALIZATION ---
	river.source = start_pos
	
	var current_pos_float: Vector2 = start_pos
	# Initialize movement in the desired direction
	var current_dir: Vector2 = target_dir.normalized()
	
	river.river_path.append(river.source)
	
	var step_count: int = 0
	# Allow more steps for diagonal paths
	var max_steps: int = max(width, height) * 10 
	
	# OPTIMIZATION: Convert the ocean's Array to a temporary Dictionary 
	# so we don't cause massive lag checking the array every single step.
	var fast_ocean_check: Dictionary[Vector2, bool] = {}
	for cell: Vector2 in ocean.all_cells:
		fast_ocean_check[cell] = true
	
	# --- 3. FLOW LOOP ---
	while step_count < max_steps:
		step_count += 1
		
		# --- A. PROGRESSIVE MEANDERING ---
		# Create a progress factor from 0.0 to 1.0. 
		# (Adjust 400.0 to change how long it takes to reach maximum meandering)
		var progress: float = clamp(float(step_count) / 1000.0, 0.0, 1.0)
		
		# Dynamically change the noise step size!
		# Starts smooth and straight (0.1), ends chaotic and jagged (1.2)
		var current_step_size: float = lerp(0.1, 1.2, progress)
		
		# Safely advance the cursor
		noise_cursor += current_step_size
		
		# Get noise value (-1.0 to 1.0) using the cursor instead of step_count
		var noise_val = noise.get_noise_2d(noise_cursor, 0.0)
		
		# Calculate the noise steering vector relative to our target direction
		var desired_angle = noise_val * PI # -180 to 180 degrees
		var steer_vector = target_dir.rotated(desired_angle)
		
		# Apply forces
		current_dir = current_dir.lerp(steer_vector, steer_strength)
		current_dir = current_dir.lerp(target_dir, gravity_strength)
		
		# --- C. MOVE ---
		current_pos_float += current_dir * 0.6 
		
		# --- D. BOUNDS & RECORD ---
		var current_grid_pos = current_pos_float.round()
		
		# 1. Universal Out-of-Bounds Check
		if (current_grid_pos.x < 0 or current_grid_pos.x >= width or 
			current_grid_pos.y < 0 or current_grid_pos.y >= height):
			
			river.mouth = current_grid_pos
			# Clamp just for the final point so it doesn't crash map access
			current_grid_pos.x = clamp(current_grid_pos.x, 0, width-1)
			current_grid_pos.y = clamp(current_grid_pos.y, 0, height-1)
			_add_unique_point(river.river_path, current_grid_pos)
			break

		# 2. Check for Ocean Collision
		if fast_ocean_check.has(current_grid_pos):
			river.mouth = current_grid_pos
			_add_unique_point(river.river_path, current_grid_pos)
			
			# Register this river with the Ocean
			ocean.rivers_in.append(river)
			break
			
		# 3. Check for Collision with Another River
		if river_data.has(current_grid_pos):
			river.mouth = current_grid_pos
			_add_unique_point(river.river_path, current_grid_pos)
			
			# Extract the specific Region we hit and register this river to it
			var hit_region: Region = river_data[current_grid_pos]
			hit_region.rivers_in.append(river)
			break
			
		_add_unique_point(river.river_path, current_grid_pos)
		
		# 4. Check Maximum Length Limit
		if max_length > 0 and river.river_path.size() > max_length:
			river.river_path.clear()
			river.is_proper = false
			return river
		
	# Post-processing helper (assumed to exist)
	_orthagonalize_river_path(river, noise_seed)
	return river
