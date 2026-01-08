extends Node2D

@export var cell_size: int = 20
@export var grid_width : int
@export var grid_height : int

var grid : Dictionary[int, Array]
var height_data : Dictionary
var current_land_map 

var used_squares : Array[int] = []
var all_squares : Array[int] = []


func _ready():
	var ter_gen = WorldGenerator.new()
	var river_gen = WaterWorks.new()
	grid = make_grid() # creates the world grid
	make_all_squares() # creates an array that contains all the avilable cells
	#grid_printer(grid)
	height_data = ter_gen.generate_height_map(grid,grid_width,grid_height)
	#print(height_data)
	current_land_map = get_land_type_map()
	current_land_map = river_gen.identify_lakes(current_land_map)
	#grid_printer(current_land_map)
	#current_land_map = river_gen.generate_rivers(current_land_map, grid, 10)
	#print(current_land_map)
	#print(current_land_map)
	#current_land_map = river_gen.generate_rivers(10, height_data, current_land_map, grid_width, grid_height)
	
func make_all_squares() -> void:
	var total : int = grid_width * grid_height
	for i in total:
		all_squares.append(i)

func grid_printer(g) -> void:
	var keys : Array = g.keys()
	for i in keys:
		print(str(i) + ": " + str(g[i]))
		
func make_grid() -> Dictionary[int, Array]:
	var square_id : int = 0
	var row : Array
	for i in (grid_height):
		row = []
		for j in (grid_width):
			row.append(square_id)
			square_id += 1
		grid[i] = row
	return grid

func get_land_type_map() -> Dictionary:
	var land_type_map = {}
	
	for y in height_data.keys():
		var height_row = height_data[y]
		var type_row = []
		
		for height in height_row:
			var type_id = 1 # Default to Deep Water
			
			# Map height (-3 to 3) to Land Type IDs
			if height < -1.5:
				type_id = 1 # Deep Water
			elif height < 0.0:
				type_id = 2 # Shallow Water
			elif height < 0.2:
				type_id = 3 # Coastlines
			elif height < 1.2:
				type_id = 4 # Grass/Forest/Plains
			elif height < 2.2:
				type_id = 5 # Hills
			else:
				type_id = 6 # Mountains
				
			type_row.append(type_id)
		
		land_type_map[y] = type_row
		
	return land_type_map

func draw_land_type_map(land_type_map: Dictionary):
	# Loop through each row (y)
	for y in land_type_map.keys():
		var row = land_type_map[y]
		
		# Loop through each cell in the row (x)
		for x in range(row.size()):
			#print("\n row is: " + str(row))
			var type_id = row[x]
			var color = Color.MAGENTA # Fallback color for debugging
			
			# Assign colors based on your specific IDs
			match type_id:
				1: color = Color(0.05, 0.15, 0.4)  # Deep Water
				2: color = Color(0.2, 0.45, 0.8)  # Shallow Water
				3: color = Color(0.431, 0.694, 0.219, 1.0) # Lowlands
				4: color = Color(0.3, 0.65, 0.25) # Grass/Forest/Plains
				5: color = Color(0.45, 0.4, 0.25) # Hills
				6: color = Color(0.6, 0.6, 0.65)  # Mountains
				7: color = Color(0.499, 0.687, 0.959, 1.0) # Lake (Calm Blue)
				8: color = Color(0.2, 0.45, 0.8) # River (Bright Cyan)

			# Calculate the rectangle position and size
			var rect = Rect2(Vector2(float(x), float(y)) * cell_size, Vector2(cell_size, cell_size))
			
			# Draw the square
			draw_rect(rect, color)

# Standard Godot _draw function
func _draw():
	# Assuming 'current_land_map' is stored after your generation finishes
	if not current_land_map.is_empty():
		draw_land_type_map(current_land_map)

#func draw_height_map():
	## Loop through each row in the dictionary
	#for y in height_data.keys():
		#var row = height_data[y]
		#
		## Loop through each column (index) in the array
		#for x in range(row.size()):
			#var height = row[x]
			#var color = Color.BLACK
			#
			## Assign colors based on the -3 to 3 scale
			#if height < -1.5:
				#color = Color(0.0, 0.1, 0.4) # Deep Ocean
			#elif height < 0:
				#color = Color(0.2, 0.4, 0.8) # Shallow Water
			#elif height < 0.2:
				#color = Color(0.9, 0.8, 0.6) # Sand/Beach
			#elif height < 1.2:
				#color = Color(0.2, 0.6, 0.1) # Grass/Forest
			#elif height < 2.2:
				#color = Color(0.4, 0.3, 0.2) # Dirt/Hills
			#else:
				#color = Color(0.9, 0.9, 1.0) # Snow/Mountain Peaks
			#
			## Draw a square for each cell
			#var rect = Rect2(Vector2(x, y) * cell_size, Vector2(cell_size, cell_size))
			#draw_rect(rect, color)
#
## To see the changes, you must call queue_redraw() when the height_map is ready
#func _draw():
	## Assuming 'current_height_map' is a variable stored in your script
	#if height_data:
		#draw_height_map()
