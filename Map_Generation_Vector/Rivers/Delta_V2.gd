class_name Delta_V2
extends RefCounted

func generate_delta(
	world_data: World_Data,
	river: River,
	max_length: int = 100,         # Max length of the "big" streams
	interval: int = 15,         # Interval for spawning child streams
) -> void:
	var all_rivers: Array[River]
	var left_stream: River
	var right_stream: River
	var all_river_streams : Array[River]
	var direction_correction : float = 0
	var go_back: int = max(randi() % 30, 15) * -1
	var spawn_point: Vector2 = river.river_path[go_back]
	var river_direction: Vector2 = spawn_point.direction_to(river.river_path.back())
	while true:
		left_stream = generate_stream(world_data, river_direction, "left", spawn_point, direction_correction, max_length)
		if left_stream.river_path == []:
			direction_correction += PI/9
		else:
			break
	all_rivers.append(left_stream)
	direction_correction = 0
	while true:
		right_stream = generate_stream(world_data, river_direction, "right", spawn_point, direction_correction, max_length)
		if right_stream.river_path != []:
			direction_correction += PI/9
		else:
			break
	all_rivers.append(right_stream)
	var left_stream_sources: Array[Vector2] = get_filtered_items(left_stream.river_path, interval)
	all_rivers.append(generate_smaller_streams(world_data, river.river_path.back(), "right", interval, left_stream_sources))
	var right_stream_sources: Array[Vector2] = get_filtered_items(left_stream.river_path, interval)
	all_rivers.append(generate_smaller_streams(world_data, river.river_path.back(), "left", interval, right_stream_sources))
	
	

func generate_stream(
	world_data: World_Data,
	river_direction: Vector2,
	side: String,
	source: Vector2,
	direction_correction : float,
	max_length: int = 100         # Max length of the "big" streams
) -> River:
	var river_generator: River_Generator = River_Generator.new()
	var dir: Vector2 = get_rotated_direction(river_direction, side, (PI/3-direction_correction))
	return river_generator.generate_natural_river(world_data, source, dir, max_length)
	
func generate_smaller_streams(
	world_data: World_Data,
	river_mouth: Vector2,
	side: String,
	river_spawn_period: int,
	sources: Array[Vector2], # Max length of the "big" streams
) -> Array[River]:
	var river_generator: River_Generator = River_Generator.new()
	var rivers_to_return: Array[River]
	for source in sources:
		var rotation : float = randf_range(PI/6, PI/3)
		var mouth_direction: Vector2 = source.direction_to(river_mouth)
		var dir: Vector2 = get_rotated_direction(mouth_direction, side, rotation)
		var river: River = river_generator.generate_natural_river(world_data, source, dir)
		var additional_rivers : Array[River] = []
		var river_sources = get_filtered_items(river.river_path, river_spawn_period)
		if river_sources != []:
			var side_to_use: String
			if side == "right":
				side_to_use = "left"
			else:
				side_to_use = "right"
			additional_rivers = generate_smaller_streams(world_data, river_mouth, side_to_use, river_spawn_period, river_sources)
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
	
	# Determine rotation direction (positive is clockwise/right, negative is counter-clockwise/left)
	if side.to_lower() == "right":
		rotation_amount = offset_angle
	elif side.to_lower() == "left":
		rotation_amount = -offset_angle
	else:
		push_error("Side must be 'left' or 'right'")
		return current_direction
		
	# Rotate the vector and ensure it remains a normalized direction vector (length of 1)
	return current_direction.rotated(rotation_amount).normalized()
