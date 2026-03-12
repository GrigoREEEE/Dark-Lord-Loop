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
# True = Within 'distance' of the ocean.
func generate_beach_mask(
	ocean_mask: Dictionary, 
	width: int, 
	height: int, 
	distance: int, 
	res_scale: float = 1.0
) -> Dictionary[Vector2, bool]:
	
	var max_dist: int = int(distance * res_scale)
	var beach_mask: Dictionary[Vector2, bool] = {}
	
	# If distance is 0, there are no beaches
	if max_dist <= 0:
		return beach_mask

	# --- OPTIMIZATION 1: PRIMITIVE QUEUE ---
	# We use Vector3(x, y, current_distance) instead of instantiating 
	# thousands of heavy Dictionaries. This is drastically faster in GDScript.
	var queue: Array[Vector3] = []
	var directions: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]

	# --- OPTIMIZATION 2: COASTLINE SEEDING ---
	# Instead of loading the entire ocean into the queue, we ONLY look for land cells
	# that are directly touching the ocean, and seed the queue with those.
	for ocean_pos: Vector2 in ocean_mask:
		for d in directions:
			var neighbor: Vector2 = ocean_pos + d
			
			# Fast bounds check
			if neighbor.x < 0 or neighbor.x >= width or neighbor.y < 0 or neighbor.y >= height:
				continue
				
			# If it's Land (not in ocean_mask) and hasn't been added to the beach mask yet
			if not ocean_mask.has(neighbor) and not beach_mask.has(neighbor):
				beach_mask[neighbor] = true
				queue.append(Vector3(neighbor.x, neighbor.y, 1.0))

	# --- OPTIMIZATION 3: UNIFIED SPARSE DICTIONARY ---
	# `beach_mask` acts as our visited list. We don't need a separate `visited` tracker.
	var head: int = 0
	
	while head < queue.size():
		var current: Vector3 = queue[head]
		head += 1
		
		var current_dist: int = int(current.z)
		
		# Stop expanding this branch if we have reached the max beach depth
		if current_dist >= max_dist:
			continue
			
		var current_pos := Vector2(current.x, current.y)
		
		for d in directions:
			var neighbor: Vector2 = current_pos + d
			
			# Fast bounds check
			if neighbor.x < 0 or neighbor.x >= width or neighbor.y < 0 or neighbor.y >= height:
				continue
				
			# Must be Land (not in ocean_mask) and not yet visited (not in beach_mask)
			if not ocean_mask.has(neighbor) and not beach_mask.has(neighbor):
				beach_mask[neighbor] = true
				queue.append(Vector3(neighbor.x, neighbor.y, current_dist + 1.0))

	return beach_mask
