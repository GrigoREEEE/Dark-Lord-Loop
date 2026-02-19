extends Node

class_name River_Widener_old_v2

# Widens the river with special "Lowland Discounts".
# - beach_mask: Used to prevent mid-river segments from breaching the coastline.
func widen_river_wave_based(
	map_data: Dictionary, 
	river: River, 
	ocean_mask: Dictionary, 
	beach_mask: Dictionary,
	mouth_segments : int,
	base_flow_gain: float, 
	flow_increment: float, 
	flood_cost_base: float = 1.0, 
	flood_climb_cost: float = 5.0,
	flood_distance_cost: float = 0.1,
	climb_tolerance: float = 0.01
):
	
	river.segment_flow.clear()
	
	# Cache path for fast core checks
	var path_set = {}
	for pos in river.river_path:
		path_set[pos] = true

	var river_cells_set = {}
	for pos in river.river_path:
		river_cells_set[pos] = true
	
	var directions = [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
	
	# Pre-calculate the "Safe Zone" threshold
	# Only segments with index >= start_of_mouth can touch the beach
	var start_of_mouth = max(0, river.segments.size() - mouth_segments)
	#var segments_to_expand = max(0, river.segments.size() - 3)
	
	for i in range(start_of_mouth):
		var segment = river.segments[i]
		
		# Identify Core Cells
		var core_cells: Array[Vector2] = []
		for cell in segment:
			if path_set.has(cell):
				core_cells.append(cell)
		
		var current_budget = base_flow_gain + (float(i) * flow_increment)
		river.segment_flow.append(current_budget)
		
		var river_bed_height = 0.0
		if not core_cells.is_empty():
			river_bed_height = map_data[core_cells[0]]
		elif not segment.is_empty():
			river_bed_height = map_data[segment[0]]
		
		# --- OUTER LOOP: WAVES ---
		while current_budget > 0:
			var flooded_count_this_wave = 0
			var candidates = []
			var candidate_set = {} 
			
			for cell in segment:
				for d in directions:
					var neighbor = cell + d
					
					if not map_data.has(neighbor): continue
					if river_cells_set.has(neighbor): continue
					if candidate_set.has(neighbor): continue
					if ocean_mask.get(neighbor, false) == true: continue
					
					# --- NEW: BEACH CONTAINMENT CHECK ---
					# If this tile is a beach, ONLY allow it if we are at the river mouth.
					if beach_mask.get(neighbor, false) == true:
						if i < start_of_mouth:
							continue # Stop! Don't breach the coast mid-stream.
					
					# --- 3. CALCULATE COSTS ---
					var target_height = map_data[neighbor]
					
					# --- LOWLAND DISCOUNT LOGIC ---
					var effective_base_cost = flood_cost_base
					var effective_dist_cost = flood_distance_cost
					
					if (target_height >= 0.07) and (target_height < 0.12):
						effective_base_cost *= 0.8 
						effective_dist_cost *= 0.8
					
					if (target_height < 0.07):
						effective_base_cost = 0
						effective_dist_cost = 0
					
					var cost = effective_base_cost
					
					# A. CLIMB COST
					var height_diff = target_height - river_bed_height
					if height_diff > climb_tolerance:
						var excess = height_diff - climb_tolerance
						cost += excess * flood_climb_cost
					
					# B. DISTANCE COST
					var min_dist = 999.0
					for core in core_cells:
						var d_val = core.distance_to(neighbor)
						if d_val < min_dist: min_dist = d_val
					
					cost += min_dist * effective_dist_cost
					
					candidates.append({
						"pos": neighbor,
						"cost": cost
					})
					candidate_set[neighbor] = true
			
			if candidates.is_empty():
				break
			
			# 4. START FLOODING
			candidates.sort_custom(func(a, b): return a.cost < b.cost)
			
			var limit = min(candidates.size(), 5)
			
			for k in range(limit):
				var best = candidates[k]
				
				if current_budget >= best.cost:
					current_budget -= best.cost
					
					segment.append(best.pos)
					river_cells_set[best.pos] = true
					flooded_count_this_wave += 1
				else:
					current_budget = -1.0 
					break
			
			if current_budget <= 0 or flooded_count_this_wave == 0:
				break
				
# Combines the last 'n' segments of the river into a single "Delta Segment".
func merge_mouth_segments(river: River, n_segments_to_merge: int):
	if river.segments.size() < n_segments_to_merge + 1:
		return # River too short to make a delta
		
	var delta_cells: Array[Vector2] = []
	
	# 1. Collect all cells from the last N segments
	# We iterate backwards to pop them off easily
	for k in range(n_segments_to_merge):
		var segment = river.segments.pop_back()
		delta_cells.append_array(segment)
		
	# 2. Add the combined cluster back as a single segment
	# (We reverse the collection order if strictly needed, but for a set of cells it implies no order)
	river.segments.append(delta_cells)
	
	print("Delta created. River now has ", river.segments.size(), " segments.")

# Generates a "Sculpted" Delta:
# 1. Creates a massive cone of water.
# 2. Carves out "islands" from the center of the water, creating a braided look.
func generate_sculpted_delta(
	map_data: Dictionary, 
	river: River, 
	ocean_mask: Dictionary,
	cone_length: int = 200,       # How far the delta reaches towards the sea
	cone_spread: float = 1.5,    # How fast it widens (Higher = wider fan)
	num_islands: int = 10,       # How many sandbars to attempt creating
	island_size_min: int = 2,
	island_size_max: int = 5
):
	if river.segments.size() < 2: return

	# --- SETUP ---
	# 1. Identify the Delta Segment (The last one)
	var delta_segment_index = river.segments.size() - 1
	var delta_segment = river.segments[delta_segment_index]
	
	# 2. Determine "Start Width" from the previous segment
	# We count pixels in the previous segment to estimate its flow width
	var prev_segment = river.segments[delta_segment_index - 1]
	# (Approximate width by dividing segment area by length, or just heuristic)
	# A safe heuristic is ~5-8 pixels for a widened river.
	var start_width = max(4.0, sqrt(prev_segment.size())) 
	
	# 3. Calculate Direction
	# Vector from start of delta to end of original path
	var root = delta_segment[0]
	var river_end = river.river_path.back()
	var main_dir = (river_end - root).normalized()
	if main_dir == Vector2.ZERO: main_dir = Vector2(0, 1) # Default South
	var perp_dir = Vector2(-main_dir.y, main_dir.x)

	# Track all delta cells for fast lookups
	var delta_set = {}
	for cell in delta_segment: delta_set[cell] = true

	# =========================================================
	# STEP 1: CONE FLOODING
	# We walk down the "spine" and cast wide rays to fill the fan.
	# =========================================================
	
	for d in range(cone_length):
		# Move forward along the spine
		var spine_pos = root + (main_dir * float(d)).round()
		
		# Calculate width at this distance
		# It starts at 'start_width' and grows by 'cone_spread' every step
		var current_width = start_width + (float(d) * cone_spread)
		var radius = int(ceil(current_width / 2.0))
		
		# Scan Left and Right
		for sign in [1.0, -1.0]:
			var scan_vec = perp_dir * sign
			
			for r in range(radius):
				var offset = scan_vec * float(r)
				var target = (spine_pos + offset).round()
				
				# BOUNDARY CHECKS
				if not map_data.has(target): continue
				
				# STOP AT OCEAN
				# "Reach the ocean without spilling into it"
				# If we hit actual ocean water, we stop this specific ray.
				if ocean_mask.get(target, false) == true: 
					break
				
				# Add to Delta
				if not delta_set.has(target):
					delta_segment.append(target)
					delta_set[target] = true
	
	# =========================================================
	# STEP 2 & 3: SCULPTING ISLANDS (Subtractive)
	# We pick random spots and "erase" them to create sandbars.
	# =========================================================
	
	var islands_created = 0
	var attempts = 0
	var max_attempts = num_islands * 5 # Safety break
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	while islands_created < num_islands and attempts < max_attempts:
		attempts += 1
		
		# A. Pick a random point in the delta
		if delta_segment.is_empty(): break
		var rand_index = rng.randi() % delta_segment.size()
		var start_cell = delta_segment[rand_index]
		
		# B. Check Validity (The "Bank Safety" Rule)
		# "Not adjacent to a cell that is not in the river"
		# This means ALL neighbors must be WATER.
		if not _is_surrounded_by_water(start_cell, delta_set):
			continue
			
		# C. Carve the Island
		var island_cells = [start_cell]
		var size = rng.randi_range(island_size_min, island_size_max)
		
		# Grow the island (N-M adjacent points)
		var current_island_head = start_cell
		
		for k in range(size):
			# Try to find a valid neighbor to erase
			var neighbors = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
			neighbors.shuffle()
			
			for n_dir in neighbors:
				var n_cell = current_island_head + n_dir
				
				if delta_set.has(n_cell) and _is_surrounded_by_water(n_cell, delta_set):
					island_cells.append(n_cell)
					current_island_head = n_cell # Move head
					break
		
		# D. Commit Erasure
		# We effectively "restore" the land by removing these pixels from the river segment
		for cell in island_cells:
			if delta_set.has(cell):
				delta_set.erase(cell)
				delta_segment.erase(cell) # Note: Array.erase is O(N), slow for huge arrays but fine here
				
				# Also remove from river path if it happened to hit the center line
				# (Optional: keeps the visualizer cleaner)
				if river.river_path.has(cell):
					river.river_path.erase(cell)
					
		islands_created += 1

# Helper for the safety check
func _is_surrounded_by_water(pos: Vector2, river_set: Dictionary) -> bool:
	# Check all 8 neighbors (including diagonals)
	for x in range(-1, 2):
		for y in range(-1, 2):
			if x == 0 and y == 0: continue
			
			var neighbor = pos + Vector2(x, y)
			
			# If a neighbor is NOT in the river set, it is Land/Bank.
			# We cannot erase 'pos' because it touches land.
			if not river_set.has(neighbor):
				return false
	return true

## Widens the river using a Wave approach with DISTANCE PENALTY.
## - flood_distance_cost: Extra cost per unit of distance from the central river path.
#func widen_river_wave_based(
	#map_data: Dictionary, 
	#river: River, 
	#ocean_mask: Dictionary, 
	#base_flow_gain: float, 
	#flow_increment: float, 
	#flood_cost_base: float = 1.0, 
	#flood_climb_cost: float = 5.0,
	#flood_distance_cost: float = 0.05, # NEW: Penalty for distance
	#climb_tolerance: float = 0.01
#):
	#
	#river.segment_flow.clear()
	#
	## 1. OPTIMIZATION: Cache the river path for fast "Is this core?" checks
	#var path_set = {}
	#for pos in river.river_path:
		#path_set[pos] = true
#
	## Global set to ensure segments don't steal each other's cells
	#var river_cells_set = {}
	#for pos in river.river_path:
		#river_cells_set[pos] = true
	#
	#var directions = [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
	#
	## --- ITERATE SEGMENTS ---
	#for i in range(river.segments.size()):
		#var segment = river.segments[i]
		#
		## 2. IDENTIFY CORE CELLS
		## We need to know which cells in this segment are the "Center" to calculate distance.
		#var core_cells: Array[Vector2] = []
		#for cell in segment:
			#if path_set.has(cell):
				#core_cells.append(cell)
		#
		## Calculate Budget
		#var current_budget = base_flow_gain + (float(i) * flow_increment)
		#river.segment_flow.append(current_budget)
		#
		#var river_bed_height = 0.0
		#if not core_cells.is_empty():
			#river_bed_height = map_data[core_cells[0]]
		#elif not segment.is_empty():
			#river_bed_height = map_data[segment[0]]
		#
		## --- OUTER LOOP: WAVES ---
		#while current_budget > 0:
			#var flooded_count_this_wave = 0
			#var candidates = []
			#var candidate_set = {} 
			#
			#for cell in segment:
				#for d in directions:
					#var neighbor = cell + d
					#
					#if not map_data.has(neighbor): continue
					#if river_cells_set.has(neighbor): continue
					#if candidate_set.has(neighbor): continue
					#if ocean_mask.get(neighbor, false) == true: continue
					#
					## --- 3. CALCULATE COSTS ---
					#var target_height = map_data[neighbor]
					#var cost = flood_cost_base
					#
					## A. CLIMB COST (Height Difference)
					#var height_diff = target_height - river_bed_height
					#if height_diff > climb_tolerance:
						#var excess = height_diff - climb_tolerance
						#cost += excess * flood_climb_cost
					#
					## B. DISTANCE COST (New!)
					## Find distance to the closest "Core" cell in this segment
					#var min_dist = 999.0
					#for core in core_cells:
						#var d_val = core.distance_to(neighbor)
						#if d_val < min_dist: min_dist = d_val
					#
					## Apply Penalty (Distance is usually >= 1.0)
					#cost += min_dist * flood_distance_cost
					#
					#candidates.append({
						#"pos": neighbor,
						#"cost": cost
					#})
					#candidate_set[neighbor] = true
			#
			#if candidates.is_empty():
				#break
			#
			## 4. START FLOODING
			#candidates.sort_custom(func(a, b): return a.cost < b.cost)
			#
			#var limit = min(candidates.size(), 5)
			#
			#for k in range(limit):
				#var best = candidates[k]
				#
				#if current_budget >= best.cost:
					#current_budget -= best.cost
					#
					#segment.append(best.pos)
					#river_cells_set[best.pos] = true
					#flooded_count_this_wave += 1
				#else:
					#current_budget = -1.0 
					#break
			#
			#if current_budget <= 0 or flooded_count_this_wave == 0:
				#break

# As of 02.18.2026
#extends Node
#
#class_name River_Widener
#
## Widens the river using an "Iterative Round-Robin" approach.
## - Mouth segments gain EXPONENTIAL flow towards the ocean.
## - Cells <= 0.07 height are flooded for FREE (0 cost).
#func widen_river_iterative(
	#map_data: Dictionary, 
	#river: River, 
	#ocean_mask: Dictionary, 
	#beach_mask: Dictionary,
	#mouth_segments : int,
	#base_flow_gain: float, 
	#flow_increment: float, 
	#flood_cost_base: float = 1.0, 
	#flood_climb_cost: float = 5.0,
	#flood_distance_cost: float = 0.3,
	#climb_tolerance: float = 0.01
#):
	#
	#river.segment_flow.clear()
	#
	## --- 1. PRE-CALCULATE BUDGETS ---
	#var segment_budgets: Array[float] = []
	#var total_segments = river.segments.size()
	#var start_of_mouth = max(0, total_segments - mouth_segments)
	#
	#for i in range(total_segments):
		#var is_mouth = i >= start_of_mouth
		#var budget = base_flow_gain + (float(i) * flow_increment)
		#
		#segment_budgets.append(budget)
		#river.segment_flow.append(budget)
#
	## --- 2. SETUP OPTIMIZATION STRUCTURES ---
	#var path_set = {}
	#for pos in river.river_path:
		#path_set[pos] = true
#
	#var river_cells_set = {}
	#for pos in river.river_path:
		#river_cells_set[pos] = true
	#
	#var directions = [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
	#
	#var segment_data_cache = []
	#for i in range(river.segments.size()):
		#var segment = river.segments[i]
		#var core_cells: Array[Vector2] = []
		#for cell in segment:
			#if path_set.has(cell):
				#core_cells.append(cell)
		#
		#var bed_height = 0.0
		#if not core_cells.is_empty():
			#bed_height = map_data[core_cells[0]]
		#elif not segment.is_empty():
			#bed_height = map_data[segment[0]]
			#
		#segment_data_cache.append({
			#"core_cells": core_cells,
			#"bed_height": bed_height
		#})
#
	## --- 3. THE ROUND-ROBIN LOOP ---
	#var segments_active = true
	#var loop_count = 0
	#var max_loops = 500 
	#
	#while segments_active and loop_count < max_loops:
		#segments_active = false 
		#loop_count += 1
		#
		#for i in range(river.segments.size()):
			#if segment_budgets[i] <= 0:
				#continue
				#
			#var segment = river.segments[i]
			#var seg_data = segment_data_cache[i]
			#var is_mouth = i >= start_of_mouth
			#
			#var candidates = []
			#var candidate_set = {}
			#
			#for cell in segment:
				#for d in directions:
					#var neighbor = cell + d
					#
					#if not map_data.has(neighbor): continue
					#if river_cells_set.has(neighbor): continue
					#if candidate_set.has(neighbor): continue
					#if ocean_mask.get(neighbor, false) == true: continue
					#
					## B. CALCULATE COST
					#var target_height = map_data[neighbor]
					#var cost = 0.0
					#
					## --- CHECK 1: IS IT FREE? ---
					#if target_height <= 0.07:
						## Force cost to 0.0 and SKIP all other math (Climb, Distance, Base)
						#cost = 0.0
						#
					#else:
						## --- CHECK 2: STANDARD COST CALCULATION ---
						#var effective_base = flood_cost_base
						#var effective_dist = flood_distance_cost
						#
						## Lowland Discount (0.07 < h <= 0.12)
						#if target_height <= 0.12:
							#effective_base *= 0.8 
							#effective_dist *= 0.8
						#
						## Mouth Distance Discount
						#if is_mouth:
							#effective_dist *= 0.3
						#
						#cost = effective_base
						#
						## Climb Cost (Only calculated if not free)
						#var height_diff = target_height - seg_data.bed_height
						#if height_diff > climb_tolerance:
							#cost += (height_diff - climb_tolerance) * flood_climb_cost
						#
						## Distance Cost
						#var min_dist = 999.0
						#for core in seg_data.core_cells:
							#var d_val = core.distance_to(neighbor)
							#if d_val < min_dist: min_dist = d_val
						#cost += min_dist * effective_dist
					#
					#candidates.append({ "pos": neighbor, "cost": cost })
					#candidate_set[neighbor] = true
			#
			## C. ATTEMPT TO WIDEN
			#if candidates.is_empty():
				#segment_budgets[i] = -1.0
				#continue
				#
			#candidates.sort_custom(func(a, b): return a.cost < b.cost)
			#
			#var batch_size = 3 
			#
			#for k in range(min(candidates.size(), batch_size)):
				#var best = candidates[k]
				#
				#if segment_budgets[i] >= best.cost:
					#segment_budgets[i] -= best.cost
					#segment.append(best.pos)
					#river_cells_set[best.pos] = true
					#segments_active = true 
				#else:
					#segment_budgets[i] = -1.0
					#break
#
#
## Combines the last 'n' segments of the river into a single "Delta Segment".
#func merge_segments(river: River, n_segments_to_merge: int):
	#if river.segments.size() < n_segments_to_merge + 1:
		#return # River too short to make a delta
		#
	#var delta_cells: Array[Vector2] = []
	#
	## 1. Collect all cells from the last N segments
	## We iterate backwards to pop them off easily
	#for k in range(n_segments_to_merge):
		#var segment = river.segments.pop_back()
		#delta_cells.append_array(segment)
		#
	## 2. Add the combined cluster back as a single segment
	## (We reverse the collection order if strictly needed, but for a set of cells it implies no order)
	#river.segments.append(delta_cells)
	#
	#print("Delta created. River now has ", river.segments.size(), " segments.")
