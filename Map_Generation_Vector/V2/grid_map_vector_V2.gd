extends Node2D

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
var current_height_map: Dictionary = {} # Dictionary[Vector2, float]
var _ocean_mask: Dictionary = {} # Dictionary[Vector2, bool]
var _beach_mask: Dictionary = {} # Dictionary[Vector2, bool]


func _ready():
	var world_gen : WorldGeneratorVector_V2 = WorldGeneratorVector_V2.new()
	#var river_gen : WaterWorksVector = WaterWorksVector.new()
	current_height_map = world_gen.generate_height_map(grid_width, grid_height)
	_ocean_mask = world_gen.ocean_vs_land(current_height_map, grid_width, grid_height)
	_beach_mask = world_gen.get_beach_mask(_ocean_mask, grid_width, grid_height)
	display_map(current_height_map)
	save_map_to_png("res://image.png")
	
# Configurable settings for visualization
@export var water_level: float = 0.15 # Elevations below this are drawn as water

func save_map_to_png(file_path: String):
	if _world_data.is_empty():
		push_error("Map data is empty. Generate and display the map first.")
		return

	# 1. Determine Map Size automatically
	# We scan the dictionary to find the maximum X and Y coordinates.
	# This ensures we capture the full map, including the extra Ice Wall height.
	var max_x = 0
	var max_y = 0
	
	for pos in _world_data:
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
			
			if _world_data.has(pos):
				var elevation = _world_data[pos]
				
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

var _world_data: Dictionary = {}

func display_map(generated_data: Dictionary):
	_world_data = generated_data
	queue_redraw()

func _draw():
	if _world_data.is_empty() or _ocean_mask.is_empty():
		return
		
	for pos in _world_data:
		var elevation = _world_data[pos]
		
		var is_ocean = _ocean_mask.get(pos, false)
		var is_real_beach = _beach_mask.get(pos, false) # Get distance boolean
		
		var color = _get_layered_color(elevation, is_ocean, is_real_beach)
		
		draw_rect(Rect2(pos * cell_size, Vector2(cell_size, cell_size)), color)

func _get_layered_color(e: float, is_ocean: bool, is_real_beach: bool) -> Color:
	# --- SPECIAL HIGH PEAK LAYER (> 0.98) ---
	if e > 0.98: return Color(1.0, 1.0, 1.0, 1.0)
	
	# --- BANDED TERRAIN LAYERS ---
	
	if e < 0.15:
		# --- WATER LEVEL LOGIC ---
		if is_ocean:
			# Salt Water
			if e < -0.5: return Color("1e3852") # Deep Ocean
			return Color("2d5e87")             # Shallow Water
		else:
			if e < 0.07:
				# --- INLAND LAKE / SWAMP LOGIC ---
				# Previously "Lakes". Now we color them as deep swamps.
				# Only areas strictly below water level become swamp.
				return Color("4b5e32") # Olive Drab / Swamp Green
			elif e < 0.12:
				return Color("7a8a4b")
			else:
				return Color("5d9e44")
				 
	elif e < 0.18:
		# --- BEACH / BASIN LOGIC ---
		if is_real_beach:
			return Color("d6c38e") # Real Sand (Near Ocean)
		else:
			# --- INLAND BASIN -> GRASSLAND ---
			# Previously "Muddy Grass". 
			# Now we treat this as just standard low-elevation grassy terrain.
			# We return the same color as the "Low Grass" layer below.
			return Color("5d9e44") # Low Grass (Light Green)

	# --- REST OF THE MAP ---
	elif e < 0.40:
		# Lowlands
		if e < 0.28: return Color("5d9e44") 
		return Color("3e7a2b")             
		
	elif e < 0.70:
		# Highlands / Hills
		if e < 0.55: return Color("5c5847") 
		return Color("4d453b")             
		
	else:
		# Mountain / Snow
		if e < 0.82: return Color("8a9da1") 
		return Color("cececeff")
