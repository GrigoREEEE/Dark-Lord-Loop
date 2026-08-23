extends Node

class_name River_Handler

var mouth_segments: int = 3 #number of the original main river segments that get the mouth bonus
var to_merge: int = 0 #number of the main river segments we merge to form delta
var bands_quantity: int = 5
var chunk_size: int = 7
var delta_streams: Dictionary[int, int] = {3:1,2:2,1:2} #size and number of streams that form the delta
var bands_rivers: Dictionary[int, int] = {0:1, 1:1, 6:1, 7:1}
var main_river_erosion: Dictionary[String, float] = {
"start radius": 80.0,
"end radius": 50.0,
"start erosion": 0.7,
"end erosion": 0.85
}
var side_river_erosion: Dictionary[String, float] = {
"start radius": 20.0,
"end radius": 30.0,
"start erosion": 0.5,
"end erosion": 0.6
}

func handle_rivers(
	world_data: World_Data,
	map_width: int,
	map_height: int, 
	map_data: Dictionary[String, Dictionary], 
	global_ocean : Water_Pool,
	mask_data: Dictionary[String, Dictionary],
	noise_seed: int, 
	res_scale: float
):
	
	var river_system : Array[River] = []
	var cells_set: Array[Dictionary] = generate_map_grid(map_width, map_height, 3, 5, 20 * res_scale)
	
	var bands_keys: Array[int] = bands_rivers.keys()
	var river_noises: Dictionary[int, Array] = calculate_river_noises(noise_seed)
	for i in bands_keys:
		var river_to_add : int = bands_rivers[i] 
		while river_to_add > 0:
			var selecte_noise: int = river_noises[i][(bands_rivers[i]-river_to_add)]
			river_to_add -= 1
			var cell: Dictionary[String, int] = cells_set[i]
			# Pass map_data instead of terrain_data
			var river: River = setup_river("side", world_data, cell)
			river_system.append(river)
	return river_system

