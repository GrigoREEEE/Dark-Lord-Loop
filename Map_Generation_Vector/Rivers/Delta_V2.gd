class_name Delta_V2
extends RefCounted

func generate_delta(
	world_data: World_Data,
	river: River,
	max_streams: int = 8,
	branch_interval: int = 6, 
	angle_variance: float = PI / 3.0 # Allow a wider initial spread (~60 degrees)
) -> void:
	
	if river.river_path.is_empty():
		return
		
	var start_pos = river.river_path.back()
	
	# 1. Determine base direction
	var base_dir = Vector2.DOWN
	var path_size = river.river_path.size()
	
	if path_size >= 5:
		base_dir = (start_pos - river.river_path[path_size - 5]).normalized()
	elif path_size >= 2:
		base_dir = (start_pos - river.river_path[path_size - 2]).normalized()
		
	# --- NEW: THE FOCAL POINT ---
	# We project a target point ~25 cells directly ahead into the ocean.
	# All streams will fan out, then curve back towards this exact spot.
	var focal_point = start_pos + (base_dir * 25.0)
		
	var delta_points: Array[Vector2] = []
	var stream_tracker = {"count": 1} 
	
	var rng = RandomNumberGenerator.new()
	rng.seed = world_data.noise_seed + int(start_pos.x * 100) + int(start_pos.y)
	
	# --- NEW: DELTA NOISE ---
	var delta_noise = FastNoiseLite.new()
	delta_noise.seed = rng.seed
	delta_noise.frequency = 0.05 / world_data.res_scale
	
	# 2. Start the recursive stream generation
	_generate_delta_stream(
		start_pos, 
		base_dir, 
		focal_point, 
		branch_interval, 
		max_streams,
		angle_variance, 
		world_data, 
		delta_points, 
		stream_tracker,
		rng,
		delta_noise,
		0 # initial step count
	)
	
	# 3. Create the Singular Region
	if delta_points.is_empty():
		return
		
	var unique_points: Array[Vector2] = []
	var point_set = {}
	for pt in delta_points:
		if not point_set.has(pt):
			point_set[pt] = true
			unique_points.append(pt)
			
	var previous_region: Region = null
	if not river.segments.is_empty():
		previous_region = river.segments.back()
		
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
	river.river_path.append_array(unique_points)


# The Recursive Function
func _generate_delta_stream(
	current_grid_pos: Vector2,
	current_dir: Vector2,
	focal_point: Vector2,
	branch_interval: int,
	max_streams: int,
	angle_variance: float,
	world_data: World_Data,
	delta_points: Array[Vector2],
	stream_tracker: Dictionary,
	rng: RandomNumberGenerator,
	noise: FastNoiseLite,
	inherited_steps: int
) -> void:
	
	var width = world_data.grid_width
	var height = world_data.grid_height
	var ocean_mask = world_data.mask_data.get("ocean", {})
	
	var current_float_pos = current_grid_pos
	var last_grid = current_grid_pos
	
	var cells_since_branch = 0
	
	# HARD LIMIT: A single delta stream can never travel more than 80 steps.
	# This absolutely prevents continental wandering.
	var max_steps_failsafe = 80 
	var step = inherited_steps
	
	while step < max_steps_failsafe:
		step += 1
		
		# --- NEW: MEANDERING & STEERING LOGIC ---
		
		# 1. Wobble: Get noise based on current position and rotate the direction slightly
		var noise_val = noise.get_noise_2d(current_float_pos.x, current_float_pos.y)
		var wobble_dir = current_dir.rotated(noise_val * 0.6) # 0.6 radians of wobble
		
		# 2. Focal Pull: Calculate direction to the focal point in the ocean
		var to_focal = (focal_point - current_float_pos).normalized()
		
		# 3. Pull Strength: Starts low (so branches can spread wide), 
		# but increases dramatically as the stream gets longer, forcing it back inward.
		var pull_strength = clamp(float(step) / 40.0, 0.05, 0.8)
		
		# 4. Apply forces
		current_dir = wobble_dir.lerp(to_focal, pull_strength).normalized()
		
		# Move forward
		current_float_pos += current_dir * 0.6
		var grid_pos = current_float_pos.round()
		
		if grid_pos == last_grid:
			continue
			
		# Out of bounds check
		if grid_pos.x < 0 or grid_pos.x >= width or grid_pos.y < 0 or grid_pos.y >= height:
			break
			
		# Orthogonalize on the fly
		if grid_pos.x != last_grid.x and grid_pos.y != last_grid.y:
			var bridge: Vector2
			if rng.randf() > 0.5:
				bridge = Vector2(grid_pos.x, last_grid.y)
			else:
				bridge = Vector2(last_grid.x, grid_pos.y)
				
			delta_points.append(bridge)
			cells_since_branch += 1
			
		delta_points.append(grid_pos)
		cells_since_branch += 1
		last_grid = grid_pos
		
		# Stop this stream if it hits the ocean
		if ocean_mask.get(grid_pos, false) == true:
			break
			
		# --- BRANCHING LOGIC ---
		if cells_since_branch >= branch_interval:
			if stream_tracker.count < max_streams:
				stream_tracker.count += 1
				
				# Shoot the new stream out sharply to the side
				var sign = 1.0 if rng.randf() > 0.5 else -1.0
				var branch_angle = sign * rng.randf_range(angle_variance * 0.6, angle_variance)
				var branch_dir = current_dir.rotated(branch_angle).normalized()
				
				# RECURSIVE CALL: Note we pass 'step' so the new stream inherits the 
				# gravitational pull strength and failsafe limits of its parent.
				_generate_delta_stream(
					grid_pos, 
					branch_dir, 
					focal_point, 
					branch_interval, 
					max_streams,
					angle_variance, 
					world_data, 
					delta_points, 
					stream_tracker, 
					rng,
					noise,
					step 
				)
				
				cells_since_branch = 0
