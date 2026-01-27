extends Node

#class_name River_Widener_old
#
#func river_widener(
	#map_data: Dictionary, 
	#river: River, 
	#ocean_mask: Dictionary, 
	#start_flow: float, 
	#flow_gain: float, 
	#flood_cost_base: float = 1.0, 
	#flood_climb_cost: float = 5.0,
	#climb_tolerance: float = 0.5 # NEW: Free height difference allowed before penalty kicks in
#):
	#var carried_flow = start_flow
	#for i in range(river.segments.size()):
		#while river.flow[i] > 0:
			#var neighbour_cells = find_neighbors(river.segments[i])
			#
#
#func find_neighbors(cells: Array[Vector2]) -> Array[Vector2]:
	#var neighbor_offsets := [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]
#
	## Convert original cells to a lookup set
	#var cell_set := {}
	#for cell in cells:
		#cell_set[cell] = true
#
	#var result_set := {}
#
	#for cell in cells:
		#for offset in neighbor_offsets:
			#var neighbor = cell + offset
#
			## Only add if NOT in original array
			#if not cell_set.has(neighbor):
				#result_set[neighbor] = true
#
	## Convert back to Array
	#return result_set.keys()
#
## Widens the river using an Iterative Wave approach.
## - Floods in batches (waves) of 5 cells.
## - Recalculates neighbors after every wave.
## - Flow increases incrementally downstream.
## - Flow DOES NOT carry over between segments.
#func widen_river_wave_based(
	#map_data: Dictionary, 
	#river: River, 
	#ocean_mask: Dictionary, 
	#base_flow_gain: float, 
	#flow_increment: float, # Extra flow per segment index
	#flood_cost_base: float = 1.0, 
	#flood_climb_cost: float = 10.0,
	#climb_tolerance: float = 0.05
#):
	#
	#river.segment_flow.clear()
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
		## 1. CALCULATE FLOW BUDGET
		## "base flow gain + flow order * flow increment"
		#var current_budget = base_flow_gain + (float(i) * flow_increment)
		#
		## Store for debugging
		#river.segment_flow.append(current_budget)
		#
		## We define the "River Bed Height" as the lowest point in the original path for this segment
		## This ensures we are always climbing out of the channel, not the bank.
		#var river_bed_height = 0.0
		#if not segment.is_empty():
			#river_bed_height = map_data[segment[0]]
		#
		## --- OUTER LOOP: WAVES ---
		#while current_budget > 0:
			#var flooded_count_this_wave = 0
			#
			## 2. FIND NEIGHBORS
			## We scan the ENTIRE segment (which might have grown) to find current frontier
			#var candidates = []
			#var candidate_set = {} # Prevent duplicates in the list
			#
			#for cell in segment:
				#for d in directions:
					#var neighbor = cell + d
					#
					## Validity Checks
					#if not map_data.has(neighbor): continue
					#if river_cells_set.has(neighbor): continue
					#if candidate_set.has(neighbor): continue
					#if ocean_mask.get(neighbor, false) == true: continue
					#
					## 3. GENERATE COST
					#var target_height = map_data[neighbor]
					#var cost = flood_cost_base
					#var height_diff = target_height - river_bed_height
					#
					#if height_diff > climb_tolerance:
						#var excess = height_diff - climb_tolerance
						#cost += excess * flood_climb_cost
					#
					#candidates.append({
						#"pos": neighbor,
						#"cost": cost
					#})
					#candidate_set[neighbor] = true
			#print(candidates.size())
			## If no place to go, stop this segment
			#if candidates.is_empty():
				#break
			#
			## 4. START FLOODING (Lowest Cost First)
			#candidates.sort_custom(func(a, b): return a.cost < b.cost)
			#
			## "Do it 5 times (or while flow allows)"
			#var limit = min(candidates.size(), 5)
			#
			#for k in range(limit):
				#var best = candidates[k]
				#
				#if current_budget >= best.cost:
					## Spend & Flood
					#current_budget -= best.cost
					#
					#segment.append(best.pos)
					#river_cells_set[best.pos] = true
					#flooded_count_this_wave += 1
				#else:
					## Can't afford the cheapest option -> Budget exhausted
					#current_budget = -1.0 # Force break
					#break
			#
			## 5. LOOP CONDITION
			## "If flow is still > 0, and at least 1 cell was flooded, repeat"
			#if current_budget <= 0 or flooded_count_this_wave == 0:
				#break
				#
		## 6. MOVE TO NEXT SEGMENT
		## (Remaining flow is discarded/ignored as requested)
#
## Widens the river. Includes a "Freeboard" tolerance so plains don't cost too much to flood.
#func widen_river_natural(
	#map_data: Dictionary, 
	#river: River, 
	#ocean_mask: Dictionary, 
	#start_flow: float, 
	#flow_gain: float, 
	#flood_cost_base: float = 1.0, 
	#flood_climb_cost: float = 5.0,
	#climb_tolerance: float = 0.5 # NEW: Free height difference allowed before penalty kicks in
