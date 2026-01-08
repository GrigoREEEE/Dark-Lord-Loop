extends Node2D

@export var cell_size: int = 20
@export var grid_width : int
@export var grid_height : int

var grid : Dictionary[int, Array]
var height_data : Dictionary

var used_squares : Array[int] = []
var all_squares : Array[int] = []


func _ready():
	var ter_gen = MapGenerator_V3.new()
	grid = make_grid() # creates the world grid
	make_all_squares() # creates an array that contains all the avilable cells
	#grid_printer(grid)
	height_data = ter_gen.generate_heightmap(grid,grid_width,grid_height)
	print(height_data)
	display_map()
	
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

func display_map():
	queue_redraw()

func _draw():
	if height_data.is_empty():
		return

	for cell_id in height_data:
		# Calculate X and Y from the ID
		var x = cell_id % grid_width
		var y = cell_id / grid_width
		
		var height = height_data[cell_id]
		var color = get_height_color(height)
		
		# Draw the square
		var rect = Rect2(Vector2(x, y) * cell_size, Vector2(cell_size, cell_size))
		draw_rect(rect, color)

func get_height_color(height: float) -> Color:
	# Deep Ocean
	if height < -1.5: return Color.DARK_BLUE
	# Shallow Water
	elif height < 0: return Color.CORNFLOWER_BLUE
	# Lowland/Beach
	elif height < 0.5: return Color.SANDY_BROWN
	# Grassland
	elif height < 1.5: return Color.FOREST_GREEN
	# Hills
	elif height < 2.5: return Color.SADDLE_BROWN
	# High Mountains
	else: return Color.WHITE
