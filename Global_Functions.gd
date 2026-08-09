extends Node

# Helper function to find the 6 true touching neighbors in an offset hex grid
func _get_hex_neighbors(grid_pos: Vector2) -> Array[Vector2]:
	var neighbors: Array[Vector2] = []
	var is_odd_row: bool = int(grid_pos.y) % 2 != 0
	
	# East and West are always the same on both rows
	neighbors.append(grid_pos + Vector2(1, 0))  # Right
	neighbors.append(grid_pos + Vector2(-1, 0)) # Left
	
	if is_odd_row:
		# Odd rows are shifted Right (+0.5 X)
		neighbors.append(grid_pos + Vector2(0, -1))  # Top Left
		neighbors.append(grid_pos + Vector2(1, -1))  # Top Right
		neighbors.append(grid_pos + Vector2(0, 1))   # Bottom Left
		neighbors.append(grid_pos + Vector2(1, 1))   # Bottom Right
	else:
		# Even rows are normal
		neighbors.append(grid_pos + Vector2(-1, -1)) # Top Left
		neighbors.append(grid_pos + Vector2(0, -1))  # Top Right
		neighbors.append(grid_pos + Vector2(-1, 1))  # Bottom Left
		neighbors.append(grid_pos + Vector2(0, 1))   # Bottom Right
		
	return neighbors
	

# Converts a hex grid coordinate into physical 2D space for accurate angle math
func _get_hex_physical_pos(grid_pos: Vector2) -> Vector2:
	var hex_width = sqrt(3.0)
	var hex_height = 2.0
	
	var center_x = grid_pos.x * hex_width
	var center_y = grid_pos.y * (hex_height * 0.75)
	
	# Apply the staggered offset for odd rows
	if int(grid_pos.y) % 2 == 1:
		center_x += (hex_width / 2.0)
		
	return Vector2(center_x, center_y)
