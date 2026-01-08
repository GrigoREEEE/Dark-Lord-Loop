extends Node2D

@export var cell_size: int = 1
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
var rivers : Array = []



func _ready():
	var world_gen : WorldGeneratorVector = WorldGeneratorVector.new()
	var river_gen : WaterWorksVector = WaterWorksVector.new()
	current_height_map = world_gen.generate_height_map(grid_width, grid_height)
	get_land_type_map(current_height_map)
	river_gen.identify_lakes(self, grid_width, grid_height)
	#current_height_map = world_gen.apply_terrain_elevation(current_land_map, current_height_map)
	
	#rivers = river_gen.generate_rivers(current_land_map, inverse_land_map, 5)
	#print(rivers)



func get_land_type_map(height_data: Dictionary) -> void:
	
	for pos in height_data:
		var inverse_land_map_keys = inverse_land_map.keys()
		var height = height_data[pos]
		var type_id: int
		
		# Map height (-3 to 3) to Land Type IDs
		if height < -1.5:
			type_id = LandType.DEEP_WATER
		elif height < 0.0:
			type_id = LandType.SHALLOW_WATER
		elif height < 0.2:
			type_id = LandType.LOWS
		elif height < 1.2:
			type_id = LandType.PLAINS
		elif height < 2.2:
			type_id = LandType.HILLS
		else:
			type_id = LandType.MOUNTAINS
			
		current_land_map[pos] = type_id
		if type_id in inverse_land_map_keys:
			inverse_land_map[type_id].append(pos)
		else:
			inverse_land_map[type_id] = [pos]

enum LandType {
	DEEP_WATER = 1,
	SHALLOW_WATER = 2,
	LOWS = 3,
	PLAINS = 4,
	HILLS = 5,
	MOUNTAINS = 6,
	LAKE = 7,
	RIVER = 8,
}

func draw_land_type_map(land_type_map: Dictionary, rivers_array: Array = []):
	# 1. Draw the Base Terrain
	for pos in land_type_map:
		var type_id = land_type_map[pos]
		var color = Color.MAGENTA # Fallback
		
		match type_id:
			LandType.DEEP_WATER:    color = Color(0.05, 0.15, 0.4)
			LandType.SHALLOW_WATER: color = Color(0.2, 0.45, 0.8)
			LandType.LOWS:          color = Color(0.43, 0.69, 0.22)
			LandType.PLAINS:        color = Color(0.3, 0.65, 0.25)
			LandType.HILLS:         color = Color(0.45, 0.4, 0.25)
			LandType.MOUNTAINS:     color = Color(0.6, 0.6, 0.65)
			LandType.LAKE:          color = Color(0.2, 0.45, 0.8) #Color(0.417, 0.636, 0.945, 1.0)

		var rect = Rect2(pos * cell_size, Vector2.ONE * cell_size)
		draw_rect(rect, color)

	# 2. Draw the Rivers on top
	# We use a distinct color (e.g., slightly brighter than Shallow Water)
	var river_color = Color(0.2, 0.45, 0.8)

	for river_path in rivers_array:
		for pos in river_path:
			# Optional: Skip the error flag if it slipped into the array
			if pos == Vector2.ZERO and river_path.size() > 1: 
				continue 

			var rect = Rect2(pos * cell_size, Vector2.ONE * cell_size)
			draw_rect(rect, river_color)

#func draw_land_type_map(land_type_map: Dictionary):
	## Loop directly through the Vector2 keys
	#for pos in land_type_map:
		#var type_id = land_type_map[pos]
		#var color = Color.MAGENTA # Fallback
		#
		#match type_id:
			#LandType.DEEP_WATER:    color = Color(0.05, 0.15, 0.4)
			#LandType.SHALLOW_WATER: color = Color(0.2, 0.45, 0.8)
			#LandType.COAST:         color = Color(0.43, 0.69, 0.22)
			#LandType.PLAINS:        color = Color(0.3, 0.65, 0.25)
			#LandType.HILLS:         color = Color(0.45, 0.4, 0.25)
			#LandType.MOUNTAINS:     color = Color(0.6, 0.6, 0.65)
			#LandType.LAKE:          color = Color(0.417, 0.636, 0.945, 1.0)
#
		## Vector2 * float returns a new Vector2 scaled by that amount
		## We use Vector2.ONE * cell_size to create the square dimensions
		#var rect = Rect2(pos * cell_size, Vector2.ONE * cell_size)
		#
		#draw_rect(rect, color)

func draw_height_map_gradient(height_map: Dictionary):
	# Define your gradient colors
	var color_deep_blue = Color(0.0, 0.1, 0.4) # Deep Ocean
	var color_dark_brown = Color(0.4, 0.2, 0.1) # Mountain Peaks
	
	for pos in height_map:
		var height_val = height_map[pos]
		
		# Normalize the height to a 0.0 - 1.0 range
		# -3.0 becomes 0.0, 3.0 becomes 1.0
		var t = inverse_lerp(-3.0, 3.0, height_val)
		
		# Interpolate between the two colors based on 't'
		var color = color_deep_blue.lerp(color_dark_brown, t)
		
		var rect = Rect2(pos * cell_size, Vector2.ONE * cell_size)
		draw_rect(rect, color)

func _draw():
	match display_type:
		DisplayType.LAND_TYPES:
			if not current_land_map.is_empty():
				draw_land_type_map(current_land_map, rivers)
				
		DisplayType.HEIGHT_MAP:
			if not current_height_map.is_empty():
				draw_height_map_gradient(current_height_map)
		
# Call this whenever you generate a new map to refresh the visual
func update_visuals():
	queue_redraw()
