extends Node

class_name Beach_Identification

########################################
######## Beach Identification ##########
########################################

# Returns a Dictionary[Vector2, bool]
# True = Within 'max_dist' of the ocean (Real Beach)
# False = Too far from ocean (Inland Lowland)
func generate_beach_mask2(ocean_mask: Dictionary, distance: int, res_scale : float = 1.0) -> Dictionary[Vector2, bool]:
	distance = int(distance * res_scale)
	var beach_mask: Dictionary[Vector2, bool] = {}
	var visited = {} # To keep track of cells we've already processed
	var queue = []   # BFS Queue

	# 1. Initialization
	# Iterate through the entire map to categorize cells
	for pos in ocean_mask:
		if ocean_mask[pos] == true:
			# It is Ocean: Add to queue with distance 0, mark visited
			queue.append({ "pos": pos, "dist": 0 })
			visited[pos] = true
			beach_mask[pos] = false # Ocean is not beach
		else:
			# It is Land: Initialize as false (not beach yet)
			beach_mask[pos] = false

	# 2. Define directions (Standard 4-way Manhattan distance)
	# Add diagonals to this array if you want beaches to expand diagonally (8-way)
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]

	# 3. Multi-Source BFS
	# We use a 'head' index instead of pop_front() for better performance in GDScript
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		
		var current_pos = current["pos"]
		var current_dist = current["dist"]

		# Stop expanding this branch if we have reached the max distance
		if current_dist >= distance:
			continue

		# Check neighbors
		for dir in directions:
			var neighbor_pos = current_pos + dir

			# Skip if out of bounds (not in our world data)
			if not ocean_mask.has(neighbor_pos):
				continue
			
			# Skip if already visited (either it was Ocean or already marked as Beach)
			if visited.has(neighbor_pos):
				continue

			# If we are here, the neighbor is unvisited Land
			visited[neighbor_pos] = true
			beach_mask[neighbor_pos] = true # Mark as Beach
			
			# Add to queue to continue expanding inland
			queue.append({ "pos": neighbor_pos, "dist": current_dist + 1 })

	return beach_mask
	
# Returns a Sparse Dictionary[Vector2, bool] containing ONLY beach cells.
# True = Within 'distance' of the ocean OR a river delta.
func generate_beach_mask(
	world_data: World_Data
) -> void:
	var res_scale: float = world_data.res_scale
	var ocean_mask: Dictionary = world_data.mask_data["ocean"]
	var river_map: Dictionary = world_data.map_data["river"]
	var width: int = world_data.grid_width
	var height: int = world_data.grid_height
	var distance: int = world_data.beach_distance
	
	var max_dist: int = distance 
	var beach_mask: Dictionary[Vector2, bool] = {}

	# --- OPTIMIZATION 1: PRIMITIVE QUEUE ---
	var queue: Array[Vector3] = []

	# Helper lambda to quickly check if a cell is "Water that makes sand"
	var is_sand_source = func(pos: Vector2) -> bool:
		if ocean_mask.has(pos):
			return true
		if river_map.has(pos):
			# Only generate beaches for deltas, not standard inland rivers
			if river_map[pos].subtype == "River Delta":
				return true
		return false

	# --- OPTIMIZATION 2: COASTLINE & DELTA SEEDING ---
	# Collect all valid water cells to seed the beach from
	var sand_sources: Array[Vector2] = []
	sand_sources.append_array(ocean_mask.keys())
	
	for river_cell in river_map:
		if river_map[river_cell].subtype == "River Delta":
			sand_sources.append(river_cell)

	# Seed the queue with land cells touching the water
	for water_pos in sand_sources:
		var neighbors = global._get_hex_neighbors(water_pos)
		for neighbor in neighbors:
			
			if neighbor.x < 0 or neighbor.x >= width or neighbor.y < 0 or neighbor.y >= height:
				continue
				
			# If it's not a sand source (meaning it is land), and hasn't been flagged yet
			if not is_sand_source.call(neighbor) and not beach_mask.has(neighbor):
				beach_mask[neighbor] = true
				queue.append(Vector3(neighbor.x, neighbor.y, 1.0))

	# --- OPTIMIZATION 3: UNIFIED SPARSE DICTIONARY ---
	var head: int = 0
	
	while head < queue.size():
		var current: Vector3 = queue[head]
		head += 1
		var current_dist: int = int(current.z)
		
		if current_dist >= max_dist:
			continue
			
		var current_pos := Vector2(current.x, current.y)
		
		var neighbors = global._get_hex_neighbors(current_pos)
		for neighbor in neighbors:
			
			if neighbor.x < 0 or neighbor.x >= width or neighbor.y < 0 or neighbor.y >= height:
				continue
				
			# Must be land (not ocean/delta water) and not yet visited
			if not is_sand_source.call(neighbor) and not beach_mask.has(neighbor):
				beach_mask[neighbor] = true
				queue.append(Vector3(neighbor.x, neighbor.y, current_dist + 1.0))

	world_data.mask_data["beach"] = beach_mask
