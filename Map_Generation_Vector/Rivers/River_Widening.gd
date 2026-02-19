extends Node

class_name River_Widener

# Widens the river using an "Iterative Round-Robin" approach.
# - Mouth segments gain EXPONENTIAL flow towards the ocean.
# - Cells <= 0.07 height are flooded for FREE (0 cost).
func widen_river_iterative(
	map_data: Dictionary, 
	river: River, 
	ocean_mask: Dictionary,
	mouth_segments : int,
	base_flow_gain: float, 
	flow_increment: float, 
	flood_cost_base: float = 1.0, 
	flood_climb_cost: float = 5.0,
	flood_distance_cost: float = 0.3,
	climb_tolerance: float = 0.01
):
	
	river.segment_flow.clear()
	
	# --- 1. PRE-CALCULATE BUDGETS ---
	var segment_budgets: Array[float] = []
	var total_segments = river.segments.size()
	var start_of_mouth = max(0, total_segments - mouth_segments)
	
	for i in range(total_segments):
		var is_mouth = i >= start_of_mouth
		var budget = base_flow_gain + (float(i) * flow_increment)
		
		segment_budgets.append(budget)
		river.segment_flow.append(budget)

	# --- 2. SETUP OPTIMIZATION STRUCTURES ---
	var path_set = {}
	for pos in river.river_path:
		path_set[pos] = true

	var river_cells_set = {}
	for pos in river.river_path:
		river_cells_set[pos] = true
	
	var directions = [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
	
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
	var max_loops = 500 
	
	while segments_active and loop_count < max_loops:
		segments_active = false 
		loop_count += 1
		
		for i in range(river.segments.size()):
			if segment_budgets[i] <= 0:
				continue
				
			var segment = river.segments[i]
			var seg_data = segment_data_cache[i]
			var is_mouth = i >= start_of_mouth
			
			var candidates = []
			var candidate_set = {}
			
			for cell in segment:
				for d in directions:
					var neighbor = cell + d
					
					if not map_data.has(neighbor): continue
					if river_cells_set.has(neighbor): continue
					if candidate_set.has(neighbor): continue
					if ocean_mask.get(neighbor, false) == true: continue
					
					# B. CALCULATE COST
					var target_height = map_data[neighbor]
					var cost = 0.0
					
					var effective_base = flood_cost_base
					var effective_dist = flood_distance_cost
					
					# Lowland Discount (0.07 < h <= 0.12)
					if target_height <= 0.12:
						effective_base *= 0.8 
						effective_dist *= 0.8
					
					# Mouth Distance Discount
					if is_mouth:
						effective_dist *= 0.3
					
					cost = effective_base
					
					# Climb Cost (Only calculated if not free)
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
			
			# C. ATTEMPT TO WIDEN
			if candidates.is_empty():
				segment_budgets[i] = -1.0
				continue
				
			candidates.sort_custom(func(a, b): return a.cost < b.cost)
			
			var batch_size = 3 
			
			for k in range(min(candidates.size(), batch_size)):
				var best = candidates[k]
				
				if segment_budgets[i] >= best.cost:
					segment_budgets[i] -= best.cost
					segment.append(best.pos)
					river_cells_set[best.pos] = true
					segments_active = true 
				else:
					segment_budgets[i] = -1.0
					break


# Combines the last 'n' segments of the river into a single "Delta Segment".
func merge_segments(river: River, n_segments_to_merge: int):
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
	
