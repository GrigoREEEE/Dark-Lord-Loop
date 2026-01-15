class_name WaterWorksVector_V2
extends RefCounted

# Ensure these match your WorldGenerator enum
enum LandType {
	DEEP_WATER = 1,
	SHALLOW_WATER = 2,
	COAST = 3,
	PLAINS = 4,
	HILLS = 5,
	MOUNTAINS = 6,
	LAKE = 7,
	RIVER = 8
}

var rivers : Array # array of all rivers; Array[Dictionary[Vector2]]

static func identify_lakes(map_context: Object, width: int, height: int) -> void:
	var grid = map_context.current_land_map 
	# Access the inverse map reference
	var inverse_grid = map_context.inverse_land_map
	
	var visited = {} 

	for pos in grid:
		if visited.has(pos) or grid[pos] != LandType.SHALLOW_WATER:
			continue
			
		var cluster = []
		var is_ocean = _flood_fill_check_ocean(grid, pos, visited, cluster, width, height)
		
		if not is_ocean:
			# Prepare the LAKE array if it doesn't exist yet
			if not inverse_grid.has(LandType.LAKE):
				inverse_grid[LandType.LAKE] = []

			# Get a direct reference to the Shallow Water array to speed up lookups slightly
			var shallow_water_array: Array = inverse_grid.get(LandType.SHALLOW_WATER, [])

			for lake_pos in cluster:
				# 1. Update the main dictionary
				map_context.current_land_map[lake_pos] = LandType.LAKE
				
				# 2. Remove from the old inverse list (Shallow Water)
				# Note: 'erase' searches the array (O(n)). If arrays are massive, this can be slow.
				shallow_water_array.erase(lake_pos)
				
				# 3. Add to the new inverse list (Lake)
				inverse_grid[LandType.LAKE].append(lake_pos)

# _flood_fill_check_ocean remains exactly the same
static func _flood_fill_check_ocean(grid: Dictionary, start_pos: Vector2, visited: Dictionary, cluster: Array, width: int, height: int) -> bool:
	var stack = [start_pos]
	var touches_ocean = false
	
	while stack.size() > 0:
		var current = stack.pop_back()
		
		if visited.has(current):
			continue
			
		if current.x < 0 or current.x >= width or current.y < 0 or current.y >= height:
			touches_ocean = true
			continue
			
		var type = grid.get(current, LandType.DEEP_WATER)
		
		if type == LandType.DEEP_WATER:
			touches_ocean = true
			continue
			
		if type == LandType.SHALLOW_WATER:
			visited[current] = true
			cluster.append(current)
			
			if current.x == 0 or current.x == width - 1 or current.y == 0 or current.y == height - 1:
				touches_ocean = true
			
			stack.append(current + Vector2.RIGHT)
			stack.append(current + Vector2.LEFT)
			stack.append(current + Vector2.DOWN)
			stack.append(current + Vector2.UP)
			
	return touches_ocean

########################################
########## River Generation ############
########################################

func generate_rivers(world_data: Dictionary, inverse_land_map: Dictionary, river_count: int) -> Array[Array]:
	var all_rivers: Array[Array] = []
	var generated_sources: Array[Vector2] = [] # Track sources here
	
	var attempts = 0
	var max_attempts = river_count * 5 # Increased attempts to account for stricter placement

	while all_rivers.size() < river_count and attempts < max_attempts:
		attempts += 1
		
		# PASS generated_sources to the function
		var source = get_river_source(inverse_land_map, generated_sources, 40.0)
		
		if source == Vector2(-1, -1):
			continue 

		var mouth = get_river_mouth(world_data, source)
		if mouth == Vector2(-1, -1):
			continue 

		var river_path = generate_river_path(world_data, source, mouth)
		
		if river_path.is_empty():
			continue 
			
		# Success! Store the river AND the source
		all_rivers.append(river_path)
		generated_sources.append(source) # Add to list for next iteration

	print("Generated ", all_rivers.size(), " rivers.")
	return all_rivers

func get_river_source(inverse_land_map: Dictionary, existing_sources: Array[Vector2], min_distance: float = 40.0) -> Vector2:
	# Weights: Higher numbers = higher probability.
	var source_weights = {
		6: 10.0, # Mountains
		5: 2.0,  # Hills
		7: 2.0   # Lakes
	}
	
	# 1. Filter valid candidates types
	var valid_types = []
	var total_weight = 0.0
	for type in source_weights.keys():
		if inverse_land_map.has(type) and inverse_land_map[type].size() > 0:
			valid_types.append(type)
			total_weight += source_weights[type]
	
	if valid_types.is_empty():
		return Vector2(-1, -1)

	# 2. Try to find a valid source that is far enough from others
	# We try 20 times. If we fail 20 times, we assume the map is too crowded.
	for attempt in range(20):
		# Weighted Random Selection
		var roll = randf() * total_weight
		var current_sum = 0.0
		var selected_type = -1
		
		for type in valid_types:
			current_sum += source_weights[type]
			if roll <= current_sum:
				selected_type = type
				break
		
		var candidate: Vector2 = inverse_land_map[selected_type].pick_random()
		
		# 3. Check distance against ALL existing sources
		var is_far_enough = true
		for existing in existing_sources:
			if candidate.distance_to(existing) < min_distance:
				is_far_enough = false
				break
		
		# If valid, return immediately
		if is_far_enough:
			return candidate

	# If we exit the loop, we failed to find a spot 20 times
	push_warning("River Gen: Could not find a source > 40 units from others.")
	return Vector2(-1, -1)
	
