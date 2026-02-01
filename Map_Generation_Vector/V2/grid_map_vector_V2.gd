extends Node2D

# CONFIGURATION
@export var noise_seed : int


@export var debug_river_segments: bool = false

@export var REFERENCE_WIDTH = 400.0
@export var cell_size: int
@export var grid_width : int
@export var grid_height : int

# Add this enum at the top of your class
enum DisplayType {
	LAND_TYPES,
	HEIGHT_MAP
}

@export var display_type: DisplayType = DisplayType.LAND_TYPES

# --- Data Holders ---
var inverse_land_map: Dictionary = {} # Dictionary[int, Array[Vector2]]
var current_land_map: Dictionary = {} # Dictionary[Vector2,int]
var terrain_data: Dictionary = {} # Dictionary[Vector2, float]
var _ocean_mask: Dictionary = {} # Dictionary[Vector2, bool]
var _beach_mask: Dictionary = {} # Dictionary[Vector2, bool]
var _rivers: Array[River] = []

func _ready():
	REFERENCE_WIDTH = 400.0
	noise_seed = randi()
	add_fps_counter()
	var _rng = RandomNumberGenerator.new()
	var _winding_noise = FastNoiseLite.new()
	
	var res_scale = int(grid_width/REFERENCE_WIDTH)
	
	var world_gen : Terrain_Generator = Terrain_Generator.new()
	var south_islands : South_Islands = South_Islands.new()
	var ice_wall : Ice_Wall = Ice_Wall.new()

	
	terrain_data = world_gen.generate_height_map(grid_width, grid_height, noise_seed, res_scale)
	terrain_data = south_islands.apply_southern_islands(terrain_data, grid_width, grid_height, 150, 15, 60, noise_seed, res_scale)
	terrain_data = ice_wall.apply_ice_wall(terrain_data, grid_width, noise_seed, res_scale)
	
	handle_rivers(res_scale)

	update_map_visuals()
	#save_map_to_png("res://image.png")
	
func handle_rivers(res_scale):
	var river_gen : River_Generator = River_Generator.new()
	var erosion : River_Erosion = River_Erosion.new()
	var ocean_id : Ocean_Identification = Ocean_Identification.new()
	var beach_id : Beach_Identification = Beach_Identification.new()
	var river_expander : River_Widener = River_Widener.new()
	var my_river : River
	const mouth_segments : int = 3
	## Check where the ocean abd the beach are
	_ocean_mask = ocean_id.ocean_vs_land(terrain_data, grid_width, grid_height)
	_beach_mask = beach_id.generate_beach_mask(_ocean_mask, 5, res_scale)


		
	## Generate the River
	my_river = river_gen.generate_natural_river(grid_width, grid_height, _ocean_mask, res_scale)
	if check_river_breach(my_river, _beach_mask, mouth_segments):
		handle_rivers(res_scale)
	else:
		## Apply Erosion
		erosion.apply_river_erosion(terrain_data, my_river, 29.0, 30.0, 0.85, 0.2, res_scale) #5, 30, 0.9, 0.1)
		## Check where the ocean is again (due to erosion)
		_ocean_mask = ocean_id.ocean_vs_land(terrain_data, grid_width, grid_height)
		## Remove the river from the ocean
		river_gen.clean_river_path(my_river, _ocean_mask)
		## Break the river into segments
		my_river.create_segments(20)
		## Expand the river
		river_expander.widen_river_iterative(terrain_data, my_river, _ocean_mask, _beach_mask, mouth_segments, 1.5 * res_scale, 2.5 * res_scale)

		_rivers = []
		_rivers.append(my_river)

# Configurable settings for visualization
@export var water_level: float = 0.15 # Elevations below this are drawn as water

# Checks if any "non-mouth" segment has accidentally grown into the beach.
# Returns TRUE if a breach is detected (bad state).
# Returns FALSE if the river is contained correctly.
func check_river_breach(river: River, beach_mask: Dictionary, mouth_segments_count: int) -> bool:
	if river.segments.is_empty():
		return false
		
	# Determine the boundary.
	# Any segment with an index LESS than this is considered "Inland" and must not touch the beach.
	var start_of_mouth_index = max(0, river.segments.size() - mouth_segments_count)
	
	# Iterate only through the inland segments
	for i in range(start_of_mouth_index):
		var segment = river.segments[i]
		
		for cell in segment:
			# If this cell is marked as beach in the mask
			if beach_mask.get(cell, false) == true:
				# We found a breach!
				# Optional: Print debug info to know where it happened
				# print("River Breach detected at segment ", i, " position ", cell)
				return true
				
	return false

# Cache the texture so we don't regenerate it every frame
var _map_texture: ImageTexture

func update_map_visuals():
	# 1. Create a blank image buffer (Fast CPU operation)
	var img = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	
	# --- 1. SET TERRAIN PIXELS ---
	if not terrain_data.is_empty() and not _ocean_mask.is_empty():
		for pos in terrain_data:
			# Ensure we don't write outside the image bounds
			if pos.x < 0 or pos.y < 0 or pos.x >= grid_width or pos.y >= grid_height:
				continue
				
			var elevation = terrain_data[pos]
			var is_ocean = _ocean_mask.get(pos, false)
			var is_real_beach = _beach_mask.get(pos, false)
			
			var color = _get_layered_color(elevation, is_ocean, is_real_beach)
			
			# Set the single pixel
			img.set_pixel(int(pos.x), int(pos.y), color)

	# --- 2. SET RIVER PIXELS ---
	if not _rivers.is_empty():
		var base_river_color = Color("407badff") #Color("2d5e87")
		
		for river in _rivers:
			if not river.segments.is_empty():
				# Iterate segments for debug colors
				for i in range(river.segments.size()):
					var segment = river.segments[i]
					var draw_color = base_river_color
					
					if debug_river_segments:
						var hue = float(i % 8) / 8.0
						draw_color = Color.from_hsv(hue, 0.8, 1.0)
					
					for pos in segment:
						if pos.x >= 0 and pos.y >= 0 and pos.x < grid_width and pos.y < grid_height:
							img.set_pixel(int(pos.x), int(pos.y), draw_color)
			else:
				# Fallback path
				var path_color = base_river_color
				if debug_river_segments:
					path_color = Color.RED
				
				for pos in river.river_path:
					if pos.x >= 0 and pos.y >= 0 and pos.x < grid_width and pos.y < grid_height:
						img.set_pixel(int(pos.x), int(pos.y), path_color)

	# 3. Create or Update the GPU Texture
	# This sends the data to the GPU in one block
	if _map_texture:
		_map_texture.update(img)
	else:
		_map_texture = ImageTexture.create_from_image(img)
	
	# 4. Tell Godot to repaint
	queue_redraw()

func _draw():
	# Now _draw is incredibly cheap: it just draws one texture
	if _map_texture:
		draw_texture_rect(_map_texture, Rect2(0, 0, grid_width * cell_size, grid_height * cell_size), false)

# --- YOUR EXISTING HELPER (Unchanged) ---
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
