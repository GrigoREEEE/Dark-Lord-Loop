extends Node
class_name Delta_Hex_Sandbox

func generate_delta(
	river: River, 
	world_data: World_Data,
	boundary_width: int = 2 # In hexes (radius)
):
	if river.segments.size() < 2: return

	var last_idx = river.segments.size() - 1
	var delta_segment = river.segments[last_idx]
	var upstream_segment = river.segments[last_idx - 1]
	
	# 1. SETUP SANDBOX
	var boundary_set = {}
	for cell in delta_segment.points: 
		boundary_set[cell] = true
		
	delta_segment.points.clear() # Wipe clean to prepare for carving
	
	# 2. FIND SOURCES & FLOW (Hex Adapted)
	var sources = []
	for cell in upstream_segment.points:
		var neighbors = global._get_hex_neighbors(cell)
		for n in neighbors:
			if boundary_set.has(n):
				sources.append(cell)
				break
				
	if sources.is_empty(): 
		sources.append(upstream_segment.points.back())
	
	# Calculate physical flow direction
	var avg_source_phys = Vector2.ZERO
	for s in sources: 
		avg_source_phys += global._get_hex_physical_pos(s)
	avg_source_phys /= sources.size()
	
	var avg_delta_phys = Vector2.ZERO
	var c = 0
	for b in boundary_set: 
		if c % 10 == 0: 
			avg_delta_phys += global._get_hex_physical_pos(b)
		c += 1
	if c > 0: 
		avg_delta_phys /= (float(c) / 10.0)
	
	var flow_dir = (avg_delta_phys - avg_source_phys).normalized()
	if flow_dir == Vector2.ZERO: 
		flow_dir = Vector2(0, 1) # Default down
	
	var generated_streams = []

	# --- 3. GENERATE BOUNDARY STREAMS ---
	var edges = _extract_delta_edge_paths(boundary_set, sources, flow_dir)
	var left_edge_path = edges[0]
	var right_edge_path = edges[1]
	
	if not left_edge_path.is_empty():
		generated_streams.append({ "path": left_edge_path, "width": boundary_width })
	if not right_edge_path.is_empty():
		generated_streams.append({ "path": right_edge_path, "width": boundary_width })
	
	# --- 4. GENERATE INTERNAL STREAMS (Hex Physics Agent) ---
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for width_key in world_data.delta_streams.keys():
		var count = world_data.delta_streams[width_key]
		for i in range(count):
			var path: Array[Vector2] = _generate_smart_stream(
				sources, flow_dir, boundary_set, world_data.mask_data["ocean"], world_data.noise_seed
			)
			generated_streams.append({ "path": path, "width": width_key })

	# --- 5. RASTERIZE & THICKEN (Hex Adapted) ---
	var final_delta_set = {}
	
	for stream in generated_streams:
		var w = stream.width
		var path = stream.path
		if path.is_empty(): continue
		
		for cell in path:
			final_delta_set[cell] = true
			
			# Hex Thicken (BFS Expansion)
			if w > 1:
				var queue = [{"cell": cell, "depth": 0}]
				var head = 0
				while head < queue.size():
					var curr = queue[head]
					head += 1
					
					if curr.depth < (w - 1):
						var neighbors = global._get_hex_neighbors(curr.cell)
						for n in neighbors:
							if boundary_set.has(n) and not final_delta_set.has(n):
								final_delta_set[n] = true
								queue.append({"cell": n, "depth": curr.depth + 1})

	# Commit to river segment
	delta_segment.points.append_array(final_delta_set.keys())
	delta_segment.size = delta_segment.points.size()


