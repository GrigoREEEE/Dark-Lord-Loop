extends Node

class_name Delta

func generate_delta(
	river: River, 
	ocean_mask: Dictionary,
	stream_config: Dictionary,
	noise_seed : int,
	boundary_width: int = 3
):
	if river.segments.size() < 2: return

	var last_idx = river.segments.size() - 1
	var delta_segment = river.segments[last_idx]
	var upstream_segment = river.segments[last_idx - 1]
	
	# 1. SETUP SANDBOX
	var boundary_set = {}
	for cell in delta_segment: boundary_set[cell] = true
	delta_segment.clear() # Wipe clean
	
	# 2. FIND SOURCES & FLOW
	var sources = []
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	for cell in upstream_segment:
		for d in directions:
			if boundary_set.has(cell + d):
				sources.append(cell); break
	if sources.is_empty(): sources.append(upstream_segment.back())
	
	var avg_source = Vector2.ZERO
	for s in sources: avg_source += s
	avg_source /= sources.size()
	
	var avg_delta = Vector2.ZERO; var c=0
	for b in boundary_set: 
		if c%10==0: avg_delta += b
		c+=1
	if c>0: avg_delta /= (c/10.0)
	
	var flow_dir = (avg_delta - avg_source).normalized()
	if flow_dir == Vector2.ZERO: flow_dir = Vector2.DOWN
	
	var generated_streams = []

	# --- 3. GENERATE BOUNDARY STREAMS (Deterministic Extraction) ---
	# Instead of using physics agents that might fail, we directly extract 
	# the exact edges of the fan shape we already created.
	var edges = _extract_delta_edge_paths(boundary_set, sources, flow_dir)
	var left_edge_path = edges[0]
	var right_edge_path = edges[1]
	
	# Add them to the list to be thickened later
	if not left_edge_path.is_empty():
		generated_streams.append({ "path": left_edge_path, "width": boundary_width })
	if not right_edge_path.is_empty():
		generated_streams.append({ "path": right_edge_path, "width": boundary_width })
	
	# 4. GENERATE INTERNAL STREAMS (Natural Wander)
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for width_key in stream_config.keys():
		var count = stream_config[width_key]
		for i in range(count):
			# Note: We still use the physics agent for internal streams
			var path : Array[Vector2] = _generate_smart_stream(
				sources, flow_dir, boundary_set, ocean_mask
			)
			generated_streams.append({ "path": path, "width": width_key })

	# 5. RASTERIZE (Thicken & Commit)
	var final_delta_set = {}
	
	for stream in generated_streams:
		var w = stream.width
		var path = stream.path
		if path.is_empty(): continue
		
		for cell in path:
			final_delta_set[cell] = true # Center line
			
			# Thicken
			if w > 1:
				var radius = (float(w) - 0.5) / 2.0
				var r_squared = radius * radius
				var scan = int(ceil(radius))
				
				for dx in range(-scan, scan + 1):
					for dy in range(-scan, scan + 1):
						if dx*dx + dy*dy <= r_squared + 0.5:
							var n = cell + Vector2(dx, dy)
							# Constraint: stay inside the original fan shape
							if boundary_set.has(n):
								final_delta_set[n] = true

	# Commit to river segment
	delta_segment.append_array(final_delta_set.keys())


