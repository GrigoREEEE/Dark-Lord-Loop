extends Node

class_name River_Widener

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

# A specialized flood-fill for the Delta.
# - High budget.
# - Directional bias (Cheaper to flood downstream).
# - allowed_to_touch_ocean: It can eat beach/ocean pixels.
func expand_delta(
	map_data: Dictionary, 
	river: River, 
	ocean_mask: Dictionary,
	flow_budget: float = 40.0, # Huge budget for the delta
	climb_cost: float = 10.0,  # Hard to climb up
	spread_cost: float = 0.5   # Very cheap to spread wide
):
	if river.segments.is_empty(): return
	
	# The Delta is the LAST segment
	var delta_segment = river.segments[-1]
	var delta_root = delta_segment[0] # The point where the river becomes the delta
	
	# Track cells
	var delta_set = {}
	for cell in delta_segment: delta_set[cell] = true
	
	var candidates = []
	var candidate_set = {}
	var directions = [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
	
	# Initialize Frontier
	for cell in delta_segment:
		for d in directions:
			var n = cell + d
			if not map_data.has(n): continue
			if delta_set.has(n): continue
			if candidate_set.has(n): continue
			
			# Note: We DO allow Ocean/Beach here, effectively extending land into water
			
			candidates.append(n)
			candidate_set[n] = true
			
	# --- DELTA FLOOD LOOP ---
	while flow_budget > 0 and not candidates.is_empty():
		
		# 1. EVALUATE CANDIDATES
		# We need to pick the "Best" cell to expand the fan.
		var best_index = -1
		var best_cost = 9999.0
		
		for k in range(candidates.size()):
			var pos = candidates[k]
			var height = map_data[pos]
			
			# Base Cost
			var cost = spread_cost
			
			# A. DIRECTIONAL BIAS (The Fan Effect)
			# Calculate vector from Root to Candidate
			var dist_from_root = delta_root.distance_to(pos)
			var y_diff = pos.y - delta_root.y
			
			# If we are moving North (Upstream), make it EXPENSIVE.
			# If we are moving South (Downstream), make it CHEAP.
			if y_diff < 0:
				cost += 5.0 # Upstream penalty
			else:
				cost *= 0.5 # Downstream discount
				
			# B. CLIMB COST (Standard)
			# Deltas form on flatlands. Climbing is hard.
			# We approximate "River Level" as 0.05 or the root height
			var height_diff = height - 0.05 
			if height_diff > 0:
				cost += height_diff * climb_cost
			
			if cost < best_cost:
				best_cost = cost
				best_index = k
		
		# 2. COMMIT
		if best_index != -1:
			var target = candidates[best_index]
			
			if flow_budget >= best_cost:
				flow_budget -= best_cost
				
				# Add to delta
				delta_segment.append(target)
				delta_set[target] = true
				
				# Remove from list
				candidates.remove_at(best_index)
				
				# Add neighbors
				for d in directions:
					var n = target + d
					if map_data.has(n) and not delta_set.has(n) and not candidate_set.has(n):
						candidates.append(n)
						candidate_set[n] = true
			else:
				# Too expensive for remaining budget, remove this candidate to save perf
				candidates.remove_at(best_index)
		else:
			break

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
				
