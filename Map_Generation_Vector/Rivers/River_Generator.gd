extends Node

class_name River_Generator

var _rng = RandomNumberGenerator.new()
var _winding_noise = FastNoiseLite.new()

func _init():
	_rng.randomize()
	_winding_noise.seed = _rng.randi()
	_winding_noise.frequency = 0.05 # Lower = Long, lazy curves. Higher = Snakelike.
	_winding_noise.fractal_octaves = 2

func generate_natural_river(width: int, height: int, ocean_mask: Dictionary, res_scale: float = 1.0) -> River:
	var river = River.new()
	river.id = "RI" + str(_rng.randi() % 9999).pad_zeros(4)
	river.river_type = "Natural"

	# --- 1. CONFIGURATION ---
	# Lower frequency = wider, larger meanders
	_winding_noise.frequency = 0.005 / res_scale 
	
	# How strongly the river wants to go South (0.0 to 1.0)
	# Low = Crazy winding loops. High = Straighter river.
	var gravity_strength: float = 0.3
	
	# How hard the noise pushes the river left/right
	var steer_strength: float = 0.5 

	# --- 2. INITIALIZATION ---
	# Note: Based on your previous code, I assume (width/2, 0) is North (Source)
	# and (height) is South (Ocean). 
	var start_x = width / 2.0
	river.source = Vector2(start_x, 0)
	
	# We use a float vector for smooth movement, but store ints in the path
	var current_pos_float: Vector2 = Vector2(start_x, 0)
	var current_dir: Vector2 = Vector2.DOWN # Initial momentum
	
	river.river_path.append(river.source)
	
	var step_count: int = 0
	var max_steps: int = height * 10 # Allow plenty of steps for winding
	
	# --- 3. FLOW LOOP ---
	while step_count < max_steps:
		step_count += 1
		
		# A. CALCULATE STEERING FORCES
		# Get noise value between -1 and 1
		var noise_val = _winding_noise.get_noise_2d(step_count * 0.5, 0.0)
		
		# Create a steering force based on noise (perpendicular to flow is best, 
		# but simple rotation works for top-down rivers)
		var desired_angle = noise_val * PI # Steer anywhere from -180 to 180 degrees potentially
		var steer_vector = Vector2.DOWN.rotated(desired_angle)
		
		# B. APPLY FORCES TO DIRECTION
		# 1. Add noise steering
		current_dir = current_dir.lerp(steer_vector, steer_strength)
		# 2. Add "Gravity" (pull towards Ocean/South) so it doesn't loop forever
		current_dir = current_dir.lerp(Vector2.DOWN, gravity_strength)
		
		# Normalize to ensure consistent speed
		current_dir = current_dir.normalized()
		
		# C. MOVE CURSOR
		# We move by < 1.0 to ensure we don't skip over grid cells (diagonal gaps)
		current_pos_float += current_dir * 0.6 
		
		# D. CONVERT TO GRID
		var current_grid_pos = Vector2(round(current_pos_float.x), round(current_pos_float.y))
		
		# E. SAFETY BOUNDS (Clamp X, Check Y)
		current_grid_pos.x = clamp(current_grid_pos.x, 0, width - 1)
		
		# Check if we hit the bottom of the map
		if current_grid_pos.y >= height - 1:
			river.mouth = current_grid_pos
			_add_unique_point(river.river_path, current_grid_pos)
			break

		# F. OCEAN CHECK
		var is_ocean = ocean_mask.get(current_grid_pos, false)
		
		if is_ocean:
			river.mouth = current_grid_pos
			_add_unique_point(river.river_path, current_grid_pos)
			break
			
		# G. RECORD PATH
		# Only add if it's a new tile (since we move in sub-pixel steps)
		_add_unique_point(river.river_path, current_grid_pos)
		_orthagonalize_river_path(river)
	return river

# Helper to prevent duplicate consecutive points in the array
func _add_unique_point(arr: Array[Vector2], point: Vector2) -> void:
	if arr.is_empty() or arr.back() != point:
		arr.append(point)

## Post-processing helper: Removes diagonal connections by inserting bridge cells
func _orthagonalize_river_path(river: River) -> void:
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

## Generates a single river starting at Top-Center and winding South
#func generate_central_river(width: int, height: int, ocean_mask: Dictionary, res_scale: float = 1.0) -> River:
	#var river = River.new()
	#river.id = "RI" + str(_rng.randi() % 9999).pad_zeros(4)
	#river.river_type = "Central"
	#
	## --- 1. DETERMINE SOURCE ---
	#river.source = Vector2(int(width / 2.0), 0)
	#river.river_path.append(river.source)
	#
	## --- 2. WINDING CONFIGURATION ---
	#_winding_noise.frequency = 0.03 / res_scale 
	#
	#var current_pos = river.source
	#var step_count = 0
	#var max_steps = height * 4 
	#
	## --- 3. FLOW LOOP ---
	#while step_count < max_steps:
		#step_count += 1
		#
		## A. DETERMINE STEERING
		#var steer = _winding_noise.get_noise_1d(step_count * 5.0) 
		#var move_dir = Vector2(0, 1) # Default: South
		#
		#if steer > 0.2: move_dir = Vector2(1, 0)  # East
		#elif steer < -0.2: move_dir = Vector2(-1, 0) # West
			#
		## B. PREDICT TARGET
		#var target_pos = current_pos + move_dir
		#
		## C. ANTI-LOOP SAFETY
		## If we try to turn into our own path, force flow South immediately.
		#if river.river_path.has(target_pos):
			#target_pos = current_pos + Vector2(0, 1)
			#
		## D. BOUNDARY SAFETY
		## If we hit the bottom of the map, stop.
		#if target_pos.y >= height - 1:
			#river.mouth = current_pos
			#break
			#
		#target_pos.x = clamp(target_pos.x, 0, width - 1)
		#
		## E. CRITICAL OCEAN CHECK
		## We check the mask for the TARGET position.
		## usage of .get(pos, true) defaults to TRUE (Ocean) for safety if data is missing.
		## If the mask has the key, it uses the bool value. If key is missing, we assume Ocean to stop infinite loops.
		#var is_target_ocean = ocean_mask.get(target_pos, false)
		#
		#if is_target_ocean:
			#print(target_pos)
			#print(ocean_mask[target_pos])
			## The target IS water. 
			## 1. Move into the water cell (so it connects visually)
			#river.river_path.append(target_pos)
			#river.mouth = target_pos
			## 2. TERMINATE IMMEDIATELY
			#break
		#
		## F. COMMIT MOVE (If we are here, target is definitely Land)
		#current_pos = target_pos
		#river.river_path.append(current_pos)
		#
	#return river
#
# Trims the river path so it stops exactly where the NEW coastline begins.
func clean_river_path(river: River, ocean_mask: Dictionary):
	var new_path: Array[Vector2] = []
	var found_ocean = false
	
	for i in range(river.river_path.size()):
		var pos = river.river_path[i]
		
		# Always add the current point
		new_path.append(pos)
		
		# Check if this point is now Ocean (according to the post-erosion mask)
		if ocean_mask.get(pos, false) == true:
			# We hit the new water line!
			river.mouth = pos
			found_ocean = true
			break # Stop adding points, discard the rest of the old path
	
	# Update the river object with the trimmed path
	river.river_path = new_path
