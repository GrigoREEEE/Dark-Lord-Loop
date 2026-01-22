extends Node2D

# CONFIGURATION
@export var noise_seed : int
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
	var res_scale = int(grid_width/REFERENCE_WIDTH)
	
	var river_gen : River_Generator = River_Generator.new()
	var world_gen : Terrain_Generator = Terrain_Generator.new()
	var south_islands : South_Islands = South_Islands.new()
	var ice_wall : Ice_Wall = Ice_Wall.new()
	var erosion : River_Erosion = River_Erosion.new()
	var ocean_id : Ocean_Identification = Ocean_Identification.new()
	var beach_id : Beach_Identification = Beach_Identification.new()
	var river_expander : River_Widener = River_Widener.new()
	var my_river : River
	
	terrain_data = world_gen.generate_height_map(grid_width, grid_height, noise_seed, res_scale)
	terrain_data = south_islands.apply_southern_islands(terrain_data, grid_width, grid_height, 150, 15, 60, noise_seed, res_scale)
	terrain_data = ice_wall.apply_ice_wall(terrain_data, grid_width, noise_seed, res_scale)
	
	_ocean_mask = ocean_id.ocean_vs_land(terrain_data, grid_width, grid_height)
	_beach_mask = beach_id.generate_beach_mask(_ocean_mask, 8, res_scale)

		
	## Generate the River
	my_river = river_gen.generate_central_river(grid_width, grid_height, _ocean_mask, res_scale)
	_rivers.append(my_river)
	
	
	erosion.apply_river_erosion(terrain_data, my_river, 29.0, 30.0, 0.85, 0.2, res_scale) #5, 30, 0.9, 0.1)
	
	_ocean_mask = ocean_id.ocean_vs_land(terrain_data, grid_width, grid_height)
	
	river_gen.clean_river_path(my_river, _ocean_mask)
	my_river.create_segments(300)
	river_expander.widen_river_natural(terrain_data, my_river, _ocean_mask, 30.0, 1000.0)

	_rivers = []
	_rivers.append(my_river)
	#_ocean_mask = ocean_id.ocean_vs_land(terrain_data, grid_width, grid_height)
	#_beach_mask = beach_id.generate_beach_mask(_ocean_mask, 8, res_scale)
	queue_redraw()
	#save_map_to_png("res://image.png")
	
# Configurable settings for visualization
@export var water_level: float = 0.15 # Elevations below this are drawn as water

func save_map_to_png(file_path: String):
	if terrain_data.is_empty():
		push_error("Map data is empty. Generate and display the map first.")
		return

	# 1. Determine Map Size automatically
	# We scan the dictionary to find the maximum X and Y coordinates.
	# This ensures we capture the full map, including the extra Ice Wall height.
	var max_x = 0
	var max_y = 0
	
	for pos in terrain_data:
		if pos.x > max_x: max_x = int(pos.x)
		if pos.y > max_y: max_y = int(pos.y)
	
	var width = max_x + 1
	var height = max_y + 1
	
	# 2. Create a new Image
	var image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	
	# 3. Fill the Image pixel by pixel
	# We use the exact same logic as _draw() to ensure the PNG looks identical.
	for x in range(width):
		for y in range(height):
			var pos = Vector2(x, y)
			
			if terrain_data.has(pos):
				var elevation = terrain_data[pos]
				
				# Retrieve the pre-calculated masks
				var is_ocean = _ocean_mask.get(pos, false)
				var is_real_beach = _beach_mask.get(pos, false)
				
				# Get the color using your existing styling function
				var color = _get_layered_color(elevation, is_ocean, is_real_beach)
				
				image.set_pixel(x, y, color)
			else:
				# Fill empty spots (if any) with transparent or black
				image.set_pixel(x, y, Color.TRANSPARENT)
	
	# 4. Save to Disk
	var error = image.save_png(file_path)
	
	if error != OK:
		push_error("Failed to save image. Error code: " + str(error))
	else:
		print("Map successfully saved to: " + file_path)

func _draw():
	if terrain_data.is_empty() or _ocean_mask.is_empty():
		return
		
	# --- 1. DRAW TERRAIN ---
	for pos in terrain_data:
		var elevation = terrain_data[pos]
		
		var is_ocean = _ocean_mask.get(pos, false)
		var is_real_beach = _beach_mask.get(pos, false) 
		
		var color = _get_layered_color(elevation, is_ocean, is_real_beach)
		
		draw_rect(Rect2(pos * cell_size, Vector2(cell_size, cell_size)), color)

	# --- 2. DRAW RIVERS (Updated) ---
	# We draw these AFTER terrain so they layer on top.
	if not _rivers.is_empty():
		var river_color = Color("2d5e87") #Color("4287f5") # Distinct Bright Blue
		
		for river in _rivers:
			# Check if segments exist (fallback to path if segments were never generated)
			if not river.segments.is_empty():
				# Iterate through every segment (Chunk of the river)
				for segment in river.segments:
					# Iterate through every cell in that segment (Path + Widened Banks)
					for pos in segment:
						draw_rect(Rect2(pos * cell_size, Vector2(cell_size, cell_size)), river_color)
			else:
				# Fallback: If create_segments() wasn't called, draw the simple path
				for pos in river.river_path:
					draw_rect(Rect2(pos * cell_size, Vector2(cell_size, cell_size)), river_color)


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
		
