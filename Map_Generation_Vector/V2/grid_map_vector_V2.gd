extends Node2D

@export var hex_size: float = 12.0 # The radius from the center to a corner
var _hex_cache: Array[Dictionary] = [] # Stores { "points": PackedVector2Array, "color": Color }
var _multimesh: MultiMesh
var _mm_instance: MultiMeshInstance2D

func _setup_hex_multimesh():
	_mm_instance = MultiMeshInstance2D.new()
	add_child(_mm_instance)
	
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_colors = true
	
	# 1. Create a single hexagon mesh
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var verts = PackedVector2Array()
	var indices = PackedInt32Array()
	
	# Center point (Index 0)
	verts.append(Vector2.ZERO) 
	
	# The 6 corners (Indices 1 through 6)
	for i in range(6):
		var angle_rad = deg_to_rad(60 * i - 30)
		verts.append(Vector2(cos(angle_rad) * hex_size, sin(angle_rad) * hex_size))
		
	# Build 6 triangles connecting the center to the edges
	for i in range(6):
		indices.append(0)       # Center
		indices.append(i + 1)   # Current corner
		
		var next_corner = i + 2
		if next_corner > 6:
			next_corner = 1
		indices.append(next_corner) # Next corner
		
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var hex_mesh = ArrayMesh.new()
	hex_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# 2. Assign the mesh
	_multimesh.mesh = hex_mesh
	_mm_instance.multimesh = _multimesh

@export var river_mode_selector: OptionButton
@export var save_button: Button

var current_map_mode: MapDisplayMode = MapDisplayMode.TERRAIN
var world_data: World_Data
# River Display Mode
enum RiverDisplayMode {
	NORMAL,
	DEBUG_SEGMENTS,
	HIDDEN
}

enum MapDisplayMode {
	TERRAIN,
	WINTER_CLIMATE,
	SUMMER_CLIMATE,
	HEIGHT_MAP
}


var current_river_mode: RiverDisplayMode = RiverDisplayMode.NORMAL

# CONFIGURATION
#@export var noise_seed: int
#@export var reference_width = 400.0
#@export var cell_size: int = 1
#@export var grid_width: int = 400
#@export var grid_height: int = 600

# Water_Display
@export var water_level: float = 0.15 # Elevations below this are drawn as water

# --- Data Holders ---
var temperature_data: Dictionary = {} # Make sure to populate this using ClimateGenerator!
var river_data: Dictionary[Vector2, Region] = {}
var terrain_temperature_data: Dictionary[Vector2, float] = {}
var lake_data: Dictionary[Vector2, Region] = {}
var global_water_data: Dictionary[Vector2, Region] = {}
var _rivers: Array[River] = []