func setup_river(
	type: String,
	world_data: World_Data,
	cell : Dictionary[String, int]):
	
	Profiler.start("total river generation")
	var Source_Selector : Source_Selection = Source_Selection.new()
	var river_gen: River_Generator = River_Generator.new()
	var small_river_gen: Small_River_Generator = Small_River_Generator.new()
	var erosion: River_Erosion = River_Erosion.new()
	var ocean_id: Ocean_Identification = Ocean_Identification.new()
	var beach_id: Beach_Identification = Beach_Identification.new()
	var river_expander: River_Widener = River_Widener.new()
	var delta_maker: Delta = Delta.new()
	var delta_generator: Delta_V2 = Delta_V2.new()
	var my_river: River
	var river_start_pos : Vector2 = Vector2.ZERO
	var river_direction : Vector2 = Vector2.ZERO
	Profiler.start("River Point & Direction Selection")
	if type == "main":
		river_start_pos = Vector2(int(world_data.grid_width/2),0)
		river_direction = Vector2.DOWN
	else:
		# Route to map_data["terrain"]
		river_start_pos =  Source_Selector.select_river_source(world_data, cell)
		river_direction = get_random_river_direction((world_data.noise_seed + cell["start_y"] + cell["end_y"]))
	Profiler.end("River Point & Direction Selection")
	
	
	## Generate the River
	Profiler.start("River Path Generation")
	# Pass map_data["river"] instead of mask_data["river"]
	if type == "main": 
		my_river = river_gen.generate_natural_river(world_data, river_start_pos, river_direction)
	else:
		print("SMall river starts at %s" % river_start_pos)
		my_river = small_river_gen.generate_small_natural_river(world_data, river_start_pos)
	Profiler.end("River Path Generation")
	Profiler.start("River Breach Check")
	if check_river_breach(my_river, world_data, mouth_segments):
		Profiler.end("River Breach Check")
		world_data.noise_seed = randi()
		print("New river noise seed is: %s" % world_data.noise_seed)
		# Pass map_data
		return setup_river(type, world_data, cell)
	else:
		Profiler.end("River Breach Check")
		
		## Apply Erosion
		Profiler.start("Erosion")
		var erosion_data_to_use : Dictionary[String, float]
		if type == "main":
			erosion_data_to_use = world_data.main_river_erosion
			world_data.mask_data["valley_outer"] = erosion.generate_river_valley_mask(my_river.river_path, world_data.main_river_erosion, 20 * world_data.res_scale)
			erosion.apply_target_height_erosion(world_data, 0.2, my_river.river_path.size())
		#else:
			#erosion_data_to_use = side_river_erosion
		#mask_data["vally_outer"] = erosion.generate_river_valley_mask(my_river.river_path, erosion_data_to_use, 20 * res_scale)
		#erosion.apply_target_height_erosion(map_data["terrain"], mask_data["vally_outer"], mask_data["ocean"], 0.2, erosion_data_to_use, my_river.river_path.size())
		Profiler.end("Erosion")
		
		# --- IN-PLACE DICTIONARY UPDATES ---
		Profiler.start("Ocean Mask Making")
		# Route to map_data["terrain"]
		ocean_id.ocean_vs_land(world_data)
		Profiler.end("Ocean Mask Making")
		Profiler.start("Beach Mask Making")
		beach_id.generate_beach_mask(world_data)
		Profiler.end("Beach Mask Making")
		# Remove the river from the ocean
		Profiler.start("River Path Cleaning")
		river_gen.clean_river_path(my_river, world_data.mask_data["ocean"])
		Profiler.end("River Path Cleaning")
		## Break the river into segments
		Profiler.start("River Segmenting")
		my_river.create_segments(10 * world_data.res_scale)
		Profiler.end("River Segmenting")
		if type == "main":
			Profiler.start("River Delta Resegment")
			#to_merge = my_river.resegment_delta(mouth_segments, 1 * world_data.res_scale) + 1
			Profiler.end("River Delta Resegment")
			Profiler.start("River Expanding")
			#river_expander.widen_river_iterative(world_data, my_river, 3.0 * world_data.res_scale, 0.5 * world_data.res_scale)
			Profiler.end("River Expanding")
			Profiler.start("River Delta Generation")
			## Scale the length and interval by res_scale so it fits any map size
			var max_stream_length = int(100 * world_data.res_scale)
			var branch_interval = int(2 * world_data.res_scale)
			var regions_back = 2
			
			delta_generator.generate_delta(
				world_data,
				my_river,
				max_stream_length,
				branch_interval,
				regions_back
			)
			Profiler.end("River Delta Generation")

		Profiler.end("total river generation")
		# Pass map_data["river"] instead of mask_data["river"]
		add_river_regions_to_system_mask(my_river, world_data.map_data["river"])
		return my_river

# Updated parameter name to river_data
func add_river_regions_to_system_mask(river: River, river_data: Dictionary) -> void:
	if river == null or river.segments.is_empty():
		return
		
	# Iterate through all the Region objects that make up the river
	for region: Region in river.segments:
		# Iterate through all the individual grid coordinates in the Region
		for cell: Vector2 in region.points:
			# Map the coordinate directly to the specific Region object
			river_data[cell] = region


	
# Checks if any "non-mouth" segment has accidentally grown into the beach.
# Returns TRUE if a breach is detected (bad state).
# Returns FALSE if the river is contained correctly.
func check_river_breach(river: River, world_data: World_Data, mouth_segments_count: int) -> bool:
	var beach_mask: Dictionary = world_data.mask_data["beach"]
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
	return grid
	
# Creates a dense boolean mask where EVERY cell on the map is assigned true or false.
func create_full_river_mask(river_data: Dictionary, map_width: int, map_height: int) -> Dictionary:
	var river_mask: Dictionary = {}
	
	# Iterate through every single cell on the map grid
	for y in range(map_height):
		for x in range(map_width):
			var cell := Vector2(x, y)
			
			# Dictionary.has() returns true if the key exists in river_data, false otherwise.
			# This perfectly maps to your requirement.
			river_mask[cell] = river_data.has(cell)
			
	return river_mask
	
	
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