# Hex-native physics agent. Moves a physical cursor and snaps to the nearest valid hex.
func _generate_smart_stream(
	sources: Array, 
	flow_dir: Vector2, 
	boundary: Dictionary, 
	ocean_mask: Dictionary,
	noise_seed: int
) -> Array[Vector2]:
	
	var rng = RandomNumberGenerator.new()
	rng.seed = noise_seed
	
	var noise = FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.04 
	
	# 1. INITIALIZATION
	var start_node = sources[rng.randi() % sources.size()]
	var current_grid = start_node
	var current_phys = global._get_hex_physical_pos(start_node)
	var velocity = flow_dir.normalized()
	
	var wander_strength = 1.0 
	var gravity = 0.08  
	var hex_diameter = sqrt(3.0)
	
	var path: Array[Vector2] = [start_node]
	var visited_in_this_path = {start_node: true} 
	var steps = 0
	var max_steps = boundary.size() * 4 
	
	while steps < max_steps:
		steps += 1
		
		# A. STEERING
		var n_val = noise.get_noise_1d(steps * 4.0) 
		var steer_angle = n_val * wander_strength
		
		velocity = velocity.rotated(steer_angle)
		velocity = velocity.lerp(flow_dir, gravity).normalized()
		
		# B. MOVE PHYSICAL CURSOR
		current_phys += (velocity * hex_diameter * 0.7) 
		
		# C. FIND CLOSEST HEX NEIGHBOR
		var neighbors = global._get_hex_neighbors(current_grid)
		var best_neighbor = current_grid
		var best_dist = 999999.0
		
		for n in neighbors:
			var n_phys = global._get_hex_physical_pos(n)
			var d = current_phys.distance_to(n_phys)
			if d < best_dist:
				best_dist = d
				best_neighbor = n
				
		var next_cell = best_neighbor
		
		# D. CHECKS
		if ocean_mask.get(next_cell, false) == true:
			path.append(next_cell)
			break
			
		# Hard Bounce against the boundary wall
		if not boundary.has(next_cell):
			velocity = velocity.lerp(flow_dir, 0.5).normalized()
			var safe_phys = global._get_hex_physical_pos(path.back())
			current_phys = current_phys.lerp(safe_phys, 0.5)
			continue
			
		# Self-Intersection Allowance
		if visited_in_this_path.has(next_cell):
			if next_cell == path.back():
				continue # Don't stall on the exact same tile
		
		# E. COMMIT
		if next_cell != path.back():
			path.append(next_cell)
			visited_in_this_path[next_cell] = true
			current_grid = next_cell
			
		# Tether to prevent desync
		var tether_phys = global._get_hex_physical_pos(current_grid)
		current_phys = current_phys.lerp(tether_phys, 0.5)
		
	return path


func _extract_delta_edge_paths(boundary_set: Dictionary, sources: Array, flow_dir: Vector2) -> Array:
	var edge_cells = []
	
	# 1. Find all outer edge cells (Hex checking)
	for cell in boundary_set:
		var is_edge = false
		var neighbors = global._get_hex_neighbors(cell)
		for n in neighbors:
			if not boundary_set.has(n):
				is_edge = true
				break
		if is_edge:
			edge_cells.append(cell)
			
	if edge_cells.is_empty(): return [[], []]
	
	# 2. Split using physical coordinates
	var avg_source_phys = Vector2.ZERO
	for s in sources: 
		avg_source_phys += global._get_hex_physical_pos(s)
	avg_source_phys /= sources.size()
	
	var right_vec = Vector2(-flow_dir.y, flow_dir.x)
	var left_path = []
	var right_path = []
	
	for cell in edge_cells:
		var cell_phys = global._get_hex_physical_pos(cell)
		var to_cell = cell_phys - avg_source_phys
		
		if to_cell.dot(right_vec) < 0:
			left_path.append(cell)
		else:
			right_path.append(cell)
			
	var sort_func = func(a, b):
		var a_p = global._get_hex_physical_pos(a)
		var b_p = global._get_hex_physical_pos(b)
		return a_p.dot(flow_dir) < b_p.dot(flow_dir)
		
	left_path.sort_custom(sort_func)
	right_path.sort_custom(sort_func)
	
	return [left_path, right_path]


