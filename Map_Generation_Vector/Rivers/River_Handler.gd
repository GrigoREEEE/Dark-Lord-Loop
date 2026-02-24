extends Node

class_name River_Handler

var mouth_segments: int = 3 #number of the original main river segments that get the mouth bonus
var to_merge: int = 0 #number of the main river segments we merge to form delta
var bands_quantity: int = 5
var delta_streams: Dictionary[int, int] = {3:1,2:1,1:1} #size and number of streams that form the delta
var bands_rivers: Dictionary[int, int] = {0:1, 1:1, 2:1, 3:1, 4:1}


func handle_rivers(
	map_width: int,
	map_height: int, 
	terrain_data: Dictionary[Vector2, float], 
	_ocean_mask: Dictionary[Vector2, bool],
	_beach_mask: Dictionary[Vector2, bool],
	_delta_mask: Dictionary[Vector2, bool],
	noise_seed: int, 
	res_scale: float):
		
	var river_system : Array[River] = []
	var bands_set: Array[Dictionary] = generate_map_bands(map_height, bands_quantity, 20 * res_scale)
	var bands_keys: Array[int] = bands_rivers.keys()
	var river_noises: Dictionary[int, Array] = calculate_river_noises(noise_seed)
	for i in bands_keys:
		var river_to_add : int = bands_rivers[i] # number of rivers we need to add per band
		while river_to_add > 0:
			var selecte_noise: int = river_noises[i][(bands_rivers[i]-river_to_add)]
			river_to_add -= 1
			var band: Dictionary[String, int] = bands_set[i]
			var river: River = setup_river("side", map_width, map_height, terrain_data, _ocean_mask, _beach_mask, _delta_mask, band, selecte_noise, res_scale)
			river_system.append(river)
	return river_system

func setup_river(
	type: String,
	map_width: int,
	map_height: int, 
	terrain_data: Dictionary[Vector2, float], 
	_ocean_mask: Dictionary[Vector2, bool],
	_beach_mask: Dictionary[Vector2, bool],
	_delta_mask: Dictionary[Vector2, bool],
	band : Dictionary[String, int],
	noise_seed: int, 
	res_scale: float):
	
	Profiler.start("total river generation")
	var Source_Selector : Source_Selection = Source_Selection.new()
	var river_gen: River_Generator = River_Generator.new()
	var erosion: River_Erosion = River_Erosion.new()
	var ocean_id: Ocean_Identification = Ocean_Identification.new()
	var beach_id: Beach_Identification = Beach_Identification.new()
	var river_expander: River_Widener = River_Widener.new()
	var delta_maker: Delta = Delta.new()
	var my_river: River
	
	var river_start_pos : Vector2 = Vector2.ZERO
	var river_direction : Vector2 = Vector2.ZERO
	
	if type == "main":
		river_start_pos = Vector2(map_width/2,0)
		river_direction = Vector2.DOWN
	else:
		river_start_pos =  Source_Selector.select_river_source(terrain_data, _ocean_mask, map_width, band["start"], band["end"], noise_seed)
		river_direction = get_random_river_direction((noise_seed + band["start"] + band["end"]))
	print("River Source is %s" % river_start_pos)
	_ocean_mask = ocean_id.ocean_vs_land(terrain_data, map_width, map_height)
	_beach_mask = beach_id.generate_beach_mask(_ocean_mask, 5, res_scale)
	
		
	## Generate the River
	my_river = river_gen.generate_natural_river(map_width, map_height, _ocean_mask, noise_seed, river_start_pos, river_direction, res_scale)
	if check_river_breach(my_river, _beach_mask, mouth_segments):
		print("River touches beach!")
		noise_seed = randi()
		print("New noise seed is: %s" % noise_seed)
		my_river = null
		setup_river(type, map_width, map_height, terrain_data, _ocean_mask, _beach_mask, _delta_mask, band, noise_seed, res_scale)
	else:
		## Apply Erosion
		if type == "main":
			erosion.apply_river_erosion(terrain_data, my_river, 29.0, 30.0, 0.85, 0.2, res_scale) #5, 30, 0.9, 0.1)
		## Check where the ocean is again (due to erosion)
		_ocean_mask = ocean_id.ocean_vs_land(terrain_data, map_width, map_height)
		if type == "main":
			## Remove the river from the ocean
			river_gen.clean_river_path(my_river, _ocean_mask)
			## Break the river into segments
			my_river.create_segments(10 * res_scale)
			to_merge = my_river.resegment_delta(mouth_segments, 1 * res_scale) + 1
			
			## Expand the river
			river_expander.widen_river_iterative(terrain_data, my_river, _ocean_mask, mouth_segments, 20.0 * res_scale, 1.0 * res_scale)
			river_expander.merge_segments(my_river, to_merge)
			#_delta_mask = delta_maker.create_delta_mask(my_river, map_width, map_height)
			_delta_mask = delta_maker.create_delta_mask2(my_river)
			## Make the delta
			delta_maker.generate_delta(my_river, _ocean_mask, delta_streams, noise_seed)
			delta_maker.naturalize_delta_islands(terrain_data, my_river, _delta_mask)
			delta_maker.erode_delta_edges(terrain_data, _delta_mask)
		
		Profiler.end("total river generation")
		return my_river
	
	# Checks if any "non-mouth" segment has accidentally grown into the beach.
