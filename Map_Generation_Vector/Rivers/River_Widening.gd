extends Node
class_name River_Widener

var flood_cost_base: float = 1.0
var flood_climb_cost: float = 5.0
var flood_distance_cost: float = 0.3
var climb_tolerance: float = 0.01

# Widens the river using an "Iterative Round-Robin" approach.
# - The river naturally gets slightly wider downstream via flow_increment.
# - Cells <= 0.12 height get a slight cost discount.
func widen_river_iterative(
	world_data: World_Data,
	river: River,
	base_flow_gain: float, 
	flow_increment: float,
	enable_conical_mouth: bool = false,
	mouth_segments: int = 5, 
	mouth_cost_discount: float = 0.10
):
	
	river.segment_flow.clear()
	
	# --- 1. PRE-CALCULATE BUDGETS ---
	var segment_budgets: Array[float] = []
	var total_segments = river.segments.size()
	
	for i in range(total_segments):
		# We apply a slight curve to the budget so it doesn't explode exponentially at the mouth
		var progress = float(i) / float(max(1, total_segments - 1))
		var budget = base_flow_gain + (flow_increment * total_segments * pow(progress, 0.75))
		
		segment_budgets.append(budget)
		river.segment_flow.append(budget)

	# --- 2. SETUP OPTIMIZATION STRUCTURES ---
	var path_set = {}
	for pos in river.river_path:
		path_set[pos] = true

	var river_cells_set = {}
	for pos in river.river_path:
		river_cells_set[pos] = true
	
	# REMOVED 4-way directions array
	
	var segment_data_cache = []
	for i in range(river.segments.size()):
		var region: Region = river.segments[i]
		var core_cells: Array[Vector2] = []
		
		for cell in region.points:
			if path_set.has(cell):
				core_cells.append(cell)
		
		var bed_height = 0.0
		if not core_cells.is_empty():
			bed_height = world_data.map_data["terrain"][core_cells[0]]
		elif not region.points.is_empty():
			bed_height = world_data.map_data["terrain"][region.points[0]]
			
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
				
			var region: Region = river.segments[i]
			var seg_data = segment_data_cache[i]
			
			# --- NEW: CALCULATE CONICAL DISCOUNT ---
			var is_mouth = enable_conical_mouth and i >= (river.segments.size() - mouth_segments)
			var current_discount = 1.0
			
			if is_mouth:
				var dist_from_end = (river.segments.size() - 1) - i
				var cone_factor = float(dist_from_end) / float(max(1, mouth_segments - 1))
				# Smoothly scales from mouth_cost_discount (at the very end) up to 1.0 (inland)
				current_discount = lerp(mouth_cost_discount, 1.0, cone_factor)
				
			var candidates = []
			var candidate_set = {}
			
			# Search neighbors around the Region's points
			for cell in region.points:
				# FIX 1: Use 6-way hex neighbors
				var neighbors = global._get_hex_neighbors(cell)
				
				for neighbor in neighbors:
					if not world_data.map_data["terrain"].has(neighbor): continue
					if river_cells_set.has(neighbor): continue
					if candidate_set.has(neighbor): continue
					if world_data.mask_data["ocean"].get(neighbor, false) == true: continue
					
					# B. CALCULATE COST
					var target_height = world_data.map_data["terrain"][neighbor]
					var cost = 0.0
					
					var effective_base = flood_cost_base
					var effective_dist = flood_distance_cost
						
					# Lowland Discount (0.07 < h <= 0.12)
					if target_height <= 0.12:
						effective_base *= 0.8 
						effective_dist *= 0.8
						
					cost = effective_base
						
					# Climb Cost
					var height_diff = target_height - seg_data.bed_height
					if height_diff > climb_tolerance:
						cost += (height_diff - climb_tolerance) * flood_climb_cost
						
					# Calculate Physical Distance Cost
					var min_dist = 999.0
					var phys_neighbor = global._get_hex_physical_pos(neighbor)
					
					for core in seg_data.core_cells:
						var phys_core = global._get_hex_physical_pos(core)
						var d_val = phys_core.distance_to(phys_neighbor)
						if d_val < min_dist: 
							min_dist = d_val
							
					cost += min_dist * effective_dist
					
					# --- NEW: APPLY CONICAL DISCOUNT ---
					cost *= current_discount
						
					candidates.append({ "pos": neighbor, "cost": cost })
					candidate_set[neighbor] = true
		
			# C. ATTEMPT TO WIDEN
			if candidates.is_empty():
				segment_budgets[i] = -1.0
				continue
				
			candidates.sort_custom(func(a, b): return a.cost < b.cost)
			
			var expensive_fill_limit = 3 
			var expensive_fill_count = 0
			
			for best in candidates:
				if best.cost > 0.0 and expensive_fill_count >= expensive_fill_limit:
					break
				
				if segment_budgets[i] >= best.cost:
					segment_budgets[i] -= best.cost
					
					region.points.append(best.pos)
					region.size = region.points.size()
					
					river_cells_set[best.pos] = true
					segments_active = true 
					
					if best.cost > 0.0:
						expensive_fill_count += 1
				else:
					segment_budgets[i] = -1.0
					break


# Combines the last 'n' regions of the river into a single "Delta Region".
func merge_segments(river: River, n_segments_to_merge: int):
	if river.segments.size() < n_segments_to_merge + 1:
		return # River too short to make a delta
		
	var delta_points: Array[Vector2] = []
	var popped_regions: Array[Region] = []
	
	# 1. Collect all points from the last N regions
	# We iterate backwards to pop them off easily
	for k in range(n_segments_to_merge):
		var popped_region: Region = river.segments.pop_back()
		delta_points.append_array(popped_region.points)
		popped_regions.append(popped_region)
		
	# 2. Identify the surviving upstream region and clean up connections
	var previous_region: Region = null
	if not river.segments.is_empty():
		previous_region = river.segments.back()
		
		# Break the old forward connections to the deleted regions
		for popped in popped_regions:
			if previous_region.regions_connect.has(popped):
				previous_region.regions_connect.erase(popped)

	# 3. Create the new combined Delta Region
	var delta_region = Region.new()
	delta_region.id = randi()
	delta_region.type = "Water"
	delta_region.subtype = "River Delta"
	delta_region.points = delta_points
	delta_region.size = delta_points.size()
	
	# 4. Link the new Delta back to the surviving main river
	if previous_region != null:
		previous_region.regions_connect.append(delta_region)
		delta_region.regions_connect.append(previous_region)
		
	# 5. Add the combined cluster back as a single region
	river.segments.append(delta_region)
	
	print("Delta Region created. River now has ", river.segments.size(), " segments.")
	