# --- HEX ISLAND NATURALIZER ---

func naturalize_delta_islands(
	world_data: World_Data,
	river: River, 
	water_height: float = 0.05,
	island_peak_height: float = 0.10,
	roughness: float = 0.02
):
	var delta_mask: Dictionary = world_data.mask_data["delta"]
	if river.segments.is_empty(): return
	
	var river_water_set = {}
	for cell in river.segments[-1].points:
		river_water_set[cell] = true
		
	var all_island_cells = {}
	for cell in delta_mask.keys():
		if delta_mask[cell] == true and not river_water_set.has(cell):
			all_island_cells[cell] = true
	
	if all_island_cells.is_empty(): return

	var islands: Array[Array] = _cluster_islands_hex(all_island_cells)
	
	var noise = FastNoiseLite.new()
	noise.seed = world_data.noise_seed
	noise.frequency = 0.1
	
	for island in islands:
		var dist_field = _calculate_island_distance_field_hex(island, river_water_set)
		
		var max_dist = 1.0
		for d in dist_field.values():
			if d > max_dist: max_dist = float(d)
			
		for cell in island:
			var dist = float(dist_field[cell])
			var shape_factor = dist / max_dist
			
			# Make the islands humped
			shape_factor = sqrt(shape_factor)
			
			var phys_pos = global._get_hex_physical_pos(cell)
			var noise_val = noise.get_noise_2d(phys_pos.x, phys_pos.y) * roughness
			
			var new_height = water_height + (island_peak_height * shape_factor) + noise_val
			new_height = max(new_height, water_height + 0.01)
			
			world_data.map_data["terrain"][cell] = new_height


func _cluster_islands_hex(all_cells_map: Dictionary) -> Array[Array]:
	var islands : Array[Array] = []
	var visited = {}
	
	for start_cell in all_cells_map.keys():
		if visited.has(start_cell): continue
		
		var current_island: Array[Vector2] = []
		var queue = [start_cell]
		visited[start_cell] = true
		current_island.append(start_cell)
		
		var head = 0
		while head < queue.size():
			var cell = queue[head]
			head += 1
			
			var neighbors = global._get_hex_neighbors(cell)
			for n in neighbors:
				if all_cells_map.has(n) and not visited.has(n):
					visited[n] = true
					current_island.append(n)
					queue.append(n)
		
		islands.append(current_island)
		
	return islands


func _calculate_island_distance_field_hex(island_cells: Array, water_set: Dictionary) -> Dictionary:
	var distances = {}
	var queue = []
	
	# 1. Shoreline Cells (Hex Check)
	for cell in island_cells:
		distances[cell] = 9999
		var is_shore = false
		
		var neighbors = global._get_hex_neighbors(cell)
		for n in neighbors:
			if not n in island_cells: 
				is_shore = true
				break
		
		if is_shore:
			distances[cell] = 1
			queue.append(cell)
			
	# 2. Propagate Inwards
	var head = 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		var current_dist = distances[current]
		
		var neighbors = global._get_hex_neighbors(current)
		for n in neighbors:
			if n in island_cells:
				if distances[n] > current_dist + 1:
					distances[n] = current_dist + 1
					queue.append(n)
					
	return distances

