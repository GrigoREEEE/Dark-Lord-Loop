class_name Delta_V2
extends RefCounted

func generate_delta(
	world_data: World_Data,
	river: River,
	Z: int = 80,         # Max length of the "big" streams
	F: int = 15,         # Interval for spawning child streams
	max_streams: int = 15 # Maximum total streams to generate
) -> void:
	
	# We need at least 2 regions to get the n-1 region
	if river.segments.size() < 2:
		print("River does not have enough segments for the Delta algorithm.")
		return
		
	# 1. Pop the last two regions (n and n-1)
	var region_n = river.segments.pop_back()
	var region_n_minus_1 = river.segments.pop_back()
	
	# Select the beginning of the n-1 region
	var start_pos = region_n_minus_1.points[0]
	
	# Find the general direction towards the ocean based on the original river path
	var end_pos = region_n.points.back()
	var base_dir = (end_pos - start_pos).normalized()
	
	var all_delta_points: Array[Vector2] = []
	
	# Add the original n-1 and n regions to the delta pool
	all_delta_points.append_array(region_n_minus_1.points)
	all_delta_points.append_array(region_n.points)
	
	var stream_tracker = {"count": 0, "max": max_streams}
	
	# 2 & 3. RIGHT "BIG" STREAM (+1.0 sign)
	var right_path = _get_valid_big_stream(start_pos, base_dir, 1.0, Z, world_data)
	if not right_path.is_empty():
		all_delta_points.append_array(right_path)
		_process_stream_recursively(right_path, 1.0, F, all_delta_points, stream_tracker, world_data)
		
	# 4. LEFT "BIG" STREAM (-1.0 sign)
	var left_path = _get_valid_big_stream(start_pos, base_dir, -1.0, Z, world_data)
	if not left_path.is_empty():
		all_delta_points.append_array(left_path)
		_process_stream_recursively(left_path, -1.0, F, all_delta_points, stream_tracker, world_data)

	# --- CONSOLIDATE INTO A SINGULAR REGION ---
	
	# Deduplicate all points (streams intersecting, bridge cells, etc.)
	var unique_points: Array[Vector2] = []
	var point_set = {}
	for pt in all_delta_points:
		if not point_set.has(pt):
			point_set[pt] = true
			unique_points.append(pt)
			
			# Ensure the new points are added to the main river path array so they render
			if not river.river_path.has(pt):
				river.river_path.append(pt)
				
	# Re-link the new singular Delta Region to the remaining river
	var previous_region: Region = null
	if not river.segments.is_empty():
		previous_region = river.segments.back()
		
		# Break old forward connections to the popped n-1 region
		if previous_region.regions_connect.has(region_n_minus_1):
			previous_region.regions_connect.erase(region_n_minus_1)
			
	var delta_region = Region.new()
	delta_region.associated_water = river
	delta_region.id = randi()
	delta_region.type = "Water"
	delta_region.subtype = "River Delta"
	delta_region.points = unique_points
	delta_region.size = unique_points.size()
	
	if previous_region != null:
		previous_region.regions_connect.append(delta_region)
		delta_region.regions_connect.append(previous_region)
		
	river.segments.append(delta_region)


# --- Helper 1: Big Stream Generation Loop ---
# Tries to shoot a stream at PI/3. If it exceeds length Z, reduces angle and retries.
func _get_valid_big_stream(start_pos: Vector2, base_dir: Vector2, sign: float, Z: int, world_data: World_Data) -> Array[Vector2]:
	var current_angle = PI / 3.0
	var final_path: Array[Vector2] = []
	
	# Safety loop (max 10 tries) to prevent infinite generation freezes
	for attempt in range(10):
		var target_dir = base_dir.rotated(current_angle * sign)
		final_path = _shoot_stream(start_pos, target_dir, world_data)
		
		if final_path.size() <= Z:
			break # Found a valid path!
			
		# Discard and reduce the angle by 20% to aim it more directly at the ocean
		current_angle *= 0.8
		
	return final_path


