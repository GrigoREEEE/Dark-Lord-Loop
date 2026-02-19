extends Node

class_name Delta_old

func generate_delta(
	river: River, 
	ocean_mask: Dictionary,
	stream_config: Dictionary,
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
				sources, flow_dir, boundary_set, ocean_mask,
				"NATURAL", rng.randi()
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
	behavior: String,
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

# Naturalizes the elevation of islands formed inside the delta.
# - river: The river object containing segments.
# - delta_mask: The boolean mask defining the overall shape of the delta region.
# - water_height: The base height of the river (islands will rise from this level).
# - island_peak_height: How much higher the center of an island can get.
# - roughness: Magnitude of noise to apply to the terrain.
func naturalize_delta_islands(
	map_data: Dictionary, 
	river: River, 
	delta_mask: Dictionary,
	noise_seed: int,
	water_height: float = 0.07,
	island_peak_height: float = 0.15,
	roughness: float = 0.02
):
	if river.segments.is_empty(): return
	
	# 1. SETUP LOOKUPS
	# Convert the river water pixels into a fast lookup set
	var river_water_set = {}
	for cell in river.segments[-1]:
		river_water_set[cell] = true
		
	# 2. IDENTIFY ISLAND CELLS
	# An island cell is inside the Delta Mask but NOT in the River Water Set.
	var all_island_cells = {}
	for cell in delta_mask.keys():
		if delta_mask[cell] == true:
			if not river_water_set.has(cell):
				all_island_cells[cell] = true
	
	if all_island_cells.is_empty(): return

	# 3. CLUSTER INTO INDIVIDUAL ISLANDS
	# We separate the soup of pixels into distinct island arrays
	var islands: Array[Array] = _cluster_islands(all_island_cells)
	
	# 4. PROCESS EACH ISLAND
	var noise = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = 0.1
	
	for island in islands:
		# A. Generate Distance Field (Distance to nearest shore)
		# Returns Dictionary { cell: distance_int }
		var dist_field = _calculate_island_distance_field(island, river_water_set)
		
		# Find the "widest" point of this island to normalize height
		var max_dist = 1.0
		for d in dist_field.values():
			if d > max_dist: max_dist = float(d)
			
		# B. Apply Height
		for cell in island:
			var dist = float(dist_field[cell])
			
			# Normalize: 0.0 at shore, 1.0 at peak
			var shape_factor = dist / max_dist
			
			# Parabolic curve (makes islands look rounder/humped rather than pointy cones)
			# shape_factor = sqrt(shape_factor) 
			
			# Noise Variation
			var noise_val = noise.get_noise_2d(cell.x, cell.y) * roughness
			
			# Calculate final height
			# Base + (Peak * Shape) + Noise
			var new_height = water_height + (island_peak_height * shape_factor) + noise_val
			
			# Clamp to ensure it never sinks below water (unless you want marsh)
			new_height = max(new_height, water_height + 0.01)
			
			map_data[cell] = new_height


# --- HELPERS ---

# Groups connected cells into separate Arrays (Islands)
func _cluster_islands(all_cells_map: Dictionary) -> Array[Array]:
	var islands : Array[Array] = []
	var visited = {}
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	
	for start_cell in all_cells_map.keys():
		if visited.has(start_cell): continue
		
		# Start a new island
		var current_island: Array[Vector2] = []
		var queue = [start_cell]
		visited[start_cell] = true
		current_island.append(start_cell)
		
		var head = 0
		while head < queue.size():
			var cell = queue[head]
			head += 1
			
			for d in directions:
				var n = cell + d
				if all_cells_map.has(n) and not visited.has(n):
					visited[n] = true
					current_island.append(n)
					queue.append(n)
		
		islands.append(current_island)
		
	return islands

# Calculates how far each cell is from the water (shore).
# Uses a Breadth-First Search starting from the edges.
func _calculate_island_distance_field(island_cells: Array, water_set: Dictionary) -> Dictionary:
	var distances = {}
	var queue = []
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	
	# 1. Identify Shoreline Cells (Distance 1)
	# A cell is shoreline if it touches Water or "Empty Space" (outside delta)
	for cell in island_cells:
		distances[cell] = 9999 # Initialize with infinity
		var is_shore = false
		
		for d in directions:
			var n = cell + d
			# If neighbor is water OR not in our island group, we are an edge
			if water_set.has(n) or not cell in island_cells: 
				# (Note: simpler check is just: if neighbor not in island_cells)
				pass
				
			if not n in island_cells: # Simple definition of edge
				is_shore = true
				break
		
		if is_shore:
			distances[cell] = 1
			queue.append(cell)
			
	# 2. Propagate Distance Inwards
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		var current_dist = distances[current]
		
		for d in directions:
			var n = current + d
			
			# Only process if it's part of this island
			if n in island_cells:
				if distances[n] > current_dist + 1:
					distances[n] = current_dist + 1
					queue.append(n)
					
	return distances