# Erodes the terrain adjacent to the delta to create an uneven, natural transition.
# - map_data: The terrain height dictionary.
# - delta_mask: A Dictionary where keys are every cell inside the delta region.
# - noise_seed: Seed for the erosion variation (pass your world seed here).
# - erosion_radius: How many hexes out from the delta to affect.
# - erosion_strength: How much to subtract from the height (0.05 is subtle, 0.1 is strong).
# - min_height: The absolute lowest the erosion is allowed to dig (unless already lower).
func erode_delta_edges_hex(
	world_data: World_Data,
	erosion_radius: int = 5, 
	erosion_strength: float = 0.9,
	min_height: float = 0.12
	):
	var delta_mask: Dictionary = world_data.mask_data["delta"]
	var noise_seed: int = world_data.noise_seed
	if delta_mask.is_empty(): return

	# Setup Noise for organic unevenness
	var noise = FastNoiseLite.new()
	noise.seed = noise_seed if noise_seed != 0 else randi()
	noise.frequency = 0.15 

	# 1. IDENTIFY BORDER CELLS
	var cells_to_erode: Dictionary[Vector2, float] = {}
	
	var current_boundary: Array[Vector2] = []
	current_boundary.assign(delta_mask.keys())
	
	var processed: Dictionary = delta_mask.duplicate()
	
	# Iterative expansion (Breadth-First Search) using Hex Rings
	for i in range(erosion_radius):
		var next_boundary: Array[Vector2] = []
		
		# Calculate the base drop for this "ring" of distance
		var falloff: float = 1.0 - (float(i) / float(erosion_radius))
		var base_drop: float = erosion_strength * falloff
		
		for cell: Vector2 in current_boundary:
			
			# --- HEX MATH ---
			# Replaced 4-way directions with true 6-way hex neighbors
			var neighbors = global._get_hex_neighbors(cell)
			
			for n in neighbors:
				if not world_data.map_data["terrain"].has(n): continue
				if processed.has(n): continue
				
				# Found a valid neighbor terrain cell
				processed[n] = true
				next_boundary.append(n)
				
				# --- UNEVEN NOISE MODULATION ---
				# Calculate noise based on physical hex position to avoid staggered stretching
				var phys_pos = global._get_hex_physical_pos(n)
				var raw_noise: float = (noise.get_noise_2dv(phys_pos) + 1.0) / 2.0
				var uneven_multiplier: float = lerp(0.2, 1.0, raw_noise)
				
				cells_to_erode[n] = base_drop * uneven_multiplier
		
		current_boundary = next_boundary

	# 2. APPLY EROSION
	for cell: Vector2 in cells_to_erode.keys():
		var drop: float = cells_to_erode[cell]
		var current_h: float = world_data.map_data["terrain"][cell]
		
		# Apply the drop
		var new_h: float = current_h - drop
		
		# Determine the absolute floor for this specific cell.
		var cell_floor: float = min(current_h, min_height)
		
		# Clamp to ensure we don't accidentally dig a hole below our dynamic floor
		if new_h < cell_floor: 
			new_h = cell_floor
		
		world_data.map_data["terrain"][cell] = new_h
		
# Creates a boolean mask (Dictionary) where every cell in the delta is TRUE.
# - spread_radius: Expands the mask outward by N hexes.
# Returns an empty dictionary if the river has no segments.
func create_delta_mask(
	world_data: World_Data,
	river: River, 
	spread_radius: int = 0
) -> void:
	var mask: Dictionary[Vector2, bool] = {}
	
	if river.segments.is_empty():
		world_data.mask_data["delta"] = mask
		
	# The delta is defined as the very last Region in the river
	var delta_region: Region = river.segments.back()
	var current_boundary: Array[Vector2] = []
	
	# 1. Populate the initial mask with the exact delta cells
	for cell: Vector2 in delta_region.points:
		mask[cell] = true
		current_boundary.append(cell)
		
	# 2. Spread the mask outward by N cells (Dilation)
	if spread_radius > 0:
		# Expand layer by layer
		for i in range(spread_radius):
			var next_boundary: Array[Vector2] = []
			
			for cell: Vector2 in current_boundary:
				
				# --- HEX FIX: Check all 6 true neighbors ---
				var neighbors = global._get_hex_neighbors(cell)
				
				for neighbor in neighbors:
					# If it's not already in the mask, add it and mark it for the next expansion layer
					if not mask.has(neighbor):
						mask[neighbor] = true
						next_boundary.append(neighbor)
						
			# Move to the newly added outer edge for the next loop
			current_boundary = next_boundary
		
	world_data.mask_data["delta"] = mask
