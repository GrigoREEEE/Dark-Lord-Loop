extends Node

class_name Lake_Maker

# Scans a single river for cells below 'lake_threshold' and groups them into Lake objects.
# Returns an array of Lake objects found along this river's path.
func extract_lakes_from_river(map_data: Dictionary, river: River) -> Array[Lake]:
	var lake_threshold = 0.12
	var potential_lake_cells = {}
	
	# --- 1. IDENTIFY ALL LOW-LYING WATER CELLS ---
	# We collect every pixel from the river that sits in a depression.
	for segment in river.segments:
		for cell in segment:
			# Check height. Default to 1.0 (land) if map data missing.
			if map_data.get(cell, 1.0) < lake_threshold:
				potential_lake_cells[cell] = true
	
	if potential_lake_cells.is_empty():
		return []

	# --- 2. CLUSTER INTO INDIVIDUAL LAKES (Connected Components) ---
	# Even a single river might have multiple separate lakes along its path.
	# We use flood-fill to separate them.
	
	var found_lakes: Array[Lake] = []
	var visited = {}
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for cell in potential_lake_cells.keys():
		if visited.has(cell): continue
		
		# Start a new Lake cluster
		var current_lake_area: Array[Vector2] = []
		var queue = [cell]
		visited[cell] = true
		
		while not queue.is_empty():
			var current = queue.pop_back()
			current_lake_area.append(current)
			
			for d in directions:
				var neighbor = current + d
				
				# If neighbor is also a low-lying water cell and not visited
				if potential_lake_cells.has(neighbor) and not visited.has(neighbor):
					visited[neighbor] = true
					queue.append(neighbor)
		
		# --- 3. CREATE LAKE OBJECT ---
		# Only create if it's significant (e.g., more than 5 pixels)
		if current_lake_area.size() > 5:
			var new_lake = Lake.new()
			new_lake.id = "LA" + str(rng.randi() % 9999).pad_zeros(4)
			new_lake.lake_area = current_lake_area
			
			# Since this lake was found on THIS river, we can assume it feeds/leaves it.
			# Ideally, you'd check upstream/downstream connections more rigorously here.
			new_lake.feeding_rivers.append(river)
			new_lake.leaving_rivers.append(river)
			
			found_lakes.append(new_lake)
			
	return found_lakes
