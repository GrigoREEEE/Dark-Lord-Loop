extends Node

class_name Beach_Identification

########################################
######## Beach Identification ##########
########################################

# Returns a Dictionary[Vector2, bool]
# True = Within 'max_dist' of the ocean (Real Beach)
# False = Too far from ocean (Inland Lowland)
func generate_beach_mask(ocean_mask: Dictionary, distance: int, res_scale : float = 1.0) -> Dictionary:
	distance = int(distance * res_scale)
	var beach_mask = {}
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
