class_name Lake_Generator
extends RefCounted

const DIRECTIONS: Array[Vector2] = [
	Vector2(0, -1), # UP
	Vector2(0, 1),  # DOWN
	Vector2(-1, 0), # LEFT
	Vector2(1, 0)   # RIGHT
]

# Generates a lake starting from a local minimum.
# Returns the new lake (Water_Pool) and the position where a new river should start (or Vector2(-1,-1) if none).
func generate_lake(
	start_pos: Vector2, 
	incoming_river: River, 
	terrain_data: Dictionary, 
	mask_data: Dictionary,
	river_data: Dictionary # Mapping Vector2 -> Region
) -> Dictionary:
	
	var lake = Water_Pool.new()
	lake.id = "LK" + str(randi() % 9999).pad_zeros(4)
	lake.type = "Lake"
	lake.water_type = "Lake"
	
	if incoming_river:
		lake.rivers_in.append(incoming_river)
		
	var ocean_mask: Dictionary = mask_data.get("ocean", {})
	var lake_mask: Dictionary = mask_data.get("lake", {})
	var delta_mask: Dictionary = mask_data.get("delta", {})
	var river_mask: Dictionary = mask_data.get("river", {})
	
	var current_lake_height: float = terrain_data.get(start_pos, 0.0)
	var wall_cells: Array[Vector2] = []
	var visited: Dictionary = {}
	var perimeter: Dictionary = {} # Vector2 -> height
	
	# Initialize
	_add_to_lake(start_pos, lake, mask_data, incoming_river)
	visited[start_pos] = true
	_add_neighbors_to_perimeter(start_pos, perimeter, visited, terrain_data)

	var overflow_point: Vector2 = Vector2(-1, -1)
	
	# Flood fill loop
	while not perimeter.is_empty():
		# 1. Find the lowest cell in the perimeter
		var lowest_cell: Vector2 = perimeter.keys()[0]
		var lowest_height: float = perimeter[lowest_cell]
		
		for cell in perimeter.keys():
			if perimeter[cell] < lowest_height:
				lowest_height = perimeter[cell]
				lowest_cell = cell
				
		perimeter.erase(lowest_cell)
		
		# 2. Check Constraint 3: Is it a wall? (Adjacent to or IS another water body)
		if _is_wall_cell(lowest_cell, incoming_river, ocean_mask, lake_mask, delta_mask, river_mask, river_data):
			if not wall_cells.has(lowest_cell):
				wall_cells.append(lowest_cell)
			# Raise the wall cell slightly above the lake height
			terrain_data[lowest_cell] = current_lake_height + 0.05
			continue
			
		# 3. Check Overflow Condition
		if lowest_height < current_lake_height:
			# We found a cell LOWER than the lake level. The lake overflows here!
			overflow_point = lowest_cell
			break
			
		# 4. Expand Lake
		current_lake_height = lowest_height
		_add_to_lake(lowest_cell, lake, mask_data, incoming_river)
		_add_neighbors_to_perimeter(lowest_cell, perimeter, visited, terrain_data)
		
		# 5. Update all tracked walls to stay above the new lake height
		for wall_pos in wall_cells:
			terrain_data[wall_pos] = current_lake_height + 0.05
			
	return {
		"lake": lake,
		"overflow_point": overflow_point
	}

# Adds a cell to the lake and handles erasing it from the incoming river (Constraint 1)
func _add_to_lake(pos: Vector2, lake: Water_Pool, mask_data: Dictionary, incoming_river: River):
	lake.cells.append(pos)
	lake.all_cells.append(pos)
	mask_data["lake"][pos] = true
	
	var river_mask = mask_data["river"]
	if river_mask.get(pos, false) == true:
		river_mask.erase(pos) # Remove from river mask
		
		if incoming_river and incoming_river.river_path.has(pos):
			incoming_river.river_path.erase(pos)
			# If you are using regions/segments, you would also remove the point from the segment here:
			for region in incoming_river.segments:
				if region.points.has(pos):
					region.points.erase(pos)
					region.size -= 1

# Scans 4 directions and adds valid new cells to the perimeter queue
func _add_neighbors_to_perimeter(pos: Vector2, perimeter: Dictionary, visited: Dictionary, terrain_data: Dictionary):
	for dir in DIRECTIONS:
		var neighbor = pos + dir
		if not visited.has(neighbor) and terrain_data.has(neighbor):
			visited[neighbor] = true
			perimeter[neighbor] = terrain_data[neighbor]

# Checks if a cell is part of another water body OR adjacent to one
func _is_wall_cell(
	pos: Vector2, 
	incoming_river: River, 
	ocean_mask: Dictionary, 
	lake_mask: Dictionary, 
	delta_mask: Dictionary, 
	river_mask: Dictionary,
	river_data: Dictionary
) -> bool:
	
	# Helper lambda to check a single coordinate
	var is_other_water = func(check_pos: Vector2) -> bool:
		if ocean_mask.get(check_pos, false) or lake_mask.get(check_pos, false) or delta_mask.get(check_pos, false):
			return true
		if river_mask.get(check_pos, false):
			# It is a river. Is it a DIFFERENT river?
			if river_data.has(check_pos):
				var region: Region = river_data[check_pos]
				if region.associated_water != incoming_river:
					return true
			else:
				# Failsafe: If it's a river but not in river_data, assume it's a wall to be safe
				return true 
		return false

	# 1. Is the cell itself another body of water?
	if is_other_water.call(pos):
		return true
		
	# 2. Is the cell adjacent to another body of water?
	for dir in DIRECTIONS:
		if is_other_water.call(pos + dir):
			return true
			
	return false
