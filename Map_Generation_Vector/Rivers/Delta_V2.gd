class_name Delta_V2
extends RefCounted

func generate_delta(
	world_data: World_Data,
	river: River,
	max_length: int = 100,      
	interval: int = 15,         
	regions_back: int = 2       
) -> void:
	
	print("\n--- [Delta Trace] STARTING DELTA GENERATION ---")
	print("  -> Parent River ID: ", river.id)
	
	if river.segments.size() <= regions_back:
		print("  -> [Delta Trace] River too short to backtrack. Adjusting regions_back.")
		regions_back = river.segments.size() - 1
		if regions_back <= 0:
			print("  -> [Delta Trace] ABORT: River has no valid segments to split from.")
			return

	var all_rivers: Array[River]
	var left_stream: River = null
	var right_stream: River = null
	var direction_correction : float = 0
	
	var spawn_point: Vector2 = river.segments[(-1 * regions_back)].points[0]
	var original_mouth: Vector2 = river.river_path.back()
	
	var phys_spawn = global._get_hex_physical_pos(spawn_point)
	var phys_mouth = global._get_hex_physical_pos(original_mouth)
	var river_direction: Vector2 = phys_spawn.direction_to(phys_mouth)
	
	print("  -> [Delta Trace] Spawn Point: ", spawn_point, " | Original Mouth: ", original_mouth)
	
	# TRUNCATE THE OLD RIVER TAIL
	var split_index = river.river_path.size() - (river.segments.back().size * regions_back) - 1
	split_index = max(0, split_index)
	river.river_path = river.river_path.slice(0, split_index + 1)
	river.mouth = spawn_point
	
	# --- NEW: LOCAL COLLISION MASK ---
	var local_delta_mask: Dictionary = {}
	# Seed it with the truncated parent river so streams don't loop backwards
	for pt in river.river_path:
		local_delta_mask[pt] = true
	
	# --- SAFE LEFT STREAM GENERATION ---
	print("  -> [Delta Trace] Generating Main Left Stream...")
	var attempts = 0
	var max_attempts = 36 
	while attempts < max_attempts:
		left_stream = generate_stream(world_data, river_direction, "left", spawn_point, direction_correction, max_length, local_delta_mask)
		if left_stream.river_path.is_empty():
			direction_correction += PI/18 
			attempts += 1
			print("    -> [Delta Trace] Left stream empty. Rotating PI/18. Attempt: ", attempts)
		else:
			print("    -> [Delta Trace] Left stream SUCCESS. Length: ", left_stream.river_path.size())
			# Add new path to the mask!
			for pt in left_stream.river_path:
				local_delta_mask[pt] = true
			break
			
	if left_stream != null and not left_stream.river_path.is_empty():
		all_rivers.append(left_stream)
	
	# --- SAFE RIGHT STREAM GENERATION ---
	print("  -> [Delta Trace] Generating Main Right Stream...")
	direction_correction = 0
	attempts = 0
	while attempts < max_attempts:
		right_stream = generate_stream(world_data, river_direction, "right", spawn_point, direction_correction, max_length, local_delta_mask)
		if right_stream.river_path.is_empty():
			direction_correction += PI/18
			attempts += 1
			print("    -> [Delta Trace] Right stream empty. Rotating PI/18. Attempt: ", attempts)
		else:
			print("    -> [Delta Trace] Right stream SUCCESS. Length: ", right_stream.river_path.size())
			# Add new path to the mask!
			for pt in right_stream.river_path:
				local_delta_mask[pt] = true
			break
			
	if right_stream != null and not right_stream.river_path.is_empty():
		all_rivers.append(right_stream)
	
	# --- RECURSIVE CHILD STREAMS ---
	print("  -> [Delta Trace] Initiating child stream recursion...")
	
	var global_tracker = { "count": 0, "max_total": 40 } 
	var max_recursion_depth = 3
	
	if left_stream != null and not left_stream.river_path.is_empty():
		var left_stream_sources: Array[Vector2] = get_filtered_items(left_stream.river_path, interval)
		# PASS river_direction INSTEAD OF original_mouth
		all_rivers.append_array(generate_smaller_streams(world_data, river_direction, "right", interval, left_stream_sources, max_length, 0, max_recursion_depth, global_tracker, local_delta_mask))
	
	if right_stream != null and not right_stream.river_path.is_empty():
		var right_stream_sources: Array[Vector2] = get_filtered_items(right_stream.river_path, interval)
		# PASS river_direction INSTEAD OF original_mouth
		all_rivers.append_array(generate_smaller_streams(world_data, river_direction, "left", interval, right_stream_sources, max_length, 0, max_recursion_depth, global_tracker, local_delta_mask))
	
	print("  -> [Delta Trace] Bundling ", all_rivers.size(), " total streams into Delta Region.")
	_bundle_delta_region(river, all_rivers, regions_back)
	print("--- [Delta Trace] DELTA GENERATION COMPLETE ---\n")


