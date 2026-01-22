extends Node

class_name River_Widener

# Widens the river using a recursive "Flood Fill" approach.
# Consumes ocean_mask to ensure we never accidentally flood the sea.
func widen_river_natural(map_data: Dictionary, river: River, ocean_mask: Dictionary, start_flow: float, flow_gain: float, flood_cost_base: float = 0.7, flood_climb_cost: float = 15.0):
	
	river.segment_flow.clear()
	var carried_flow = start_flow
	
	var river_cells_set = {}
	for pos in river.river_path:
		river_cells_set[pos] = true
	
	# --- ITERATE SEGMENTS ---
	for i in range(river.segments.size()):
		var segment = river.segments[i]
		
		# 1. ACCUMULATE FLOW
		var current_budget = carried_flow + flow_gain
		river.segment_flow.append(current_budget)
		
		# 2. INITIALIZE CANDIDATES
		var candidates = [] 
		var candidate_set = {} 
		var directions = [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
		
		var add_neighbors_to_candidates = func(source_cells: Array):
			for cell in source_cells:
				for d in directions:
					var neighbor = cell + d
					
					# A. Basic Checks
					if not map_data.has(neighbor): continue
					if river_cells_set.has(neighbor): continue
					if candidate_set.has(neighbor): continue
					
					# B. OCEAN CHECK (The Fix)
					# If this neighbor is already ocean, we CANNOT flood it.
					if ocean_mask.get(neighbor, false) == true:
						continue
					
					# C. Add to Pool
					var c_data = { "pos": neighbor, "height": map_data[neighbor] }
					candidates.append(c_data)
					candidate_set[neighbor] = true
		
		# Seed the pool
		add_neighbors_to_candidates.call(segment)
		
		var river_bed_height = 0.0
		if not segment.is_empty():
			river_bed_height = map_data[segment[0]]
		
		# 3. RECURSIVE FLOOD LOOP
		while current_budget > 0 and not candidates.is_empty():
			
			candidates.sort_custom(func(a, b): return a.height < b.height)
			
			var best_candidate = candidates[0]
			var target_pos = best_candidate.pos
			var target_height = best_candidate.height
			
			var cost = flood_cost_base
			var height_diff = target_height - river_bed_height
			if height_diff > 0:
				cost += height_diff * flood_climb_cost
				
			if current_budget >= cost:
				current_budget -= cost
				
				candidates.remove_at(0)
				
				segment.append(target_pos)
				river_cells_set[target_pos] = true
				
				# Expand frontier
				add_neighbors_to_candidates.call([target_pos])
				
			else:
				break
		
		carried_flow = current_budget
		
# Removes river cells from the last segment if they overlap with the ocean mask.
# This fixes "spilling" where the river widening algorithm floods the ocean itself.
func clean_river_mouth(river: River, ocean_mask: Dictionary):
	if river.segments.is_empty():
		return

	# Get the last segment (the mouth of the river)
	var last_segment_index = river.segments.size() - 1
	var last_segment = river.segments[last_segment_index]
	
	var cleaned_segment: Array[Vector2] = []
	
	for cell in last_segment:
		# Check if this specific cell is Ocean
		# (If ocean_mask doesn't have the key, we assume False/Land for safety)
		var is_ocean = ocean_mask.get(cell, false)
		
		if not is_ocean:
			# Keep the cell if it is LAND
			cleaned_segment.append(cell)
			
	# Update the segment with only the valid land cells
	river.segments[last_segment_index] = cleaned_segment
