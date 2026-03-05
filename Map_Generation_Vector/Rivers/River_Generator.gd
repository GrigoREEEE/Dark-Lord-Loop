extends Node

class_name River_Generator



# Generates a natural river flowing in ANY specified direction.
# - start_pos: Pixel coordinate where the river begins.
# - target_dir: The general "Gravity" direction (e.g., Vector2.RIGHT for West->East).
func generate_natural_river(
	width: int, 
	height: int, 
	ocean: Pool, 
	river_mask: Dictionary, 
	noise_seed: int, 
	start_pos: Vector2,
	target_dir: Vector2,
	res_scale: float = 1.0
) -> River:
	
	var river = River.new()
	river.id = "RI" + str(randi() % 9999).pad_zeros(4)
	river.river_type = "Natural"
	
	# --- 1. CONFIGURATION ---
	var noise = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.01 / res_scale 
	
	var gravity_strength: float = 0.35
	var steer_strength: float = 0.5 
	
	# Sensor Config
	var sensor_reach: float = 15.0 
	var repulsion_strength: float = 0.8 

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
		
		# --- A. BASE MOVEMENT (Noise + Gravity) ---
		# Get noise value (-1.0 to 1.0)
		var noise_val = noise.get_noise_2d(step_count * 0.5, 0.0)
		
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
			ocean.rivers_enter.append(river)
			break
			
		# 3. Check for Collision with Another River
		if river_mask.has(current_grid_pos):
			river.mouth = current_grid_pos
			_add_unique_point(river.river_path, current_grid_pos)
			
			# Extract the specific Region we hit and register this river to it
			var hit_region: Region = river_mask[current_grid_pos]
			hit_region.rivers_enter.append(river)
			break
			
		_add_unique_point(river.river_path, current_grid_pos)
		
	# Post-processing helper (assumed to exist)
	_orthagonalize_river_path(river, noise_seed)
	return river

func _add_unique_point(path: Array[Vector2], point: Vector2):
	if path.is_empty() or path.back() != point:
		path.append(point)


## Post-processing helper: Removes diagonal connections by inserting bridge cells
func _orthagonalize_river_path(river: River, noise_seed : int) -> void:
	var _rng = RandomNumberGenerator.new()
	_rng.seed = noise_seed
	
	var old_path: Array[Vector2] = river.river_path
	if old_path.is_empty():
		return

	var new_path: Array[Vector2] = []
	
	# Always keep the starting point
	new_path.append(old_path[0])
	
	for i in range(old_path.size() - 1):
		var current: Vector2 = old_path[i]
		var next: Vector2 = old_path[i+1]
		
		# Check if the move is diagonal
		# (True if both X and Y change between steps)
		if current.x != next.x and current.y != next.y:
			
			# We need a "bridge" cell.
			# Option A: Move X first (Horizontal corner) -> Vector2(next.x, current.y)
			# Option B: Move Y first (Vertical corner)   -> Vector2(current.x, next.y)
			
			var bridge: Vector2
			
			# Randomly pick one to prevent visual bias (zig-zag patterns)
			if _rng.randf() > 0.5:
				bridge = Vector2(next.x, current.y)
			else:
				bridge = Vector2(current.x, next.y)
				
			new_path.append(bridge)
		
		# Always add the target cell after the potential bridge
		new_path.append(next)
	
	# Apply the new smoothed path back to the river object
	river.river_path = new_path

# Trims the river path so it stops exactly where the NEW coastline begins.
func clean_river_path(river: River, ocean_mask: Dictionary):
	var new_path: Array[Vector2] = []
	
	for i in range(river.river_path.size()):
		var pos = river.river_path[i]
		
		# Always add the current point
		new_path.append(pos)
		
		# Check if this point is now Ocean (according to the post-erosion mask)
		if ocean_mask.get(pos, false) == true:
			# We hit the new water line!
			river.mouth = pos
			break # Stop adding points, discard the rest of the old path
	
	# Update the river object with the trimmed path
	river.river_path = new_path

# Checks if any "non-mouth" segment has accidentally grown into the beach.
# Returns TRUE if a breach is detected (bad state).
# Returns FALSE if the river is contained correctly.
func check_river_breach(river: River, beach_mask: Dictionary, mouth_segments_count: int) -> bool:
	if river.segments.is_empty():
		return false
		
	# Determine the boundary.
	# Any segment with an index LESS than this is considered "Inland" and must not touch the beach.
	var start_of_mouth_index = max(0, river.segments.size() - mouth_segments_count)
	
	# Iterate only through the inland segments
	for i in range(start_of_mouth_index):
		var segment = river.segments[i]
		
		for cell in segment:
			# If this cell is marked as beach in the mask
			if beach_mask.get(cell, false) == true:
				# We found a breach!
				# Optional: Print debug info to know where it happened
				# print("River Breach detected at segment ", i, " position ", cell)
				return true
				
	return false
