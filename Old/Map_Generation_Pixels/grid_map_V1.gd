extends Node2D

@export var width : int
@export var height : int

var grid : Dictionary[int, Array]
var height_map : Dictionary

var used_squares : Array[int] = []
var all_squares : Array[int] = []

func _ready():
	grid = make_grid() # creates the world grid
	make_all_squares() # creates an array that contains all the avilable cells
	grid_printer(grid)
	#height_map = Height_Map.generate_elevation(grid)
	#print(height_map)
	var oc = generate_oceans(grid)
	grid_printer(oc)
	display_map(grid, oc)

func make_all_squares() -> void:
	var total : int = width * height
	for i in total:
		all_squares.append(i)

func grid_printer(g) -> void:
	var keys : Array = g.keys()
	for i in keys:
		print(str(i) + ": " + str(g[i]))
		
func make_grid() -> Dictionary[int, Array]:
	var square_id : int = 0
	var row : Array
	for i in (height):
		row = []
		for j in (width):
			row.append(square_id)
			square_id += 1
		grid[i] = row
	return grid

func generate_oceans(grid: Dictionary, ocean_percentage: float = 0.65, num_seeds: int = 5) -> Dictionary:
	var result = {}
	var height = grid.size()
	var width = grid[0].size() if height > 0 else 0
	
	# Initialize all tiles as land
	for y in range(height):
		for x in range(width):
			var tile_id = grid[y][x]
			result[tile_id] = "l"
	
	# Calculate target number of ocean tiles
	var total_tiles = height * width
	var target_ocean_tiles = int(total_tiles * ocean_percentage)
	var ocean_tiles_created = 0
	
	# Helper function to get neighbors
	var get_neighbors = func(y: int, x: int) -> Array:
		var neighbors = []
		var directions = [
			Vector2i(0, -1),  # up
			Vector2i(0, 1),   # down
			Vector2i(-1, 0),  # left
			Vector2i(1, 0)    # right
		]
		
		for dir in directions:
			var ny = y + dir.y
			var nx = x + dir.x
			# Check bounds
			if ny >= 0 and ny < height and nx >= 0 and nx < width:
				neighbors.append(Vector2i(nx, ny))
		
		return neighbors
	
	# Start random walks from multiple seed points
	var walkers = []
	for i in range(num_seeds):
		var start_y = randi() % height
		var start_x = randi() % width
		walkers.append(Vector2i(start_x, start_y))
		
		# Mark seed as ocean
		var tile_id = grid[start_y][start_x]
		if result[tile_id] == "l":
			result[tile_id] = "w"
			ocean_tiles_created += 1
	
	# Perform random walks until we reach target ocean percentage
	while ocean_tiles_created < target_ocean_tiles:
		# If we run out of walkers, spawn new ones
		if walkers.size() == 0:
			# Find an existing ocean tile to spawn from
			var ocean_tiles = []
			for y in range(height):
				for x in range(width):
					var tile_id = grid[y][x]
					if result[tile_id] == "w":
						ocean_tiles.append(Vector2i(x, y))
			
			if ocean_tiles.size() > 0:
				# Spawn multiple new walkers from random ocean tiles
				for i in range(min(5, ocean_tiles.size())):
					var spawn_pos = ocean_tiles[randi() % ocean_tiles.size()]
					walkers.append(spawn_pos)
			else:
				# Emergency: spawn a completely new seed
				walkers.append(Vector2i(randi() % width, randi() % height))
		
		var new_walkers = []
		
		for walker in walkers:
			# Get valid neighbors
			var neighbors = get_neighbors.call(walker.y, walker.x)
			
			if neighbors.size() == 0:
				continue
			
			# Move to a random neighbor
			var next_pos = neighbors[randi() % neighbors.size()]
			var tile_id = grid[next_pos.y][next_pos.x]
			
			# Convert to ocean if not already
			if result[tile_id] == "l":
				result[tile_id] = "w"
				ocean_tiles_created += 1
				
				# Check if we've reached target
				if ocean_tiles_created >= target_ocean_tiles:
					return result
			
			# Walker continues with high probability
			if randf() < 0.95:  # 95% chance to continue
				new_walkers.append(next_pos)
			
			# Chance to spawn a new walker (creates branches)
			if randf() < 0.08:  # 8% chance to branch
				new_walkers.append(next_pos)
		
		walkers = new_walkers
	
	return result
	
func display_map(grid: Dictionary, ocean_map: Dictionary, cell_size: int = 20):
	# Clear any existing display
	for child in get_children():
		child.queue_free()
	
	var height = grid.size()
	var width = grid[0].size() if height > 0 else 0
	
	# Define colors
	var ocean_color = Color(0.2, 0.4, 0.8)  # Blue
	var land_color = Color(0.3, 0.7, 0.3)   # Green
	
	# Create a ColorRect for each tile
	for y in range(height):
		for x in range(width):
			var tile_id = grid[y][x]
			var tile_type = ocean_map[tile_id]
			
			var rect = ColorRect.new()
			rect.size = Vector2(cell_size, cell_size)
			rect.position = Vector2(x * cell_size, y * cell_size)
			
			if tile_type == "w":
				rect.color = ocean_color
			else:
				rect.color = land_color
			
			add_child(rect)