# Returns TRUE if a breach is detected (bad state).
# Returns FALSE if the river is contained correctly.
func check_river_breach(river: River, beach_mask: Dictionary, mouth_segments_count: int) -> bool:
	if river.segments.is_empty():
		return false
	var start_of_mouth_index = max(0, river.segments.size() - mouth_segments_count)
	for i in range(start_of_mouth_index):
		var segment = river.segments[i]
		for cell in segment:
			if beach_mask.get(cell, false) == true:
				return true
	return false

# Generates a normalized Vector2 pointing between 180 and 360 degrees.
# In Godot's 2D space (+Y is down), this means the river will flow generally UP (North).
func get_random_river_direction(noise_seed : int) -> Vector2:
	var rng = RandomNumberGenerator.new()
	rng.seed = noise_seed
	
	# PI = 180 degrees (Left)
	# TAU = 360 degrees (Right)
	# Values in between point Upwards (-Y)
	var random_angle = rng.randf_range(0 + PI/4, PI - PI/4)
	
	return Vector2.from_angle(random_angle)

# Splits the map into N sequential bands, skipping a specified number of pixels at the top.
func generate_map_bands(map_length: int, num_bands: int, top_padding: int = 0) -> Array[Dictionary]:
	var bands: Array[Dictionary] = []
	
	if num_bands <= 0 or map_length <= 0:
		return bands
		
	# 1. Calculate the actual space available for bands
	var effective_length : int = map_length - top_padding
	
	# Safety check: if padding is larger than the map itself, no bands can be generated
	if effective_length <= 0:
		return bands
		
	# Prevent creating more bands than there are available pixels
	num_bands = min(num_bands, effective_length)
	
	# 2. Divide the effective space
	var base_size : int = effective_length / num_bands
	var remainder : int = effective_length % num_bands
	
	# 3. Start generating after the padding
	var current_start : int = top_padding
	
	for i in range(num_bands):
		var band_size: int = base_size
		
		# Distribute the remainder 1 pixel at a time to the first few bands
		if remainder > 0:
			band_size += 1
			remainder -= 1
			
		var current_end : int = current_start + band_size - 1
		var band : Dictionary[String, int] = {"start": current_start, "end": current_end}
		bands.append(band)
		
		current_start = current_end + 1
		
	return bands

func calculate_river_noises(noise_seed: int) -> Dictionary[int, Array]:
	var result: Dictionary[int, Array] = {}

	for band_id in bands_rivers.keys():
		var river_count: int = bands_rivers[band_id]
		var seeds: Array[int] = []

		for i in river_count:
			# Combine base seed, band, and river index deterministically
			var combined: int = noise_seed
			combined ^= band_id * 374761393
			combined ^= i * 668265263

			var river_seed: int = _hash_int(combined)
			seeds.append(river_seed)

		result[band_id] = seeds

	return result

func _hash_int(value: int) -> int:
	# 32-bit integer hash (deterministic)
	value = ((value >> 16) ^ value) * 0x45d9f3b
	value = ((value >> 16) ^ value) * 0x45d9f3b
	value = (value >> 16) ^ value
	return value & 0x7fffffff  # keep positive
