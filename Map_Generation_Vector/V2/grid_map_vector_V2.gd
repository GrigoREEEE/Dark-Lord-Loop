extends Node2D



@export var river_mode_selector: OptionButton
@export var save_button: Button
@export var lake_debug_button: Button

# River Display Mode
enum RiverDisplayMode {
	NORMAL,
	DEBUG_SEGMENTS,
	HIDDEN
}

var show_lakes: bool = false

var current_river_mode: RiverDisplayMode = RiverDisplayMode.NORMAL

# CONFIGURATION
@export var noise_seed: int
@export var reference_width = 400.0
@export var cell_size: int = 1
@export var grid_width: int = 400
@export var grid_height: int = 600

# Main River Generation
@export var mouth_segments: int = 3
var to_merge: int = 0
@export var water_level: float = 0.15 # Elevations below this are drawn as water
@export var delta_streams: Dictionary[int, int] = {3:1,2:1,1:1}


# --- Data Holders ---
var inverse_land_map: Dictionary = {} # Dictionary[int, Array[Vector2]]
var current_land_map: Dictionary = {} # Dictionary[Vector2,int]
var terrain_data: Dictionary = {} # Dictionary[Vector2, float]
var _ocean_mask: Dictionary = {} # Dictionary[Vector2, bool]
var _beach_mask: Dictionary = {} # Dictionary[Vector2, bool]
var _delta_mask: Dictionary = {} # Dictionary[Vector2, bool]
var _rivers: Array[River] = []

func _ready():
	reference_width = 400
	setup_buttons()
	add_fps_counter()
	noise_seed = 663202794#randi()
	print("Noise seed is: %s" % noise_seed)
	
	var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var _winding_noise: FastNoiseLite = FastNoiseLite.new()
	
	var res_scale = int(grid_width/reference_width)
	Profiler.start("total terrain generation")
	var world_gen: Terrain_Generator = Terrain_Generator.new()
	var south_islands: South_Islands = South_Islands.new()
	var ice_wall: Ice_Wall = Ice_Wall.new()

	
	terrain_data = world_gen.generate_height_map(grid_width, grid_height, noise_seed, res_scale)
	terrain_data = south_islands.apply_southern_islands(terrain_data, grid_width, grid_height, 150, 15, 60, noise_seed, res_scale)
	terrain_data = ice_wall.apply_ice_wall(terrain_data, grid_width, noise_seed, res_scale)
	Profiler.end("total terrain generation")
	handle_rivers(res_scale)

	update_map_visuals()
	#save_map_to_png("res://image.png")

func handle_rivers(res_scale):
	Profiler.start("total river generation")
	var river_gen: River_Generator = River_Generator.new()
	var erosion: River_Erosion = River_Erosion.new()
	var ocean_id: Ocean_Identification = Ocean_Identification.new()
	var beach_id: Beach_Identification = Beach_Identification.new()
	var river_expander: River_Widener = River_Widener.new()
	var delta_maker: Delta = Delta.new()
	var my_river: River
	
	## Check where the ocean abd the beach are
	_ocean_mask = ocean_id.ocean_vs_land(terrain_data, grid_width, grid_height)
	_beach_mask = beach_id.generate_beach_mask(_ocean_mask, 5, res_scale)


		
	## Generate the River
	my_river = river_gen.generate_natural_river(grid_width, grid_height, _ocean_mask, noise_seed, res_scale)
	if check_river_breach(my_river, _beach_mask, mouth_segments):
		print("River touches beach!")
		noise_seed = randi()
		print("New noise seed is: %s" % noise_seed)
		my_river = null
		handle_rivers(res_scale)
	else:
		## Apply Erosion
		erosion.apply_river_erosion(terrain_data, my_river, 29.0, 30.0, 0.85, 0.2, res_scale) #5, 30, 0.9, 0.1)
		## Check where the ocean is again (due to erosion)
		_ocean_mask = ocean_id.ocean_vs_land(terrain_data, grid_width, grid_height)
		## Remove the river from the ocean
		river_gen.clean_river_path(my_river, _ocean_mask)
		## Break the river into segments
		my_river.create_segments(10 * res_scale)
		to_merge = my_river.resegment_delta(mouth_segments, 1 * res_scale) + 1
		
		## Expand the river
		river_expander.widen_river_iterative(terrain_data, my_river, _ocean_mask, mouth_segments, 20.0 * res_scale, 1.0 * res_scale)
		river_expander.merge_segments(my_river, to_merge)
		#_delta_mask = delta_maker.create_delta_mask(my_river, grid_width, grid_height)
		_delta_mask = delta_maker.create_delta_mask2(my_river)
		## Make the delta
		delta_maker.generate_delta(my_river, _ocean_mask, delta_streams, noise_seed)
		delta_maker.naturalize_delta_islands(terrain_data, my_river, _delta_mask)
		delta_maker.erode_delta_edges(terrain_data, _delta_mask)
		
		_rivers = []
		_rivers.append(my_river)
		Profiler.end("total river generation")


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

# Cache the texture so we don't regenerate it every frame
var _map_texture: ImageTexture