func _ready():
	#reference_width = 400
	var noise_seed = 1599947545 #randi() # 177024239 #randi() #58196215 #randi() #663202794#
	#print("Noise seed is: %s" % noise_seed)
	
	var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var _winding_noise: FastNoiseLite = FastNoiseLite.new()
	world_data = load("res://Map/World_Data.tres")
	world_data.res_scale = int(world_data.grid_width/world_data.reference_width)
	world_data.noise_seed = noise_seed
	#Profiler.start("total terrain generation")
	var climate_gen: Climate_Generator = Climate_Generator.new()
	var world_gen: Terrain_Generator = Terrain_Generator.new()
	var south_islands: South_Islands = South_Islands.new()
	var ice_wall: Ice_Wall = Ice_Wall.new()
	var ocean_id: Ocean_Identification = Ocean_Identification.new()
	var beach_id: Beach_Identification = Beach_Identification.new()
	var river_handler : River_Handler = River_Handler.new()
	
	var global_ocean: Water_Pool = Water_Pool.new()
	global_ocean.type = "Ocean"
	world_data.ocean = global_ocean
	Profiler.start("Terrain Generation")
	world_gen.generate_height_map(world_data)
	south_islands.apply_southern_islands(world_data)
	ice_wall.apply_ice_wall(world_data)
	Profiler.end("total terrain generation")
	world_data.map_data["terrain"]= world_data.map_data["terrain"]
	Profiler.end("Terrain Generation")
	Profiler.start("Beach and Mask Generation")
	# Check where the ocean abd the beach are
	ocean_id.ocean_vs_land(world_data)
	beach_id.generate_beach_mask(world_data)
	Profiler.end("Beach and Mask Generation")

	
	var main_river : River = river_handler.setup_river("main", world_data, {})
	_rivers.append(main_river)
	#var minor_rivers : Array[River] = river_handler.handle_rivers(world_data, grid_width, grid_height, map_data, global_ocean, mask_data, noise_seed, res_scale)
	#_rivers.append_array(minor_rivers)
	#mask_data["river"] = river_handler.create_full_river_mask(map_data["river"], grid_width, grid_height)
	#Profiler.start("Temperature Generation")
	##temperature_data = climate_gen.generate_temperatures(map_data["terrain"], mask_data)
	##map_data["temperature"] = temperature_data
	#Profiler.end("Temperature Generation")

	_setup_hex_multimesh()
	update_map_visuals()

# Cache the texture so we don't regenerate it every frame
var _map_texture: ImageTexture

func update_map_visuals():
	if world_data.map_data["terrain"].is_empty():
		return
		
	var valid_tiles = world_data.map_data["terrain"].keys()
	_multimesh.instance_count = valid_tiles.size()
	
	var hex_width = sqrt(3.0) * hex_size
	var hex_height = 2.0 * hex_size
	var vertical_spacing = hex_height * 0.75
	
	# --- 1. PRE-CALCULATE RIVER COLORS ---
	var river_colors: Dictionary = {}
	
	if not _rivers.is_empty() and current_river_mode != RiverDisplayMode.HIDDEN:
		var base_river_color: Color = Color("2d5e87")
		
		for river in _rivers:
			match current_river_mode:
				RiverDisplayMode.DEBUG_SEGMENTS:
					if not river.segments.is_empty():
						for i in range(river.segments.size()):
							var hue: float = float(i % 8) / 8.0
							var draw_color: Color = Color.from_hsv(hue, 0.8, 1.0)
							for pos in river.segments[i].points:
								river_colors[pos] = draw_color
					else:
						for pos in river.river_path:
							river_colors[pos] = Color.RED

				RiverDisplayMode.NORMAL:
					if not river.segments.is_empty():
						for region in river.segments:
							for pos in region.points:
								river_colors[pos] = base_river_color
					else:
						for pos in river.river_path:
							river_colors[pos] = base_river_color

	# --- 2. POPULATE THE MULTIMESH ---
	var instance_index = 0
	
	for pos in valid_tiles:
		if pos.x < 0 or pos.y < 0 or pos.x >= world_data.grid_width or pos.y >= world_data.grid_height:
			continue
			
		var elevation = world_data.map_data["terrain"][pos]
		var is_ocean = world_data.mask_data["ocean"].get(pos, false)
		var color: Color
		
		# Determine base terrain color
		if current_map_mode == MapDisplayMode.TERRAIN:
			var is_real_beach = world_data.mask_data["beach"].get(pos, false) or world_data.mask_data["delta"].get(pos, false)
			color = _get_layered_color(elevation, is_ocean, is_real_beach)
		elif current_map_mode == MapDisplayMode.HEIGHT_MAP:
			color = _get_height_color(elevation)
		else:
			var is_winter = (current_map_mode == MapDisplayMode.WINTER_CLIMATE)
			color = _get_climate_color(pos, is_winter)
			
		# OVERRIDE WITH RIVER COLOR IF APPLICABLE
		if river_colors.has(pos):
			color = river_colors[pos]
			
		# Hexagon Positioning
		var center_x = pos.x * hex_width
		var center_y = pos.y * vertical_spacing
		
		if int(pos.y) % 2 == 1:
			center_x += (hex_width / 2.0)
			
		var t = Transform2D()
		t = t.translated(Vector2(center_x, center_y))
		
		_multimesh.set_instance_transform_2d(instance_index, t)
		_multimesh.set_instance_color(instance_index, color)
		
		instance_index += 1