func get_river_mouth(current_land_map: Dictionary, source: Vector2, max_search_radius: int = 50) -> Vector2:
	print("Getting Mouth")
	var shallow_ocean_type = 2
	
	# We start expanding outward from the source
	# r is the "radius" or distance from the center
	for r in range(1, max_search_radius + 1):
		
		# A list to store any ocean cells found in this specific ring/layer
		var found_ocean_cells = []
		
		# 1. Check Top and Bottom rows of the square ring
		# x ranges from (source.x - r) to (source.x + r)
		for x_offset in range(-r, r + 1):
			var top_pos = source + Vector2(x_offset, -r)
			var bot_pos = source + Vector2(x_offset, r)
			
			if current_land_map.get(top_pos) == shallow_ocean_type:
				found_ocean_cells.append(top_pos)
			if current_land_map.get(bot_pos) == shallow_ocean_type:
				found_ocean_cells.append(bot_pos)
		
		# 2. Check Left and Right columns of the square ring
		# We exclude the corners (range starts at -r+1 and ends at r-1) because
		# they were already checked in the top/bottom steps.
		for y_offset in range(-r + 1, r):
			var left_pos = source + Vector2(-r, y_offset)
			var right_pos = source + Vector2(r, y_offset)
			
			if current_land_map.get(left_pos) == shallow_ocean_type:
				found_ocean_cells.append(left_pos)
			if current_land_map.get(right_pos) == shallow_ocean_type:
				found_ocean_cells.append(right_pos)
		
		# 3. If we found any ocean cells in this ring, pick one and return it
		if not found_ocean_cells.is_empty():
			# Picking a random one prevents the river from always favoring 
			# the top-left ocean if multiple cells are equidistant.
			return found_ocean_cells.pick_random()

	# Safety return if no ocean is found within the max radius
	push_warning("River Gen: No shallow ocean found within search radius.")
	return Vector2(-1, -1)

func generate_river_path(current_land_map: Dictionary, source: Vector2, mouth: Vector2) -> Array[Vector2]:
	print("Generate Path")
	# This priority queue stores [priority_score, cell_position]
	var frontier = [] 
	frontier.append([0, source])
	
	# To reconstruct the path later: came_from[next_cell] = previous_cell
	var came_from = {}
	came_from[source] = null
	
	# The cost to reach a specific cell
	var cost_so_far = {}
	cost_so_far[source] = 0
	
	while not frontier.is_empty():
		# Sort to emulate a Priority Queue (Lowest F-score first)
		# Note: For massive maps, a binary heap is faster, but this works for standard grid sizes.
		frontier.sort_custom(func(a, b): return a[0] < b[0])
		var current = frontier.pop_front()[1]
		
		# If we reached the ocean, stop!
		if current == mouth:
			break
		
		for next in get_valid_neighbors(current):
			if not current_land_map.has(next):
				continue
				
			# 1. Calculate the cost to move to this neighbor
			var move_cost = 1.0
			
			# WINDING LOGIC: Add random noise to the terrain cost.
			# This tricks the algorithm into taking a "meandering" path rather than a straight line.
			move_cost += randf() * 10.0
			
			# NATURAL FLOW LOGIC: Penalize moving uphill.
			# If the next tile is higher than the current one, add a massive penalty cost.
			# It's still possible (to prevent getting stuck), but the river will avoid it if it can.
			var h_current = get_height_rank(current_land_map[current])
			var h_next = get_height_rank(current_land_map[next])
			if h_next > h_current:
				move_cost += 50.0 
			
			var new_cost = cost_so_far[current] + move_cost
			
			if not cost_so_far.has(next) or new_cost < cost_so_far[next]:
				cost_so_far[next] = new_cost
				# Heuristic: Manhattan distance to nudge it generally towards the ocean
				var priority = new_cost + (abs(mouth.x - next.x) + abs(mouth.y - next.y))
				frontier.append([priority, next])
				came_from[next] = current
	
	# Reconstruct the path backwards from Mouth -> Source
	var path: Array[Vector2] = []
	var curr = mouth
	
	# If A* failed to find a path (e.g. boxed in by mountains), return empty
	if not came_from.has(mouth):
		push_warning("River Gen: Could not find path to mouth.")
		return []
		
	while curr != null:
		path.append(curr)
		curr = came_from.get(curr)
	
	path.reverse() # Flip it so it goes Source -> Mouth
	return path

# Helper to get orthogonal neighbors (Up, Down, Left, Right)
func get_valid_neighbors(cell: Vector2) -> Array[Vector2]:
	return [
		cell + Vector2.UP,
		cell + Vector2.DOWN,
		cell + Vector2.LEFT,
		cell + Vector2.RIGHT
	]

# Helper to convert cell types into "Height" for flow logic
# 6 (Mtn) > 5 (Hills) > 4 (Grass) > 3 (Coast) > 2 (Shallow)
func get_height_rank(type: int) -> int:
	match type:
		6: return 5 # Mountain
		5: return 4 # Hills
		4: return 3 # Grass/Forest
		7: return 3 # Lake (Treat same as grass or slightly lower)
		3: return 2 # Coast
		2: return 1 # Shallow Ocean
		1: return 0 # Deep Ocean
		_: return 0
