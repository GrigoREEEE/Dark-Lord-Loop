extends Node

class_name River_Handler

var mouth_segments: int = 3 #number of the original main river segments that get the mouth bonus
var to_merge: int = 0 #number of the main river segments we merge to form delta
var bands_quantity: int = 5
var delta_streams: Dictionary[int, int] = {3:1,2:1,1:1} #size and number of streams that form the delta
var bands_rivers: Dictionary[int, int] = {0:1, 1:1, 2:1, 3:1, 4:1}
var main_river_erosion: Dictionary[String, float] = {
"start radius": 29.0,
"end radius": 50.0,
"start erosion": 0.85,
"end erosion": 0.75
}
var side_river_erosion: Dictionary[String, float] = {
"start radius": 5.0,
"end radius": 10.0,
"start erosion": 0.6,
"end erosion": 0.1
}

func handle_rivers(
	map_width: int,
	map_height: int, 
	terrain_data: Dictionary[Vector2, float], 
	global_ocean : Pool,
	mask_data: Dictionary[String, Dictionary],
	noise_seed: int, 
	res_scale: float
):
	
	var river_system : Array[River] = []
	var cells_set: Array[Dictionary] = generate_map_grid(map_width, map_height, 3, 5, 20 * res_scale)
	var bands_keys: Array[int] = bands_rivers.keys()
	var river_noises: Dictionary[int, Array] = calculate_river_noises(noise_seed)
	for i in bands_keys:
		var river_to_add : int = bands_rivers[i] # number of rivers we need to add per band
		while river_to_add > 0:
			var selecte_noise: int = river_noises[i][(bands_rivers[i]-river_to_add)]
			river_to_add -= 1
			var cell: Dictionary[String, int] = cells_set[i]
			var river: River = setup_river("side", map_width, map_height, terrain_data, global_ocean, mask_data, cell, selecte_noise, res_scale)
			river_system.append(river)
	return river_system