func generate_stream(
	world_data: World_Data,
	river_direction: Vector2,
	side: String,
	source: Vector2,
	direction_correction : float,
	max_length: int,
	local_delta_mask: Dictionary # <--- NEW
) -> River:
	var river_generator: River_Generator = River_Generator.new()
	var dir: Vector2 = get_rotated_direction(river_direction, side, (PI/6 - direction_correction))
	
	# Pass the local mask so it knows to stop
	return river_generator.generate_natural_river(world_data, source, dir, max_length, 1.5, 0.8, false, local_delta_mask)
	
	
func generate_smaller_streams(
	world_data: World_Data,
	river_mouth: Vector2,
	side: String,
	river_spawn_period: int,
	sources: Array[Vector2],
	max_length: int,
	current_depth: int,
	max_depth: int,
	global_tracker: Dictionary,
	local_delta_mask: Dictionary # <--- NEW
) -> Array[River]:
	
	var rivers_to_return: Array[River] = []
	
	if current_depth >= max_depth:
		print("      -> [Delta Trace] Hit max recursion depth (", max_depth, "). Aborting branch.")
		return rivers_to_return
		
	var river_generator: River_Generator = River_Generator.new()
	
	for source in sources:
		if global_tracker["count"] >= global_tracker["max_total"]:
			print("      -> [Delta Trace] Global stream limit reached (", global_tracker["max_total"], "). Halting generation.")
			return rivers_to_return
			
		global_tracker["count"] += 1
		
		var rotation : float = randf_range(PI/18, PI/6) 
		var phys_source = global._get_hex_physical_pos(source)
		var phys_mouth = global._get_hex_physical_pos(river_mouth)
		var mouth_direction: Vector2 = phys_source.direction_to(phys_mouth)
		var dir: Vector2 = get_rotated_direction(mouth_direction, side, rotation)
		
		# Pass the local mask down
		var river: River = river_generator.generate_natural_river(world_data, source, dir, max_length, 2.0, 0.9, true, local_delta_mask)
		
		if river.river_path.is_empty():
			continue 
			
		# --- NEW: UPDATE MASK WITH CHILD STREAM ---
		for pt in river.river_path:
			local_delta_mask[pt] = true
			
		var additional_rivers : Array[River] = []
		var river_sources = get_filtered_items(river.river_path, river_spawn_period)
		
		if not river_sources.is_empty(): 
			var side_to_use: String = "left" if side == "right" else "right"
			
			print("      -> [Delta Trace] Child stream spawned at depth ", current_depth, ". Spawning ", river_sources.size(), " sub-children.")
			
			additional_rivers = generate_smaller_streams(
				world_data, river_mouth, side_to_use, river_spawn_period, 
				river_sources, max_length, current_depth + 1, max_depth, global_tracker, local_delta_mask
			)
			
		rivers_to_return.append(river)
		rivers_to_return.append_array(additional_rivers)
		
	return rivers_to_return


func get_filtered_items(arr: Array, x: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if x <= 0:
		return result
	for i in range(x, arr.size() - x, x):
		result.append(arr[i])
	return result
		
	
func get_rotated_direction(current_direction: Vector2, side: String, offset_angle: float) -> Vector2:
	var rotation_amount: float = 0.0
	
	if side.to_lower() == "right":
		rotation_amount = offset_angle
	elif side.to_lower() == "left":
		rotation_amount = -offset_angle
	else:
		push_error("Side must be 'left' or 'right'")
		return current_direction
		
	return current_direction.rotated(rotation_amount).normalized()


func _bundle_delta_region(parent_river: River, delta_streams: Array[River], regions_back: int) -> void:
	var unique_points: Array[Vector2] = []
	var point_set = {}
	
	var popped_regions: Array[Region] = []
	for k in range(min(regions_back, parent_river.segments.size())):
		var popped = parent_river.segments.pop_back()
		popped_regions.append(popped)
		
		for pt in popped.points:
			if not point_set.has(pt):
				point_set[pt] = true
				unique_points.append(pt)
				
	for stream in delta_streams:
		for pt in stream.river_path:
			if not point_set.has(pt):
				point_set[pt] = true
				unique_points.append(pt)
				if not parent_river.river_path.has(pt):
					parent_river.river_path.append(pt)
				
	if unique_points.is_empty():
		return
				
	var previous_region: Region = null
	if not parent_river.segments.is_empty():
		previous_region = parent_river.segments.back()
		for popped in popped_regions:
			if previous_region.regions_connect.has(popped):
				previous_region.regions_connect.erase(popped)
				
	var delta_region = Region.new()
	delta_region.associated_water = parent_river
	delta_region.id = randi()
	delta_region.type = "Water"
	delta_region.subtype = "River Delta"
	delta_region.points = unique_points
	delta_region.size = unique_points.size()
	
	if previous_region != null:
		previous_region.regions_connect.append(delta_region)
		delta_region.regions_connect.append(previous_region)
		
	parent_river.segments.append(delta_region)
	parent_river.mouth = parent_river.river_path.back()