# Helper to generate the 6 corners of a pointy-topped hex
func _get_hex_points(center: Vector2, size: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in range(6):
		# 60 degrees per corner, starting at -30 degrees for pointy-top
		var angle_rad = deg_to_rad(60 * i - 30)
		points.append(center + Vector2(cos(angle_rad) * size, sin(angle_rad) * size))
	return points


#func update_map_visuals():
	## 1. Create a blank image buffer
	#var img = Image.create(world_data.grid_width, world_data.grid_height, false, Image.FORMAT_RGBA8)
	#
	## --- 1. SET TERRAIN / CLIMATE / HEIGHT PIXELS ---
	#if not world_data.map_data["terrain"].is_empty() and not world_data.mask_data["ocean"].is_empty():
		#for pos in world_data.map_data["terrain"]:
			#if pos.x < 0 or pos.y < 0 or pos.x >= world_data.grid_width or pos.y >= world_data.grid_height:
				#continue
			#
			#var elevation = world_data.map_data["terrain"][pos]
			#var is_ocean = world_data.mask_data["ocean"].get(pos, false)
			#
			#var color: Color
			#
			#if current_map_mode == MapDisplayMode.TERRAIN:
				#var is_real_beach = world_data.mask_data["beach"].get(pos, false) or world_data.mask_data["delta"].get(pos, false)
				#color = _get_layered_color(elevation, is_ocean, is_real_beach)
			#elif current_map_mode == MapDisplayMode.HEIGHT_MAP:
				#color = _get_height_color(elevation)
			#else:
				#var is_winter = (current_map_mode == MapDisplayMode.WINTER_CLIMATE)
				#color = _get_climate_color(pos, is_winter)
				#
			#img.set_pixel(int(pos.x), int(pos.y), color)
#
	## --- 2. SET RIVER PIXELS ---
	#if not _rivers.is_empty() and current_river_mode != RiverDisplayMode.HIDDEN:
		#
		#var base_river_color: Color = Color("2d5e87")
		#
		#for river in _rivers:
			#match current_river_mode:
				#
				#RiverDisplayMode.DEBUG_SEGMENTS:
					#if not river.segments.is_empty():
						#for i in range(river.segments.size()):
							#var region: Region = river.segments[i] # Unpack as Region
							## Rainbow logic for segments
							#var hue: float = float(i % 8) / 8.0
							#var draw_color: Color = Color.from_hsv(hue, 0.8, 1.0)
							#
							## Iterate through the Region's points array
							#for pos in region.points:
								#if pos.x >= 0 and pos.y >= 0 and pos.x < world_data.grid_width and pos.y < world_data.grid_height:
									#img.set_pixel(int(pos.x), int(pos.y), draw_color)
					#else:
						#_draw_simple_river_path(img, river, Color.RED)
#
				#RiverDisplayMode.NORMAL:
					#if not river.segments.is_empty():
						#for region: Region in river.segments: # Type hint as Region
							## Iterate through the Region's points array
							#for pos in region.points:
								#if pos.x >= 0 and pos.y >= 0 and pos.x < world_data.grid_width and pos.y < world_data.grid_height:
									#img.set_pixel(int(pos.x), int(pos.y), base_river_color)
					#else:
						#_draw_simple_river_path(img, river, base_river_color)
#
	## 4. Create or Update the GPU Texture
	#if _map_texture:
		#_map_texture.update(img)
	#else:
		#_map_texture = ImageTexture.create_from_image(img)
	#
	## 5. Tell Godot to repaint
	#queue_redraw()
	#
func _get_height_color(e: float) -> Color:
	# Convert elevation from range [-1.0, 1.0] to a normalized [0.0, 1.0] weight
	var w = clamp(inverse_lerp(-1.0, 1.0, e), 0.0, 1.0)
	
	# Using a Red -> Yellow -> Green gradient makes it much easier to read
	# than a direct Red -> Green blend (which turns muddy brown in the middle)
	if w < 0.5:
		# Bottom half: Red blending into Yellow
		var local_w = w * 2.0
		return Color.RED.lerp(Color.YELLOW, local_w)
	else:
		# Top half: Yellow blending into Green
		var local_w = (w - 0.5) * 2.0
		return Color.YELLOW.lerp(Color.GREEN, local_w)
#
## --- Helper to avoid code duplication ---
#func _draw_simple_river_path(img: Image, river, color: Color):
	#for pos in river.river_path:
		#if pos.x >= 0 and pos.y >= 0 and pos.x < world_data.grid_width and pos.y < world_data.grid_height:
			#img.set_pixel(int(pos.x), int(pos.y), color)
#
#func _draw():
	#if _map_texture:
		#draw_texture_rect(_map_texture, Rect2(0, 0, world_data.grid_width * world_data.cell_size, world_data.grid_height * world_data.cell_size), false)

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
			var grid_x = int(local_mouse_pos.x / world_data.cell_size)
			var grid_y = int(local_mouse_pos.y / world_data.cell_size)
			var grid_pos = Vector2(grid_x, grid_y)
			
			# Ensure we clicked INSIDE the map boundaries
			if grid_x >= 0 and grid_x < world_data.grid_width and grid_y >= 0 and grid_y < world_data.grid_height:
				
				# Fetch elevation for extra debugging info
				var elevation = "N/A"
				if not world_data.map_data["terrain"].is_empty() and world_data.map_data["terrain"].has(grid_pos):
					elevation = str(snapped(world_data.map_data["terrain"][grid_pos], 0.0001))
				
				# Print to the Output console
				print("📍 Map Clicked - Grid Pos: ", grid_pos, " | Elevation: ", elevation)
				
# Retrieves the elevation data for a specific X, Y coordinate.
# Returns the elevation as a float, or -1.0 if the cell doesn't exist.
func get_elevation_at(map_data, x: int, y: int) -> float:
	var pos := Vector2(x, y)
	
	# Check if the coordinate actually exists in our generated map
	if map_data.has(pos):
		return map_data[pos]
	else:
		push_warning("Coordinate not found in map data: ", pos)
		return -1.0 # Return an impossible height to indicate an error

# Helper function to map a temperature (Celsius) to a color heatmap
func _get_climate_color(pos: Vector2, is_winter: bool) -> Color:
	if not temperature_data.has(pos):
		return Color.BLACK
		
	var temps: Vector2 = temperature_data[pos]
	var t: float = temps.x if is_winter else temps.y
	
	# Temperature Color Ramp
	if t < -15.0:
		return Color("2c2c54") # Deep freezing purple
	elif t < 0.0:
		var w = inverse_lerp(-15.0, 0.0, t)
		return Color("4a69bd").lerp(Color("74b9ff"), w) # Dark blue to light blue
	elif t < 15.0:
		var w = inverse_lerp(0.0, 15.0, t)
		return Color("74b9ff").lerp(Color("55efc4"), w) # Light blue to mint green
	elif t < 25.0:
		var w = inverse_lerp(15.0, 25.0, t)
		return Color("55efc4").lerp(Color("fdcb6e"), w) # Mint green to warm yellow
	elif t < 35.0:
		var w = inverse_lerp(25.0, 35.0, t)
		return Color("fdcb6e").lerp(Color("d63031"), w) # Warm yellow to hot red
	else:
		return Color("b71540") # Extreme heat dark red
