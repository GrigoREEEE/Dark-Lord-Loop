extends Node

class_name River_Generator



func generate_natural_river(width: int, height: int, ocean_mask: Dictionary, noise_seed : int, res_scale: float = 1.0) -> River:
	
	var river = River.new()
	river.id = "RI" + str(randi() % 9999).pad_zeros(4)
	river.river_type = "Natural"
	
	# --- 1. CONFIGURATION ---
	var noise = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.01 / res_scale 
	
	var gravity_strength: float = 0.35
	var steer_strength: float = 0.5 


	# --- 2. INITIALIZATION ---
	var start_x = width / 2.0
	river.source = Vector2(start_x, 0)
	
	var current_pos_float: Vector2 = Vector2(start_x, 0)
	var current_dir: Vector2 = Vector2.DOWN 
	
	river.river_path.append(river.source)
	
	var step_count: int = 0
	var max_steps: int = height * 10 
	
	# --- 3. FLOW LOOP ---
	while step_count < max_steps:
		step_count += 1
		
		# --- A. BASE MOVEMENT (Noise + Gravity) ---
		var noise_val = noise.get_noise_2d(step_count * 0.5, 0.0)
		var desired_angle = noise_val * PI 
		var steer_vector = Vector2.DOWN.rotated(desired_angle)
		
		# Apply natural forces
		current_dir = current_dir.lerp(steer_vector, steer_strength)
		current_dir = current_dir.lerp(Vector2.DOWN, gravity_strength)
		
		
		# --- C. MOVE ---
		current_pos_float += current_dir * 0.6 
		
		# --- D. BOUNDS & RECORD ---
		var current_grid_pos = current_pos_float.round()
		current_grid_pos.x = clamp(current_grid_pos.x, 0, width - 1)
		
		if current_grid_pos.y >= height - 1:
			river.mouth = current_grid_pos
			_add_unique_point(river.river_path, current_grid_pos)
			break

		if ocean_mask.get(current_grid_pos, false):
			river.mouth = current_grid_pos
			_add_unique_point(river.river_path, current_grid_pos)
			break
			
		_add_unique_point(river.river_path, current_grid_pos)
		
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
