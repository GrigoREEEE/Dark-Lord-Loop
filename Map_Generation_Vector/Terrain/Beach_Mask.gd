extends Node

class_name Beach_Identification

########################################
######## Beach Identification ##########
########################################

# Returns a Dictionary[Vector2, bool]
# True = Within 'max_dist' of the ocean (Real Beach)
# False = Too far from ocean (Inland Lowland)
func get_beach_mask(ocean_mask: Dictionary, max_dist: int = 8, res_scale : float = 1.0) -> Dictionary:
		
	max_dist = int(max_dist * res_scale)
	
	var beach_mask = {}
	var distance_map = {} # Stores distance to nearest ocean
	var queue = []        # For BFS
	
	# --- STEP 1: INITIALIZE BFS ---
	# Add ALL Ocean cells to the queue with distance 0.
	# Initialize all Land cells with "Infinity" distance (-1).
	for pos in ocean_mask:
		if ocean_mask[pos] == true:
			distance_map[pos] = 0
			queue.append(pos)
		else:
			distance_map[pos] = -1 # Unvisited Land
			
	# --- STEP 2: MULTI-SOURCE FLOOD FILL ---
	var directions = [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
	
	# We use a standard pointer-based queue for speed in GDScript
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		
		var current_dist = distance_map[current]
		
		# Optimization: If we are already at max_dist, we don't need to check neighbors,
		# because any neighbor would be dist+1 (which is too far).
		if current_dist >= max_dist:
			continue
			
		for d in directions:
			var neighbor = current + d
			
			if distance_map.has(neighbor):
				# If neighbor is unvisited (-1), we found a shorter path to it!
				if distance_map[neighbor] == -1:
					distance_map[neighbor] = current_dist + 1
					queue.append(neighbor)
					
	# --- STEP 3: BUILD THE BOOLEAN MASK ---
	# Now simply check the distance map.
	for pos in ocean_mask:
		# We only care about LAND cells.
		if ocean_mask[pos] == false:
			var dist = distance_map.get(pos, -1)
			
			# If visited and within range -> True Beach
			if dist != -1 and dist <= max_dist:
				beach_mask[pos] = true
			else:
				beach_mask[pos] = false
				
	return beach_mask
