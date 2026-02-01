extends Node

class_name River_Widener

# Widens the river using an "Iterative Round-Robin" approach.
# 1. Calculates budgets upfront.
# 2. Cycles through segments (1 -> N -> 1 -> N) performing small widening steps.
# 3. Stops when no segment can afford to widen further.
func widen_river_iterative(
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
	
	# --- 1. PRE-CALCULATE BUDGETS ---
	var segment_budgets: Array[float] = []
	var start_of_mouth = max(0, river.segments.size() - mouth_segments)
	
	for i in range(river.segments.size()):
		var is_mouth = i >= start_of_mouth
		var budget = base_flow_gain + (float(i) * flow_increment)
		
		# Mouth Boost
		if is_mouth:
			budget *= 1.5 
			budget += 10.0 
			
		segment_budgets.append(budget)
		# Update the class property for debug/display usage
		river.segment_flow.append(budget)

	# --- 2. SETUP OPTIMIZATION STRUCTURES ---
	var path_set = {}
	for pos in river.river_path:
		path_set[pos] = true

	var river_cells_set = {}
	for pos in river.river_path:
		river_cells_set[pos] = true
	
	var directions = [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
	
	# Pre-cache core cells and bed height to save performance inside the big loop
	var segment_data_cache = []
	for i in range(river.segments.size()):
		var segment = river.segments[i]
		var core_cells: Array[Vector2] = []
		for cell in segment:
			if path_set.has(cell):
				core_cells.append(cell)
		
		var bed_height = 0.0
		if not core_cells.is_empty():
			bed_height = map_data[core_cells[0]]
		elif not segment.is_empty():
			bed_height = map_data[segment[0]]
			
		segment_data_cache.append({
			"core_cells": core_cells,
			"bed_height": bed_height
		})

	# --- 3. THE ROUND-ROBIN LOOP ---
	var segments_active = true
	var loop_count = 0
	var max_loops = 100 # Safety break to prevent infinite loops
	
	while segments_active and loop_count < max_loops:
		segments_active = false # Assume we are done unless someone widens
		loop_count += 1
		
		# Cycle through every segment once per loop
		for i in range(river.segments.size()):
			# Skip if this segment is out of money
			if segment_budgets[i] <= 0:
				continue
				
			var segment = river.segments[i]
			var seg_data = segment_data_cache[i]
			var is_mouth = i >= start_of_mouth
			
			# A. FIND CANDIDATES (Re-scan frontier)
			var candidates = []
			var candidate_set = {}
			
			# Optimization: Instead of scanning the WHOLE segment every time, 
			# we could track a "frontier", but for simplicity/robustness we scan neighbors.
			for cell in segment:
				for d in directions:
					var neighbor = cell + d
					
					# Validity Checks
					if not map_data.has(neighbor): continue
					if river_cells_set.has(neighbor): continue
					if candidate_set.has(neighbor): continue # Don't double add
					if ocean_mask.get(neighbor, false) == true: continue
					
					# Beach Check
					if beach_mask.get(neighbor, false) == true and not is_mouth:
						continue

					# B. CALCULATE COST
					var target_height = map_data[neighbor]
					var effective_base = flood_cost_base
					var effective_dist = flood_distance_cost
					
					# Lowland Discount
					if (target_height >= 0.07) and (target_height < 0.12):
						effective_base *= 0.8 
						effective_dist *= 0.8
					if (target_height < 0.07):
						effective_base = 0
						effective_dist = 0
						
					# Mouth Discount
					if is_mouth:
						effective_dist *= 0.3
						
					var cost = effective_base
					
					# Climb Cost
					var height_diff = target_height - seg_data.bed_height
					if height_diff > climb_tolerance:
						cost += (height_diff - climb_tolerance) * flood_climb_cost
						
					# Distance Cost
					var min_dist = 999.0
					for core in seg_data.core_cells:
						var d_val = core.distance_to(neighbor)
						if d_val < min_dist: min_dist = d_val
					cost += min_dist * effective_dist
					
					candidates.append({ "pos": neighbor, "cost": cost })
					candidate_set[neighbor] = true
			
			# C. ATTEMPT TO WIDEN (Small Batch)
			if candidates.is_empty():
				# No valid neighbors left to flood, effectively bankrupt this segment to stop checking it
				segment_budgets[i] = -1.0
				continue
				
			candidates.sort_custom(func(a, b): return a.cost < b.cost)
			
			# "Widen the segment a single time" (or small batch of 1-3 cells)
			# Using a batch of 1 is purely iterative, 3 is slightly faster
			var batch_size = 3 
			var flooded_this_turn = 0
			
			for k in range(min(candidates.size(), batch_size)):
				var best = candidates[k]
				
				if segment_budgets[i] >= best.cost:
					segment_budgets[i] -= best.cost
					segment.append(best.pos)
					river_cells_set[best.pos] = true
					flooded_this_turn += 1
					segments_active = true # Keep the outer loop alive!
				else:
					# Can't afford the cheapest option
					segment_budgets[i] = -1.0
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
	
