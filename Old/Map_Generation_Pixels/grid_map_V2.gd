extends Node2D

@export var cell_size: int = 20
@export var width : int
@export var height : int

var grid : Dictionary[int, Array]
var height_map : Dictionary

var used_squares : Array[int] = []
var all_squares : Array[int] = []

## Color palette for elevation levels
var elevation_colors: Dictionary = {
	-3: Color(0.0, 0.1, 0.4),   # Deep ocean - dark blue
	-2: Color(0.0, 0.2, 0.6),   # Ocean - medium blue
	-1: Color(0.2, 0.4, 0.8),   # Shallow water - light blue
	0: Color(0.9, 0.85, 0.6),   # Beach/coast - sandy
	1: Color(0.3, 0.6, 0.3),    # Plains - green
	2: Color(0.5, 0.5, 0.4),    # Hills - gray-green
	3: Color(0.9, 0.9, 0.9)     # Mountains - white
}

func _ready():
	var ter_gen = MapGenerator.new()
	grid = make_grid() # creates the world grid
	make_all_squares() # creates an array that contains all the avilable cells
	#grid_printer(grid)
	var terr = ter_gen.generate_height_map(grid,width,height)
	display_height_map(terr)
	
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
	
# Display the height map by drawing colored rectangles
func display_height_map(height_map: Dictionary) -> void:
	# Clear any previous drawings
	queue_redraw()
	
	# Store height map for _draw callback
	_current_height_map = height_map

var _current_height_map: Dictionary = {}

func _draw() -> void:
	if _current_height_map.is_empty():
		return
	
	var map_height: int = _current_height_map.size()
	
	for y in range(map_height):
		var row: Array = _current_height_map[y]
		
		for x in range(row.size()):
			var elevation: int = row[x]
			
			# Get color for this elevation
			var color: Color = elevation_colors.get(elevation, Color.MAGENTA)
			
			# Calculate position
			var pos: Vector2 = Vector2(x * cell_size, y * cell_size)
			
			# Draw filled rectangle for this cell
			draw_rect(Rect2(pos, Vector2(cell_size, cell_size)), color)
			
			# Optional: Draw grid lines for clarity
			draw_rect(Rect2(pos, Vector2(cell_size, cell_size)), Color(0, 0, 0, 0.2), false, 1.0)
