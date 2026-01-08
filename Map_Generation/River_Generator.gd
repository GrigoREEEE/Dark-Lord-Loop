class_name WaterWorks
extends RefCounted

########################################
########## Lake Recognition ############
########################################

## Consumes the world map and converts isolated shallow water (2) into lakes (7).
static func identify_lakes(world_data: Dictionary) -> Dictionary:
	# Work on a deep copy to avoid modifying the original data mid-process
	var new_map = world_data.duplicate(true)
	
	var rows = new_map.keys()
	if rows.size() == 0:
		return new_map
		
	var height = rows.size()
	var width = new_map[0].size()
	
	# Keep track of cells we've already checked to avoid infinite loops
	var visited = []
	for y in range(height):
		visited.append([])
		for x in range(width):
			visited[y].append(false)

	for y in range(height):
		for x in range(width):
			# If we find shallow water (2) that hasn't been visited yet
			if new_map[y][x] == 2 and not visited[y][x]:
				var cluster = []
				var is_ocean = _flood_fill_check_ocean(new_map, x, y, visited, cluster)
				
				# If the cluster is NOT connected to deep water or edges, it's a lake
				if not is_ocean:
					for cell in cluster:
						new_map[cell.y][cell.x] = 7 # Type 7: Lake
						
	return new_map

## Internal helper to find all connected shallow water cells and 
## determine if they touch the "True Ocean" (Deep Water or Map Edge)
static func _flood_fill_check_ocean(grid: Dictionary, start_x: int, start_y: int, visited: Array, cluster: Array) -> bool:
	var width = grid[0].size()
	var height = grid.size()
	var stack = [Vector2i(start_x, start_y)]
	var touches_ocean = false
	
	while stack.size() > 0:
		var current = stack.pop_back()
		var x = current.x
		var y = current.y
		
		if x < 0 or x >= width or y < 0 or y >= height:
			touches_ocean = true
			continue
			
		if visited[y][x]:
			continue
			
		# If we hit Deep Ocean, this entire connected body is part of the Ocean system
		if grid[y][x] == 1:
			touches_ocean = true
			continue
			
		# We only traverse through Shallow Water (2)
		if grid[y][x] == 2:
			visited[y][x] = true
			cluster.append(Vector2i(x, y))
			
			# Check if this shallow water is on the very edge of the map
			if x == 0 or x == width - 1 or y == 0 or y == height - 1:
				touches_ocean = true
			
			# Add neighbors (4-way connectivity)
			stack.push_back(Vector2i(x + 1, y))
			stack.push_back(Vector2i(x - 1, y))
			stack.push_back(Vector2i(x, y + 1))
			stack.push_back(Vector2i(x, y - 1))
			
	return touches_ocean

########################################
########## River Generation ############
########################################

const HEIGHT_MAP = {
	1: -2, 2: -1, 3: 0, 4: 1, 5: 2, 6: 3, 7: 1, 8: 0.5
}

var rivers_database: Dictionary = {} 
var current_river_id: int = 0

func generate_rivers(world_data: Dictionary, grid_ids: Dictionary, num_rivers: int) -> Dictionary:
	var new_world = world_data.duplicate(true)
	var rows = new_world.keys().size()
	var cols = new_world[0].size()
	
	for i in range(num_rivers):
		var start_pos = _find_river_start(new_world)
		if start_pos != Vector2i(-1, -1):
			_grow_river(new_world, grid_ids, start_pos, rows, cols)
			
	return new_world

func _find_river_start(world: Dictionary) -> Vector2i:
	var mountains = []
	var others = []
	
	for r in world.keys():
		for c in range(world[r].size()):
			if world[r][c] == 6: # Priority: Mountains
				mountains.append(Vector2i(c, r))
			elif world[r][c] in [5, 7]: # Backup: Hills/Lakes
				others.append(Vector2i(c, r))
	
	if not mountains.is_empty():
		mountains.shuffle()
		return mountains[0]
	elif not others.is_empty():
		others.shuffle()
		return others[0]
	return Vector2i(-1, -1)

func _grow_river(world: Dictionary, grid: Dictionary, start: Vector2i, rows: int, cols: int):
	var current = start
	var path = []
	var visited = [] # Keep track of where this specific river has been
	current_river_id += 1
	
	# Growth loop
	for step in range(200): # Increased step limit for large maps
		path.append(grid[current.y][current.x])
		visited.append(current)
		
		# 1. Check if we reached a destination (Shallow Ocean or another Lake)
		# We don't turn the start cell (Mountain/Lake) into type 8
		if step > 0:
			if world[current.y][current.x] in [2, 7]:
				break
			world[current.y][current.x] = 8
		
		# 2. Find neighbors
		var neighbors = [
			Vector2i(current.x + 1, current.y), Vector2i(current.x - 1, current.y),
			Vector2i(current.x, current.y + 1), Vector2i(current.x, current.y - 1)
		]
		
		var current_height = HEIGHT_MAP[world[current.y][current.x]]
		var valid_moves = []
		
		for n in neighbors:
			# Bounds check
			if n.x >= 0 and n.x < cols and n.y >= 0 and n.y < rows:
				var target_type = world[n.y][n.x]
				var target_height = HEIGHT_MAP[target_type]
				
				# CRITICAL: Growth rules
				# - Must be lower or equal height
				# - Must not be a cell this river already visited
				# - Must not be deep ocean (1) or mountain source (6) unless it's the very start
				if target_height <= current_height and not visited.has(n):
					if target_type != 1 and target_type != 8:
						valid_moves.append(n)
		
		# 3. Handle Dead Ends (Logic 4)
		if valid_moves.is_empty():
			if step > 0: # Don't turn the source mountain into a lake
				world[current.y][current.x] = 7 
			break
			
		# 4. Movement Selection (Logic 5: Natural Winding)
		# Sort moves so the river PREFERS to go down, but can go flat
		valid_moves.sort_custom(func(a, b):
			return HEIGHT_MAP[world[a.y][a.x]] < HEIGHT_MAP[world[b.y][b.x]]
		)
		
		# 80% chance to take the lowest path, 20% to take any valid path (winding)
		if randf() < 0.8:
			current = valid_moves[0]
		else:
			current = valid_moves.pick_random()

	rivers_database[current_river_id] = path