# Generates a stream that flows until it hits the ocean.
# - Ignores other streams (can cross over).
# - Strictly constrained to 'boundary' set.
# - Uses momentum + noise for natural curves.
func _generate_smart_stream(
	sources: Array, 
	flow_dir: Vector2, 
	boundary: Dictionary, 
	ocean_mask: Dictionary,
	noise_seed: int = 0
) -> Array[Vector2]:
	
	var rng = RandomNumberGenerator.new()
	if noise_seed != 0: rng.seed = noise_seed
	else: rng.randomize()
	
	# SETUP NOISE
	var noise = FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.04 # Low frequency for wide, lazy meanders
	
	# 1. INITIALIZATION
	var start_node = sources[rng.randi() % sources.size()]
	var pos_f = Vector2(start_node) 
	var velocity = flow_dir.normalized()
	
	# Config
	var wander_strength = 1.0 
	var gravity = 0.08  # Very low gravity = allows crossing sideways
	
	# 2. PHYSICS LOOP
	var path : Array[Vector2] = [start_node]
	var visited_in_this_path = {start_node: true} # Only avoid self-intersection
	
	var steps = 0
	var max_steps = boundary.size() * 4 # Allow long, winding paths
	
	while steps < max_steps:
		steps += 1
		
		# A. STEERING
		# Sample noise (-1 to 1)
		var n_val = noise.get_noise_1d(steps * 4.0) 
		var steer_angle = n_val * wander_strength
		
		# Rotate velocity
		velocity = velocity.rotated(steer_angle)
		
		# Apply weak gravity (pull towards ocean)
		velocity = velocity.lerp(flow_dir, gravity).normalized()
		
		# B. MOVE (Sub-pixel)
		var next_pos_f = pos_f + (velocity * 0.7) # Small steps for precision
		var next_cell = next_pos_f.round()
		
		# C. CHECKS
		
		# 1. OCEAN (Success!)
		if ocean_mask.get(next_cell, false) == true:
			path.append(next_cell)
			break
			
		# 2. BOUNDARY (Constraint)
		# If we hit the edge of the fan, we must bounce or slide back in.
		if not boundary.has(next_cell):
			# Hard Bounce: Reflect velocity back towards the center/flow
			# We mix the flow_dir in strongly to force it back on track
			velocity = velocity.lerp(flow_dir, 0.5).normalized()
			
			# Nudge position slightly back to safe ground to prevent sticking
			pos_f = pos_f.lerp(Vector2(path.back()), 0.5)
			continue
			
		# 3. SELF-INTERSECTION (Loop prevention)
		# We allow crossing OTHER streams, but we shouldn't loop our OWN path tightly.
		# (Checking the last 10 steps is usually enough to prevent instant 180s)
		if visited_in_this_path.has(next_cell):
			# Allow crossing self if it's an old part of the path (loops), 
			# but prevent stalling on the same pixel.
			if next_cell == path.back():
				continue 
		
		# D. COMMIT
		if next_cell != path.back():
			path.append(next_cell)
			visited_in_this_path[next_cell] = true
			
		pos_f = next_pos_f
		
	return path

# Helper to deterministically extract the outer edges of the delta shape.
# Returns an Array containing two paths: [left_edge_path, right_edge_path]
func _extract_delta_edge_paths(boundary_set: Dictionary, sources: Array, flow_dir: Vector2) -> Array:
	var edge_cells = []
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	
	# 1. Find all cells that are on the edge boundary
	for cell in boundary_set:
		var is_edge = false
		for d in directions:
			if not boundary_set.has(cell + d):
				is_edge = true
				break
		if is_edge:
			edge_cells.append(cell)
			
	if edge_cells.is_empty(): return [[], []]
	
	# 2. Calculate Center Line (to split Left vs Right)
	var avg_source = Vector2.ZERO
	for s in sources: avg_source += s
	avg_source /= sources.size()
	
	# A vector perpendicular to flow, pointing "Right"
	var right_vec = Vector2(-flow_dir.y, flow_dir.x)
	
	var left_path = []
	var right_path = []
	
	# 3. Split edges based on which side of the center line they are on
	for cell in edge_cells:
		# Vector from source center to this edge cell
		var to_cell = cell - avg_source
		# Dot product determines if it's to the left or right of the flow
		var side_dot = to_cell.dot(right_vec)
		
		if side_dot < 0:
			left_path.append(cell)
		else:
			right_path.append(cell)
			
	# 4. Sort paths upstream-to-downstream for clean rasterization
	var sort_func = func(a, b): return a.dot(flow_dir) < b.dot(flow_dir)
	left_path.sort_custom(sort_func)
	right_path.sort_custom(sort_func)
	
	return [left_path, right_path]

# Creates a full-world boolean mask for the Delta.
# - Keys: Vector2 coordinates for every tile in the map.
# - Values: TRUE if the tile is part of the last river segment, FALSE otherwise.
func create_delta_mask(river: River, width: int, height: int) -> Dictionary:
	var mask = {}
	
	# 1. Initialize the entire world to FALSE
	for x in range(width):
		for y in range(height):
			mask[Vector2(x, y)] = false
			
	# 2. Paint the Delta cells to TRUE
	if not river.segments.is_empty():
		var delta_segment = river.segments[-1]
		
		for cell in delta_segment:
			# Safety check to ensure we don't write out of bounds
			if cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height:
				mask[cell] = true
				
	return mask
	
# Creates a boolean mask (Dictionary) where every cell in the delta is TRUE.
# Returns empty dictionary if river has no segments.
func create_delta_mask2(river: River) -> Dictionary:
	var mask = {}
	
	if river.segments.is_empty():
		return mask
		
	# The delta is defined as the very last segment in the river
	var delta_segment = river.segments[-1]
	
	for cell in delta_segment:
		mask[cell] = true
		
	return mask