func setup_river(
	type: String,
	map_width: int,
	map_height: int, 
	terrain_data: Dictionary[Vector2, float], 
	global_ocean : Pool,
	mask_data: Dictionary[String, Dictionary], 
	cell : Dictionary[String, int],
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
	Profiler.start("River Point Selection")
	if type == "main":
		river_start_pos = Vector2(map_width/2,0)
		river_direction = Vector2.DOWN
	else:
		river_start_pos =  Source_Selector.select_river_source(terrain_data, mask_data["ocean"], cell, noise_seed)
		river_direction = get_random_river_direction((noise_seed + cell["start_y"] + cell["end_y"]))
	Profiler.end("River Point Selection")
	# --- IN-PLACE DICTIONARY UPDATES ---
	Profiler.start("Ocean Mask Making")
	var temp_ocean = ocean_id.ocean_vs_land(terrain_data, map_width, map_height, global_ocean)
	mask_data["ocean"].clear()
	mask_data["ocean"].merge(temp_ocean)
	Profiler.end("Ocean Mask Making")
	Profiler.start("Beach Mask Making")
	var temp_beach = beach_id.generate_beach_mask(mask_data["ocean"], map_width, map_height, 5, res_scale)
	mask_data["beach"].clear()
	mask_data["beach"].merge(temp_beach)
	Profiler.end("Beach Mask Making")
	
	
	## Generate the River
	Profiler.start("River Path Generation")
	my_river = river_gen.generate_natural_river(map_width, map_height, global_ocean, mask_data["river"], noise_seed, river_start_pos, river_direction, res_scale)
	Profiler.end("River Path Generation")
	Profiler.start("River Breach Check")
	if check_river_breach(my_river, mask_data["beach"], mouth_segments):
		noise_seed = randi()
		print("New river noise seed is: %s" % noise_seed)
		return setup_river(type, map_width, map_height, terrain_data, global_ocean, mask_data, cell, noise_seed, res_scale)
	else:
		Profiler.end("River Breach Check")
		Profiler.start("Erosion")
		## Apply Erosion
		if type == "main":
			#erosion.apply_river_erosion(terrain_data, my_river, main_river_erosion, res_scale) #5, 30, 0.9, 0.1)
			var msk = erosion.generate_river_valley_mask(my_river.river_path, main_river_erosion["start radius"], main_river_erosion["end radius"])
			erosion.apply_target_height_erosion(terrain_data, msk, mask_data["ocean"], 0.2, main_river_erosion)
		else:
			var msk = erosion.generate_river_valley_mask(my_river.river_path, side_river_erosion["start radius"], side_river_erosion["end radius"])
			erosion.apply_target_height_erosion(terrain_data, msk, mask_data["ocean"], 0.2, side_river_erosion)
		Profiler.end("Erosion")
		## Check where the ocean is again (due to erosion)
		mask_data["ocean"] = ocean_id.ocean_vs_land(terrain_data, map_width, map_height, global_ocean)
		## Remove the river from the ocean
		Profiler.start("River Path Cleaning")
		river_gen.clean_river_path(my_river, mask_data["ocean"])
		Profiler.end("River Path Cleaning")
		## Break the river into segments
		my_river.create_segments(10 * res_scale)
		if type == "main":
			Profiler.start("River Resegment")
			to_merge = my_river.resegment_delta(mouth_segments, 1 * res_scale) + 1
			Profiler.end("River Resegment")
			## Expand the river
			Profiler.start("River Expanding")
			river_expander.widen_river_iterative(terrain_data, my_river, mask_data["ocean"], mouth_segments, 20.0 * res_scale, 1.0 * res_scale)
			Profiler.end("River Expanding")
			Profiler.start("River merge")
			river_expander.merge_segments(my_river, to_merge)
			Profiler.end("River merge")
			# --- IN-PLACE DICTIONARY UPDATE ---
			Profiler.start("River Delta")
			var temp_delta = delta_maker.create_delta_mask2(my_river)
			mask_data["delta"].clear()
			mask_data["delta"].merge(temp_delta)
			## Make the delta
			delta_maker.generate_delta(my_river, mask_data["ocean"], delta_streams, noise_seed)
			delta_maker.naturalize_delta_islands(terrain_data, my_river, mask_data["delta"])
			delta_maker.erode_delta_edges(terrain_data, mask_data["delta"], noise_seed)
			# --- IN-PLACE DICTIONARY UPDATE ---
			temp_delta = delta_maker.create_delta_mask2(my_river,3)
			mask_data["delta"].clear()
			mask_data["delta"].merge(temp_delta)
			Profiler.end("River Delta")
		
		Profiler.end("total river generation")
		add_river_regions_to_system_mask(my_river, mask_data["river"])
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
	var random_angle = rng.randf_range(0 + PI/8, PI - PI/8)
	
	return Vector2.from_angle(random_angle)

# Splits the map into a 2D grid of rows and columns, skipping a specified number of pixels at the top.
# Returns an Array of Dictionaries, each containing start_x, end_x, start_y, and end_y.
func generate_map_grid(
	map_width: int, 
	map_height: int, 
	columns: int, 
	rows: int, 
	top_padding: int = 0
) -> Array[Dictionary]:
	
	var grid: Array[Dictionary] = []
	
	if columns <= 0 or rows <= 0 or map_width <= 0 or map_height <= 0:
		return grid
		
	# --- 1. Y-AXIS (ROWS) CALCULATIONS ---
	var effective_height: int = map_height - top_padding
	if effective_height <= 0:
		return grid # Padding consumed the entire map
		
	rows = min(rows, effective_height) # Prevent more rows than available pixels
	
	var base_h: int = effective_height / rows
	var rem_h: int = effective_height % rows
	
	var row_bounds: Array[Dictionary] = []
	var current_y: int = top_padding
	
	for r in range(rows):
		var h: int = base_h + (1 if r < rem_h else 0)
		row_bounds.append({"start": current_y, "end": current_y + h - 1})
		current_y += h

	# --- 2. X-AXIS (COLUMNS) CALCULATIONS ---
	columns = min(columns, map_width) # Prevent more columns than available pixels
	
	var base_w: int = map_width / columns
	var rem_w: int = map_width % columns
	
	var col_bounds: Array[Dictionary] = []
	var current_x: int = 0
	
	for c in range(columns):
		var w: int = base_w + (1 if c < rem_w else 0)
		col_bounds.append({"start": current_x, "end": current_x + w - 1})
		current_x += w

	# --- 3. COMBINE INTO GRID CELLS ---
	for r_bound in row_bounds:
		for c_bound in col_bounds:
			var to_append: Dictionary[String, int] = {
				"start_x": c_bound["start"],
				"end_x": c_bound["end"],
				"start_y": r_bound["start"],
				"end_y": r_bound["end"]
			}
			grid.append(to_append)
	print(grid)
	return grid

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

# Adds every cell of a river to a global mask, mapping coordinates directly to the specific Region object.
func add_river_regions_to_system_mask(river: River, region_mask: Dictionary) -> void:
	if river == null or river.segments.is_empty():
		return
		
	# Iterate through all the Region objects that make up the river
	for region: Region in river.segments:
		# Iterate through all the individual grid coordinates in the Region
		for cell: Vector2 in region.points:
			# Map the coordinate directly to the specific Region object
			region_mask[cell] = region
