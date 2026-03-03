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
	var delta_region: Region = river.segments[last_idx]
	var upstream_region: Region = river.segments[last_idx - 1]
	
	# 1. SETUP SANDBOX
	var boundary_set = {}
	for cell in delta_region.points: 
		boundary_set[cell] = true
		
	# Wipe clean the Region's data
	delta_region.points.clear() 
	delta_region.size = 0
	
	# 2. FIND SOURCES & FLOW
	var sources = []
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	
	# Look at the upstream Region's points to find where water enters the delta sandbox
	for cell in upstream_region.points:
		for d in directions:
			if boundary_set.has(cell + d):
				sources.append(cell); break
				
	if sources.is_empty(): 
		sources.append(upstream_region.points.back())
	
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
	rng.seed = noise_seed # Tied to your world seed for consistency
	
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

	# Commit back to the Delta Region object
	delta_region.points.append_array(final_delta_set.keys())
	delta_region.size = delta_region.points.size()


# Generates a stream that flows until it hits the ocean.
# - Ignores other streams (can cross over).
# - Strictly constrained to 'boundary' set.
# - Uses momentum + noise for natural curves.
func _generate_smart_stream(
	sources: Array, # Array of Vector2
	flow_dir: Vector2, 
	boundary: Dictionary, 
	ocean_mask: Dictionary,
	noise_seed: int = 0
) -> Array[Vector2]:
	
	var rng = RandomNumberGenerator.new()
	if noise_seed != 0: 
		rng.seed = noise_seed
	else: 
		rng.randomize()
	
	# SETUP NOISE
	var noise = FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.04 # Low frequency for wide, lazy meanders
	
	# 1. INITIALIZATION
	# Safely cast the starting node to Vector2
	var start_node: Vector2 = sources[rng.randi() % sources.size()]
	var pos_f: Vector2 = start_node 
	var velocity: Vector2 = flow_dir.normalized()
	
	# Config
	var wander_strength: float = 1.0 
	var gravity: float = 0.08  # Very low gravity = allows crossing sideways
	
	# 2. PHYSICS LOOP
	var path: Array[Vector2] = [start_node]
	var visited_in_this_path = {start_node: true} 
	
	var steps: int = 0
	var max_steps: int = boundary.size() * 4 # Allow long, winding paths
	
	while steps < max_steps:
		steps += 1
		
		# A. STEERING
		# Sample noise (-1 to 1)
		var n_val = noise.get_noise_1d(steps * 4.0) 
		var steer_angle = n_val * wander_strength
		
		# Rotate velocity
		velocity = velocity.rotated(steer_angle)
		
		# Apply weak gravity (pull towards ocean/main flow)
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
			velocity = velocity.lerp(flow_dir, 0.6).normalized()
			
			# Nudge position slightly back to safe ground to prevent sticking
			# Using the last valid integer position ensures we don't float out of bounds
			pos_f = pos_f.lerp(path.back(), 0.5)
			continue
			
		# 3. SELF-INTERSECTION (Loop prevention)
		if visited_in_this_path.has(next_cell):
			# Prevent stalling on the exact same pixel
			if next_cell == path.back():
				# Give it a tiny nudge forward along the flow direction to break the stall
				pos_f += flow_dir * 0.5
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
	var edge_cells: Array[Vector2] = []
	var directions: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	
	# 1. Find all cells that are on the edge boundary
	for cell: Vector2 in boundary_set:
		var is_edge: bool = false
		for d in directions:
			# If a neighbor is missing from the boundary_set, this cell touches the outside.
			if not boundary_set.has(cell + d):
				is_edge = true
				break
				
		if is_edge:
			edge_cells.append(cell)
			
	if edge_cells.is_empty(): 
		return [[], []]
	
	# 2. Calculate Center Line (to split Left vs Right)
	var avg_source := Vector2.ZERO
	for s: Vector2 in sources: 
		avg_source += s
		
	# Cast to float to prevent integer division truncation
	avg_source /= float(sources.size()) 
	
	# Create a vector exactly 90 degrees to the flow direction
	var right_vec := flow_dir.rotated(PI / 2.0)
	
	var left_path: Array[Vector2] = []
	var right_path: Array[Vector2] = []
	
	# 3. Split edges based on which side of the center line they are on
	for cell: Vector2 in edge_cells:
		# Vector pointing from the delta's source center to this specific edge cell
		var to_cell := cell - avg_source
		
		# The dot product tells us how much 'to_cell' aligns with 'right_vec'.
		# Negative = Left side, Positive = Right side.
		var side_dot := to_cell.dot(right_vec)
		
		if side_dot < 0.0:
			left_path.append(cell)
		else:
			right_path.append(cell)
			
	# 4. Sort paths upstream-to-downstream for clean rasterization
	# By dotting the position against the flow direction, we measure how "far down" the river it is.
	var sort_upstream_downstream = func(a: Vector2, b: Vector2) -> bool: 
		return a.dot(flow_dir) < b.dot(flow_dir)
		
	left_path.sort_custom(sort_upstream_downstream)
	right_path.sort_custom(sort_upstream_downstream)
	
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
# - spread_radius: Expands the mask outward by N cells.
# Returns an empty dictionary if the river has no segments.
func create_delta_mask2(river: River, spread_radius: int = 0) -> Dictionary[Vector2, bool]:
	var mask: Dictionary[Vector2, bool] = {}
	
	if river.segments.is_empty():
		return mask
		
	# The delta is defined as the very last Region in the river
	var delta_region: Region = river.segments.back()
	var current_boundary: Array[Vector2] = []
	
	# 1. Populate the initial mask with the exact delta cells
	for cell: Vector2 in delta_region.points:
		mask[cell] = true
		current_boundary.append(cell)
		
	# 2. Spread the mask outward by N cells (Dilation)
	if spread_radius > 0:
		var directions: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
		
		# Expand layer by layer
		for i in range(spread_radius):
			var next_boundary: Array[Vector2] = []
			
			for cell: Vector2 in current_boundary:
				for d in directions:
					var neighbor: Vector2 = cell + d
					
					# If it's not already in the mask, add it and mark it for the next expansion layer
					if not mask.has(neighbor):
						mask[neighbor] = true
						next_boundary.append(neighbor)
						
			# Move to the newly added outer edge for the next loop
			current_boundary = next_boundary
		
	return mask

