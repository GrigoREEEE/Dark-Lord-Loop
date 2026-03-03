extends Node2D



@export var river_mode_selector: OptionButton
@export var save_button: Button

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

# Water_Display
@export var water_level: float = 0.15 # Elevations below this are drawn as water



# --- Data Holders ---
var terrain_data: Dictionary[Vector2, float] = {} # Dictionary[Vector2, float]
var _ocean_mask: Dictionary[Vector2, bool] = {} # Dictionary[Vector2, bool]
var _beach_mask: Dictionary[Vector2, bool] = {} # Dictionary[Vector2, bool]
var _delta_mask: Dictionary[Vector2, bool] = {} # Dictionary[Vector2, bool]
var _rivers: Array[River] = []

func _ready():
	reference_width = 400
	#setup_buttons()
	#add_fps_counter()
	noise_seed = 663202794#randi()
	print("Noise seed is: %s" % noise_seed)
	
	var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var _winding_noise: FastNoiseLite = FastNoiseLite.new()
	
	var res_scale = int(grid_width/reference_width)
	Profiler.start("total terrain generation")
	
	var world_gen: Terrain_Generator = Terrain_Generator.new()
	var south_islands: South_Islands = South_Islands.new()
	var ice_wall: Ice_Wall = Ice_Wall.new()
	var ocean_id: Ocean_Identification = Ocean_Identification.new()
	var beach_id: Beach_Identification = Beach_Identification.new()
	var river_handler : River_Handler = River_Handler.new()

	
	terrain_data = world_gen.generate_height_map(grid_width, grid_height, noise_seed, res_scale)
	terrain_data = south_islands.apply_southern_islands(terrain_data, grid_width, grid_height, 150, 15, 60, noise_seed, res_scale)
	terrain_data = ice_wall.apply_ice_wall(terrain_data, grid_width, noise_seed, res_scale)
	Profiler.end("total terrain generation")
	
	## Check where the ocean abd the beach are
	_ocean_mask = ocean_id.ocean_vs_land(terrain_data, grid_width, grid_height)
	_beach_mask = beach_id.generate_beach_mask(_ocean_mask, 5, res_scale)
	
	var main_river : River = river_handler.setup_river("main", grid_width, grid_height, terrain_data, _ocean_mask, _beach_mask, _delta_mask, {}, noise_seed, res_scale)
	_rivers.append(main_river)
	var minor_rivers : Array[River] = river_handler.handle_rivers(grid_width, grid_height, terrain_data, _ocean_mask, _beach_mask, _delta_mask, noise_seed, res_scale)
	_rivers.append_array(minor_rivers)
	update_map_visuals()
	#save_map_to_png("res://image.png")

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
							var region: Region = river.segments[i] # Unpack as Region
							# Rainbow logic for segments
							var hue: float = float(i % 8) / 8.0
							var draw_color: Color = Color.from_hsv(hue, 0.8, 1.0)
							
							# Iterate through the Region's points array
							for pos in region.points:
								if pos.x >= 0 and pos.y >= 0 and pos.x < grid_width and pos.y < grid_height:
									img.set_pixel(int(pos.x), int(pos.y), draw_color)
					else:
						_draw_simple_river_path(img, river, Color.RED)

				RiverDisplayMode.NORMAL:
					if not river.segments.is_empty():
						for region: Region in river.segments: # Type hint as Region
							# Iterate through the Region's points array
							for pos in region.points:
								if pos.x >= 0 and pos.y >= 0 and pos.x < grid_width and pos.y < grid_height:
									img.set_pixel(int(pos.x), int(pos.y), base_river_color)
					else:
						_draw_simple_river_path(img, river, base_river_color)

	# *(Note: If you are still using the lake debug display from earlier, you can safely paste the DRAW LAKES block right here!)*

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

func _unhandled_input(event: InputEvent):
	# Check if the event is a mouse button click
	if event is InputEventMouseButton and event.pressed:
		# Check if it is the Right Mouse Button
		if event.button_index == MOUSE_BUTTON_RIGHT:
			
			# Get the mouse position relative to this node
			var local_mouse_pos = get_local_mouse_position()
			
			# Convert screen pixels to map grid coordinates
			var grid_x = int(local_mouse_pos.x / cell_size)
			var grid_y = int(local_mouse_pos.y / cell_size)
			var grid_pos = Vector2(grid_x, grid_y)
			
			# Ensure we clicked INSIDE the map boundaries
			if grid_x >= 0 and grid_x < grid_width and grid_y >= 0 and grid_y < grid_height:
				
				# Fetch elevation for extra debugging info
				var elevation = "N/A"
				if not terrain_data.is_empty() and terrain_data.has(grid_pos):
					elevation = str(snapped(terrain_data[grid_pos], 0.001))
				
				# Print to the Output console
				print("📍 Map Clicked - Grid Pos: ", grid_pos, " | Elevation: ", elevation)
				
# Retrieves the elevation data for a specific X, Y coordinate.
# Returns the elevation as a float, or -1.0 if the cell doesn't exist.
func get_elevation_at(map_data: Dictionary, x: int, y: int) -> float:
	var pos := Vector2(x, y)
	
	# Check if the coordinate actually exists in our generated map
	if map_data.has(pos):
		return map_data[pos]
	else:
		push_warning("Coordinate not found in map data: ", pos)
		return -1.0 # Return an impossible height to indicate an error
