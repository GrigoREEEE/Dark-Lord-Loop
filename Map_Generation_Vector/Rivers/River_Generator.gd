extends Node

class_name River_Generator

var _rng = RandomNumberGenerator.new()
var _winding_noise = FastNoiseLite.new()

func _init():
	_rng.randomize()
	_winding_noise.seed = _rng.randi()
	_winding_noise.frequency = 0.05 # Lower = Long, lazy curves. Higher = Snakelike.
	_winding_noise.fractal_octaves = 2

# Generates a single river starting at Top-Center and winding South
func generate_central_river(width: int, height: int, ocean_mask: Dictionary, res_scale: float = 1.0) -> River:
	var river = River.new()
	river.id = "RI" + str(_rng.randi() % 9999).pad_zeros(4)
	river.river_type = "Central"
	
	# --- 1. DETERMINE SOURCE ---
	river.source = Vector2(int(width / 2.0), 0)
	river.river_path.append(river.source)
	
	# --- 2. WINDING CONFIGURATION ---
	_winding_noise.frequency = 0.05 / res_scale 
	
	var current_pos = river.source
	var step_count = 0
	var max_steps = height * 4 
	
	# --- 3. FLOW LOOP ---
	while step_count < max_steps:
		step_count += 1
		
		# A. DETERMINE STEERING
		var steer = _winding_noise.get_noise_1d(step_count * 5.0) 
		var move_dir = Vector2(0, 1) # Default: South
		
		if steer > 0.35: move_dir = Vector2(1, 0)  # East
		elif steer < -0.35: move_dir = Vector2(-1, 0) # West
			
		# B. PREDICT TARGET
		var target_pos = current_pos + move_dir
		
		# C. ANTI-LOOP SAFETY
		# If we try to turn into our own path, force flow South immediately.
		if river.river_path.has(target_pos):
			target_pos = current_pos + Vector2(0, 1)
			
		# D. BOUNDARY SAFETY
		# If we hit the bottom of the map, stop.
		if target_pos.y >= height - 1:
			river.mouth = current_pos
			break
			
		target_pos.x = clamp(target_pos.x, 0, width - 1)
		
		# E. CRITICAL OCEAN CHECK
		# We check the mask for the TARGET position.
		# usage of .get(pos, true) defaults to TRUE (Ocean) for safety if data is missing.
		# If the mask has the key, it uses the bool value. If key is missing, we assume Ocean to stop infinite loops.
		var is_target_ocean = ocean_mask.get(target_pos, false)
		
		if is_target_ocean:
			print(target_pos)
			print(ocean_mask[target_pos])
			# The target IS water. 
			# 1. Move into the water cell (so it connects visually)
			river.river_path.append(target_pos)
			river.mouth = target_pos
			# 2. TERMINATE IMMEDIATELY
			break
		
		# F. COMMIT MOVE (If we are here, target is definitely Land)
		current_pos = target_pos
		river.river_path.append(current_pos)
		
	return river

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