# Identifies islands within the delta and sculpts their elevation.
# - Islands are defined as (Delta Mask - River Water).
# - Elevation is calculated based on distance from the water edge.
# - Height ranges from 0.12 (edge) to 0.25 (center).
func naturalize_delta_islands(map_data: Dictionary, river: River, delta_mask: Dictionary):
	if river.segments.is_empty(): return

	# 1. IDENTIFY "RAW" ISLAND CELLS
	# An island cell is inside the delta mask but NOT in the river water.
	var delta_water_region: Region = river.segments.back()
	var water_set: Dictionary[Vector2, bool] = {}
	
	for cell: Vector2 in delta_water_region.points:
		water_set[cell] = true
		
	var all_island_cells: Dictionary[Vector2, bool] = {}
	for cell: Vector2 in delta_mask.keys():
		if delta_mask[cell] == true and not water_set.has(cell):
			all_island_cells[cell] = true

	if all_island_cells.is_empty():
		return # No islands found

	# 2. GROUP INTO DISTINCT ISLANDS
	# We use flood-fill to find connected clumps of land.
	var islands: Array[Array] = []
	var visited: Dictionary[Vector2, bool] = {}
	var directions: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	
	for cell: Vector2 in all_island_cells.keys():
		if visited.has(cell): continue
		
		# Start a new island
		var current_island: Array[Vector2] = []
		var stack: Array[Vector2] = [cell]
		visited[cell] = true
		
		while not stack.is_empty():
			var current: Vector2 = stack.pop_back()
			current_island.append(current)
			
			for d in directions:
				var n: Vector2 = current + d
				# If neighbor is valid land and not visited
				if all_island_cells.has(n) and not visited.has(n):
					visited[n] = true
					stack.append(n)
		
		islands.append(current_island)

	# 3. SCULPT EACH ISLAND
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for island: Array in islands:
		# A. Compute Distance Field (Manhattan distance from water)
		# We identify "edge" cells first (those touching water or empty space)
		var distances: Dictionary[Vector2, int] = {}
		var queue: Array[Vector2] = []
		
		# Initialize edges
		for cell: Vector2 in island:
			var is_edge: bool = false
			
			for d in directions:
				var n: Vector2 = cell + d
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
		var max_dist: int = 0
		var head: int = 0
		while head < queue.size():
			var current: Vector2 = queue[head]
			head += 1
			var d_val: int = distances[current]
			
			if d_val > max_dist: max_dist = d_val
			
			for dir in directions:
				var n: Vector2 = current + dir
				# If it's part of this island and hasn't been distance-mapped yet
				if distances.has(n) and distances[n] == -1:
					distances[n] = d_val + 1
					queue.append(n)
		
		# B. Apply Heights
		# Range: 0.12 (Edge) -> 0.25 (Center)
		# Formula: 0.12 + (0.13 * (dist / max_dist))
		for cell: Vector2 in island:
			var dist: int = distances[cell]
			
			var height_factor: float = 0.0
			if max_dist > 0:
				height_factor = float(dist) / float(max_dist)
			
			# Lerp height
			var base_height: float = lerp(0.12, 0.25, height_factor)
			
			# Add subtle noise for roughness (range -0.005 to +0.005)
			var noise: float = rng.randf_range(-0.005, 0.005)
			
			map_data[cell] = base_height + noise