# Identifies islands within the delta and sculpts their elevation.
# - Islands are defined as (Delta Mask - River Water).
# - Elevation is calculated based on distance from the water edge.
# - Height ranges from 0.12 (edge) to 0.18 (center).
func naturalize_delta_islands(map_data: Dictionary, river: River, delta_mask: Dictionary):
	if river.segments.is_empty(): return

	# 1. IDENTIFY "RAW" ISLAND CELLS
	# An island cell is inside the delta mask but NOT in the river water.
	var delta_water_segment = river.segments[-1]
	var water_set = {}
	for cell in delta_water_segment:
		water_set[cell] = true
		
	var all_island_cells = {}
	for cell in delta_mask.keys():
		if delta_mask[cell] == true and not water_set.has(cell):
			all_island_cells[cell] = true

	if all_island_cells.is_empty():
		return # No islands found

	# 2. GROUP INTO DISTINCT ISLANDS
	# We use flood-fill to find connected clumps of land.
	var islands: Array[Array] = []
	var visited = {}
	
	for cell in all_island_cells.keys():
		if visited.has(cell): continue
		
		# Start a new island
		var current_island: Array[Vector2] = []
		var stack = [cell]
		visited[cell] = true
		
		while not stack.is_empty():
			var current = stack.pop_back()
			current_island.append(current)
			
			var neighbors = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
			for d in neighbors:
				var n = current + d
				# If neighbor is valid land and not visited
				if all_island_cells.has(n) and not visited.has(n):
					visited[n] = true
					stack.append(n)
		
		islands.append(current_island)

	# 3. SCULPT EACH ISLAND
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for island in islands:
		# A. Compute Distance Field (Manhattan distance from water)
		# We identify "edge" cells first (those touching water or empty space)
		var distances = {}
		var queue = []
		
		# Initialize edges
		for cell in island:
			var is_edge = false
			var neighbors = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
			for d in neighbors:
				var n = cell + d
				# It's an edge if the neighbor is WATER or OUT OF DELTA
				if not all_island_cells.has(n):
					is_edge = true
					break
			
			if is_edge:
				distances[cell] = 0
				queue.append(cell)
			else:
				distances[cell] = -1 # Unprocessed interior

		# BFS to fill interior distances
		var max_dist = 0
		var head = 0
		while head < queue.size():
			var current = queue[head]
			head += 1
			var d_val = distances[current]
			
			if d_val > max_dist: max_dist = d_val
			
			var neighbors = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
			for dir in neighbors:
				var n = current + dir
				# If it's part of this island and hasn't been distance-mapped yet
				if distances.has(n) and distances[n] == -1:
					distances[n] = d_val + 1
					queue.append(n)
		
		# B. Apply Heights
		# Range: 0.12 (Edge) -> 0.18 (Center)
		# Formula: 0.12 + (0.06 * (dist / max_dist))
		for cell in island:
			var dist = distances[cell]
			
			var height_factor = 0.0
			if max_dist > 0:
				height_factor = float(dist) / float(max_dist)
			
			# Lerp height
			var base_height = lerp(0.12, 0.25, height_factor)
			
			# Add subtle noise for roughness (range -0.005 to +0.005)
			var noise = rng.randf_range(-0.005, 0.005)
			
			map_data[cell] = base_height + noise

# Erodes the terrain adjacent to the delta to create a smooth transition.
# - erosion_radius: How many pixels out from the delta to affect.
# - erosion_strength: How much to subtract from the height (0.05 is subtle, 0.1 is strong).
func erode_delta_edges(
	map_data: Dictionary, 
	delta_mask: Dictionary, 
	erosion_radius: int = 4, 
	erosion_strength: float = 0.2
):
	if delta_mask.is_empty(): return

	# 1. IDENTIFY BORDER CELLS
	# We want cells that are NOT in the delta, but are within 'radius' of it.
	var cells_to_erode = {}
	var current_boundary = delta_mask.keys()
	var processed = delta_mask.duplicate() # Don't erode the delta itself, it's already water
	
	# Iterative expansion (Breadth-First Search)
	for i in range(erosion_radius):
		var next_boundary = []
		
		for cell in current_boundary:
			var neighbors = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
			for d in neighbors:
				var n = cell + d
				
				if not map_data.has(n): continue
				if processed.has(n): continue
				
				# Found a valid neighbor terrain cell
				processed[n] = true
				next_boundary.append(n)
				
				# Calculate erosion factor based on distance
				# Closer to delta = stronger erosion
				# i=0 (immediate neighbor) -> 100% strength
				# i=radius (far neighbor) -> 0% strength
				var falloff = 1.0 - (float(i) / float(erosion_radius))
				cells_to_erode[n] = erosion_strength * falloff
		
		current_boundary = next_boundary

	# 2. APPLY EROSION
	for cell in cells_to_erode.keys():
		var drop = cells_to_erode[cell]
		var current_h = map_data[cell]
		
		# Apply the drop
		var new_h = current_h - drop
		
		# Clamp to ensure we don't accidentally dig a hole below sea level 
		# unless that is intended (creating swamp). 
		# Here we clamp to 0.05 (Marsh level) so it doesn't turn into deep ocean.
		if new_h < 0.05: new_h = 0.05
		
		map_data[cell] = new_h