# --- Helper 2: Recursive Child Streams ---
func _process_stream_recursively(path: Array[Vector2], current_sign: float, F: int, all_delta_points: Array[Vector2], stream_tracker: Dictionary, world_data: World_Data) -> void:
	if stream_tracker.count >= stream_tracker.max:
		return
		
	var cells_since_branch = 0
	
	for i in range(path.size()):
		cells_since_branch += 1
		
		# Generate a smaller stream every F cells
		if cells_since_branch >= F:
			cells_since_branch = 0
			
			if stream_tracker.count >= stream_tracker.max:
				return
			stream_tracker.count += 1
			
			var branch_start = path[i]
			
			# Find the local direction of the stream to angle the branch correctly
			var look_back = max(0, i - 3)
			var local_dir = (path[i] - path[look_back]).normalized()
			if local_dir == Vector2.ZERO: local_dir = Vector2.DOWN
			
			# Rule 3a: Alternate direction. If parent went right, child goes left.
			var child_sign = -current_sign
			
			# Shoot child stream at roughly 45 degrees from the current flow
			var child_dir = local_dir.rotated((PI / 4.0) * child_sign)
			var child_path = _shoot_stream(branch_start, child_dir, world_data)
			
			all_delta_points.append_array(child_path)
			
			# Rule 3: Recursive - smaller cells have rivers produced in them as well
			_process_stream_recursively(child_path, child_sign, F, all_delta_points, stream_tracker, world_data)


# --- Helper 3: Pure Path Generation ---
# This is a pure-data version of your natural river generator.
# It ONLY terminates when hitting the ocean.
func _shoot_stream(start_pos: Vector2, target_dir: Vector2, world_data: World_Data) -> Array[Vector2]:
	var width: int = world_data.grid_width
	var height: int = world_data.grid_height
	var ocean: Water_Pool = world_data.ocean
	var noise_seed: int = world_data.noise_seed
	var res_scale: float = world_data.res_scale
	
	var path: Array[Vector2] = []
	path.append(start_pos)
	
	var noise = FastNoiseLite.new()
	noise.seed = noise_seed + int(start_pos.x * 10)
	noise.frequency = 0.01 / res_scale 
	
	var gravity_strength = 0.2
	var steer_strength = 0.5 
	var noise_cursor = 0.0
	var current_pos_float = start_pos
	var current_dir = target_dir.normalized()
	
	var max_steps = max(width, height) * 5 
	
	# Fast Ocean Dictionary
	var fast_ocean_check = {}
	for cell in ocean.all_cells:
		fast_ocean_check[cell] = true
		
	for step in range(max_steps):
		var progress = clamp(float(step) / 1000.0, 0.0, 1.0)
		var current_step_size = lerp(0.1, 1.2, progress)
		noise_cursor += current_step_size
		
		var noise_val = noise.get_noise_2d(noise_cursor, 0.0)
		var desired_angle = noise_val * PI
		var steer_vector = target_dir.rotated(desired_angle)
		
		current_dir = current_dir.lerp(steer_vector, steer_strength)
		current_dir = current_dir.lerp(target_dir, gravity_strength)
		current_pos_float += current_dir * 0.6 
		
		var current_grid_pos = current_pos_float.round()
		
		# Out of bounds check
		if current_grid_pos.x < 0 or current_grid_pos.x >= width or current_grid_pos.y < 0 or current_grid_pos.y >= height:
			break
			
		# Add point
		if path.back() != current_grid_pos:
			path.append(current_grid_pos)
			
		# Rule 3b: ALL streams ONLY terminate when they hit the ocean.
		# (We deliberately omit the "hit another river" check here so they can cross/merge freely)
		if fast_ocean_check.has(current_grid_pos):
			break
			
	return _orthagonalize_path(path, noise_seed)


# --- Helper 4: Standalone Orthogonalization ---
# Inserts bridge cells to remove diagonal gaps
func _orthagonalize_path(old_path: Array[Vector2], noise_seed: int) -> Array[Vector2]:
	if old_path.is_empty():
		return old_path
		
	var rng = RandomNumberGenerator.new()
	rng.seed = noise_seed
	var new_path: Array[Vector2] = [old_path[0]]
	
	for i in range(old_path.size() - 1):
		var current = old_path[i]
		var next = old_path[i+1]
		
		if current.x != next.x and current.y != next.y:
			var bridge: Vector2
			if rng.randf() > 0.5:
				bridge = Vector2(next.x, current.y)
			else:
				bridge = Vector2(current.x, next.y)
			new_path.append(bridge)
			
		new_path.append(next)
		
	return new_path