# Erodes the terrain adjacent to the delta to create an uneven, natural transition.
# - erosion_radius: How many pixels out from the delta to affect.
# - erosion_strength: How much to subtract from the height (0.05 is subtle, 0.1 is strong).
# - noise_seed: Seed for the erosion variation (pass your world seed here).
# - min_height: The absolute lowest the erosion is allowed to dig (unless already lower).
func erode_delta_edges(
	map_data: Dictionary, 
	delta_mask: Dictionary,
	noise_seed: int = 0,
	erosion_radius: int = 4, 
	erosion_strength: float = 0.2,
	min_height: float = 0.15
):
	if delta_mask.is_empty(): return

	# Setup Noise for organic unevenness
	var noise = FastNoiseLite.new()
	noise.seed = noise_seed if noise_seed != 0 else randi()
	# Higher frequency = more jagged banks. Lower = smoother, wider variance.
	noise.frequency = 0.15 

	# 1. IDENTIFY BORDER CELLS
	var cells_to_erode: Dictionary[Vector2, float] = {}
	
	var current_boundary: Array[Vector2] = []
	current_boundary.assign(delta_mask.keys())
	
	var processed: Dictionary = delta_mask.duplicate()
	var directions: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	
	# Iterative expansion (Breadth-First Search)
	for i in range(erosion_radius):
		var next_boundary: Array[Vector2] = []
		
		# Calculate the base drop for this "ring" of distance
		var falloff: float = 1.0 - (float(i) / float(erosion_radius))
		var base_drop: float = erosion_strength * falloff
		
		for cell: Vector2 in current_boundary:
			for d in directions:
				var n: Vector2 = cell + d
				
				if not map_data.has(n): continue
				if processed.has(n): continue
				
				# Found a valid neighbor terrain cell
				processed[n] = true
				next_boundary.append(n)
				
				# --- UNEVEN NOISE MODULATION ---
				var raw_noise: float = (noise.get_noise_2dv(n) + 1.0) / 2.0
				var uneven_multiplier: float = lerp(0.2, 1.0, raw_noise)
				
				cells_to_erode[n] = base_drop * uneven_multiplier
		
		current_boundary = next_boundary

	# 2. APPLY EROSION
	for cell: Vector2 in cells_to_erode.keys():
		var drop: float = cells_to_erode[cell]
		var current_h: float = map_data[cell]
		
		# Apply the drop
		var new_h: float = current_h - drop
		
		# Determine the absolute floor for this specific cell.
		# If it's already below min_height, its current height is the absolute floor.
		var cell_floor: float = min(current_h, min_height)
		
		# Clamp to ensure we don't accidentally dig a hole below our dynamic floor
		if new_h < cell_floor: 
			new_h = cell_floor
		
		map_data[cell] = new_h