func update_map_visuals():
	# 1. Create a blank image buffer
	var img = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	
	# --- 1. SET TERRAIN PIXELS ---
	if not terrain_data.is_empty() and not _ocean_mask.is_empty():
		for pos in terrain_data:
			if pos.x < 0 or pos.y < 0 or pos.x >= grid_width or pos.y >= grid_height:
				continue
			
			var elevation = terrain_data[pos]
			var is_ocean = _ocean_mask.get(pos, false)
			# Combine real beach mask and delta mask for the sandy look
			var is_real_beach = _beach_mask.get(pos, false) or _delta_mask.get(pos, false)
			
			var color = _get_layered_color(elevation, is_ocean, is_real_beach)
			img.set_pixel(int(pos.x), int(pos.y), color)

	# --- 2. SET RIVER PIXELS ---
	if not _rivers.is_empty() and current_river_mode != RiverDisplayMode.HIDDEN:
		
		var base_river_color: Color = Color("2d5e87")
		
		for river in _rivers:
			match current_river_mode:
				
				RiverDisplayMode.DEBUG_SEGMENTS:
					if not river.segments.is_empty():
						for i in range(river.segments.size()):
							var segment = river.segments[i]
							# Rainbow logic for segments
							var hue: float = float(i % 8) / 8.0
							var draw_color: Color = Color.from_hsv(hue, 0.8, 1.0)
							
							for pos in segment:
								if pos.x >= 0 and pos.y >= 0 and pos.x < grid_width and pos.y < grid_height:
									img.set_pixel(int(pos.x), int(pos.y), draw_color)
					else:
						_draw_simple_river_path(img, river, Color.RED)

				RiverDisplayMode.NORMAL:
					if not river.segments.is_empty():
						for segment in river.segments:
							for pos in segment:
								if pos.x >= 0 and pos.y >= 0 and pos.x < grid_width and pos.y < grid_height:
									img.set_pixel(int(pos.x), int(pos.y), base_river_color)
					else:
						_draw_simple_river_path(img, river, base_river_color)


	# 4. Create or Update the GPU Texture
	if _map_texture:
		_map_texture.update(img)
	else:
		_map_texture = ImageTexture.create_from_image(img)
	
	# 5. Tell Godot to repaint
	queue_redraw()

# --- Helper to avoid code duplication ---
func _draw_simple_river_path(img: Image, river, color: Color):
	for pos in river.river_path:
		if pos.x >= 0 and pos.y >= 0 and pos.x < grid_width and pos.y < grid_height:
			img.set_pixel(int(pos.x), int(pos.y), color)

func _draw():
	if _map_texture:
		draw_texture_rect(_map_texture, Rect2(0, 0, grid_width * cell_size, grid_height * cell_size), false)


func _get_layered_color(e: float, is_ocean: bool, is_real_beach: bool) -> Color:
	if is_ocean:
		if e < -0.5: 
			return Color("1e3852") # Deep Ocean
		else:
			return Color("2d5e87") # Shallow Water
	elif is_real_beach and e < 0.18:
		return Color("d6c38e") # Real Sand (Near Ocean)
	else:
		if e < 0.07:
			return Color("4b5e32") # Swamp
		if (e >= 0.07) and (e < 0.12):
			return Color("7a8a4b") # Marsh
		if (e >= 0.12) and (e < 0.28):
			return Color("5d9e44") # Flat Fields
		if (e >= 0.28) and (e < 0.45):
			return Color("3e7a2b") # Slightly more bendy fields
		if (e >= 0.45) and (e < 0.55):
			return Color("5c5847")  # Small Hills
		if (e >= 0.55) and (e < 0.70):
			return Color("4d453b")  # Big Hills
		if (e >= 0.70) and (e < 0.82):
			return Color("8a9da1")  # Near Mountains
		if (e >= 0.82) and (e < 0.98):
			return Color("c9c9c9ff")  # Peaks
		if (e >= 0.98):
			return Color(1.0, 1.0, 1.0, 1.0)  # Absolute peaks
		else:
			return Color(0.824, 0.001, 0.824, 1.0)  # Error
		
func add_fps_counter():
	var canvas_layer = CanvasLayer.new()
	add_child(canvas_layer)
	var fps_label = Label.new()
	canvas_layer.add_child(fps_label)
	fps_label.position = Vector2(10, 10)
	fps_label.modulate = Color(0, 1, 0) # Green text
	get_tree().process_frame.connect(func():
		var fps = Engine.get_frames_per_second()
		fps_label.text = "FPS: " + str(fps)
	)

func setup_buttons():
	# Setup the dropdown options
	river_mode_selector.add_item("Normal Rivers", RiverDisplayMode.NORMAL)
	river_mode_selector.add_item("Debug Segments", RiverDisplayMode.DEBUG_SEGMENTS)
	river_mode_selector.add_item("Hide Rivers", RiverDisplayMode.HIDDEN)
	river_mode_selector.item_selected.connect(_on_river_mode_changed)
	save_button.pressed.connect(_on_save_button_pressed)
	
	
func _on_river_mode_changed(index: int):
	current_river_mode = river_mode_selector.get_item_id(index) as RiverDisplayMode
	update_map_visuals()

func save_map_to_disk():
	if _map_texture == null:
		print("Error: No map texture to save.")
		return

	# 1. Get the image data from the texture
	var img = _map_texture.get_image()
	
	# 2. Ensure the directory exists
	var base_dir = "res://pictures/"
	# specific for exported games use: var base_dir = "user://pictures/"
	
	var dir = DirAccess.open("res://")
	if not dir.dir_exists(base_dir):
		# Create the directory if it doesn't exist
		var err = dir.make_dir_recursive(base_dir)
		if err != OK:
			print("Error creating directory: ", err)
			return

	# 3. Generate a unique filename using the current time
	var time = Time.get_datetime_dict_from_system()
	var filename = "map_%04d-%02d-%02d_%02d-%02d-%02d.png" % [
		time.year, time.month, time.day, 
		time.hour, time.minute, time.second
	]
	
	var full_path = base_dir + filename
	
	# 4. Save the file
	var err = img.save_png(full_path)
	
	if err == OK:
		print("Map saved successfully to: ", full_path)
		# Refresh the filesystem so the new file appears in the FileSystem dock (Editor only)
	else:
		print("Failed to save map. Error code: ", err)

func _on_save_button_pressed():
	save_map_to_disk()