#):
	#
	#river.segment_flow.clear()
	#var carried_flow = start_flow
	#
	#var river_cells_set = {}
	#for pos in river.river_path:
		#river_cells_set[pos] = true
	#
	## --- ITERATE SEGMENTS ---
	#for i in range(river.segments.size()):
		#var segment = river.segments[i]
		#
		## 1. ACCUMULATE FLOW
		#var current_budget = carried_flow + flow_gain
		#river.segment_flow.append(current_budget)
		#
		## 2. INITIALIZE CANDIDATES
		#var candidates = [] 
		#var candidate_set = {} 
		#var directions = [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
		#
		#var add_neighbors_to_candidates = func(source_cells: Array):
			#for cell in source_cells:
				#for d in directions:
					#var neighbor = cell + d
					#
					#if not map_data.has(neighbor): continue
					#if river_cells_set.has(neighbor): continue
					#if candidate_set.has(neighbor): continue
					#if ocean_mask.get(neighbor, false) == true: continue
					#
					#var c_data = { "pos": neighbor, "height": map_data[neighbor] }
					#candidates.append(c_data)
					#candidate_set[neighbor] = true
		#
		#add_neighbors_to_candidates.call(segment)
		#
		#var river_bed_height = 0.0
		#if not segment.is_empty():
			#river_bed_height = map_data[segment[0]]
		#
		## 3. RECURSIVE FLOOD LOOP
		#while current_budget > 0 and not candidates.is_empty():
			#
			#candidates.sort_custom(func(a, b): return a.height < b.height)
			#
			#var best_candidate = candidates[0]
			#var target_pos = best_candidate.pos
			#var target_height = best_candidate.height
			#
			#var cost = flood_cost_base
			#var height_diff = target_height - river_bed_height
			#
			## --- THE FIX: CLIMB TOLERANCE ---
			## We ignore the first X meters of height difference.
			## This represents the river filling up its own eroded channel.
			## Only when it breaches the bank (diff > tolerance) do we charge extra.
			#
			#if height_diff > climb_tolerance:
				#var excess_height = height_diff - climb_tolerance
				#cost += excess_height * flood_climb_cost
			#
			## If the neighboring land is LOWER than the bed (rare, but possible in basins), 
			## we treat it as free or super cheap (base cost only).
				#
			#if current_budget >= cost:
				#current_budget -= cost
				#candidates.remove_at(0)
				#segment.append(target_pos)
				#river_cells_set[target_pos] = true
				#add_neighbors_to_candidates.call([target_pos])
			#else:
				#break
		#
		#carried_flow = current_budget
#
### Widens the river using a recursive "Flood Fill" approach.
### Consumes ocean_mask to ensure we never accidentally flood the sea.
##func widen_river_natural(map_data: Dictionary, river: River, ocean_mask: Dictionary, start_flow: float, flow_gain: float, flood_cost_base: float = 0.7, flood_climb_cost: float = 15.0):
	##
	##river.segment_flow.clear()
	##var carried_flow = start_flow
	##
	##var river_cells_set = {}
	##for pos in river.river_path:
		##river_cells_set[pos] = true
	##
	### --- ITERATE SEGMENTS ---
	##for i in range(river.segments.size()):
		##var segment = river.segments[i]
		##
		### 1. ACCUMULATE FLOW
		##var current_budget = carried_flow + flow_gain
		##river.segment_flow.append(current_budget)
		##
		### 2. INITIALIZE CANDIDATES
		##var candidates = [] 
		##var candidate_set = {} 
		##var directions = [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]
		##
		##var add_neighbors_to_candidates = func(source_cells: Array):
			##for cell in source_cells:
				##for d in directions:
					##var neighbor = cell + d
					##
					### A. Basic Checks
					##if not map_data.has(neighbor): continue
					##if river_cells_set.has(neighbor): continue
					##if candidate_set.has(neighbor): continue
					##
					### B. OCEAN CHECK (The Fix)
					### If this neighbor is already ocean, we CANNOT flood it.
					##if ocean_mask.get(neighbor, false) == true:
						##continue
					##
					### C. Add to Pool
					##var c_data = { "pos": neighbor, "height": map_data[neighbor] }
					##candidates.append(c_data)
					##candidate_set[neighbor] = true
		##
		### Seed the pool
		##add_neighbors_to_candidates.call(segment)
		##
		##var river_bed_height = 0.0
		##if not segment.is_empty():
			##river_bed_height = map_data[segment[0]]
		##
		### 3. RECURSIVE FLOOD LOOP
		##while current_budget > 0 and not candidates.is_empty():
			##
			##candidates.sort_custom(func(a, b): return a.height < b.height)
			##
			##var best_candidate = candidates[0]
			##var target_pos = best_candidate.pos
			##var target_height = best_candidate.height
			##
			##var cost = flood_cost_base
			##var height_diff = target_height - river_bed_height
			##if height_diff > 0:
				##cost += height_diff * flood_climb_cost
				##
			##if current_budget >= cost:
				##current_budget -= cost
				##
				##candidates.remove_at(0)
				##
				##segment.append(target_pos)
				##river_cells_set[target_pos] = true
				##
				### Expand frontier
				##add_neighbors_to_candidates.call([target_pos])
				##
			##else:
				##break
		##
		##carried_flow = current_budget
		#
## Removes river cells from the last segment if they overlap with the ocean mask.
## This fixes "spilling" where the river widening algorithm floods the ocean itself.
#func clean_river_mouth(river: River, ocean_mask: Dictionary):
	#if river.segments.is_empty():
		#return
#
	## Get the last segment (the mouth of the river)
	#var last_segment_index = river.segments.size() - 1
	#var last_segment = river.segments[last_segment_index]
	#
	#var cleaned_segment: Array[Vector2] = []
	#
	#for cell in last_segment:
		## Check if this specific cell is Ocean
		## (If ocean_mask doesn't have the key, we assume False/Land for safety)
		#var is_ocean = ocean_mask.get(cell, false)
		#
		#if not is_ocean:
			## Keep the cell if it is LAND
			#cleaned_segment.append(cell)
			#
	## Update the segment with only the valid land cells
	#river.segments[last_segment_index] = cleaned_segment
