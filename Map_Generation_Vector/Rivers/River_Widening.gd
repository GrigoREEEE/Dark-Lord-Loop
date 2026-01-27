extends Node

class_name River_Widener

# Configuration for flooding costs
const COST_BASE: float = 1.0
const COST_HEIGHT_MULTIPLIER: float = 20.0  # High penalty for going uphill
const COST_DISTANCE_MULTIPLIER: float = 0.5 # Penalty for getting wide
const MAX_SEARCH_ITERATIONS: int = 500      # Safety break for while loops
const BASE_FLOW_GAIN : float = 1.0
const ITERATIVE_FLOW_GAIN : float = 0.005


## Main function to consume and expand the River object
static func expand_river(river: Object, world_heights: Dictionary) -> void:
	accumulate_flow(river)
	
	# 1. Validation and Setup
	if river.segments.size() != river.river_path.size():
		push_warning("River segments and path length mismatch. Adjusting...")
		river.segments.resize(river.river_path.size())

	# A set to keep track of every cell owned by the river to prevent overlap
	var global_river_cells: Dictionary = {} 
	
	# Pre-populate global cells with the river spine (center path)
	for point in river.river_path:
		global_river_cells[point] = true

	# Variable to track flow accumulation from source to mouth
	var current_accumulated_flow: float = 0.0

	# 2. Iterate through every segment
	for i in range(len(river.segments)):
		var center_pos: Vector2 = river.river_path[i]
		
		# Initialize the segment array if empty
		if river.segments[i] == null:
			river.segments[i] = []
		
		# Ensure the center point is part of the segment
		if not center_pos in river.segments[i]:
			river.segments[i].append(center_pos)

		# Add new flow to the accumulation (River gets bigger downstream)
		# We use modulo or a check to prevent index errors if flow array is smaller
		var flow_add: float = 0.0
		if i < river.segment_flow.size():
			flow_add = river.segment_flow[i]
		
		current_accumulated_flow += flow_add
		print("Iteration %s, flow is %s" % [i,current_accumulated_flow])
		# 3. Perform the Flood Fill for this segment
		_flood_segment(
			river.segments[i], 
			center_pos, 
			current_accumulated_flow, 
			world_heights, 
			global_river_cells
		)

static func accumulate_flow(river: Object) -> void:
	for i in river.segments.size():
		river.segment_flow.append((BASE_FLOW_GAIN + ITERATIVE_FLOW_GAIN * i))

## Helper: Floods a single segment based on a flow budget
static func _flood_segment(
	segment_cells: Array, 
	center: Vector2, 
	flow_budget: float, 
	world_heights: Dictionary, 
	global_visited: Dictionary
) -> void:
	
	# Priority Queue logic: Stores [Vector2, cost]
	# We use a simple array and sort it to act as a priority queue
	var candidates: Array = []
	var center_height: float = world_heights.get(center, 0.0)
	
	# Add initial neighbors of the center
	_add_neighbors(center, center, center_height, candidates, world_heights, global_visited)
	
	var safety_counter: int = 0
	
	# While we have water (budget) and places to go
	while flow_budget > 0 and not candidates.is_empty():
		safety_counter += 1
		if safety_counter > MAX_SEARCH_ITERATIONS:
			break

		# Sort candidates so the "cheapest" cell is last (for efficient popping)
		# We sort descending by cost, so pop_back() gives us the smallest cost
		candidates.sort_custom(func(a, b): return a.cost > b.cost)
		
		var current_candidate = candidates.pop_back()
		var pos: Vector2 = current_candidate.pos
		var cost: float = current_candidate.cost
		
		# Check if we can afford this cell
		if flow_budget >= cost:
			# Buy the cell
			flow_budget -= cost
			segment_cells.append(pos)
			global_visited[pos] = true
			
			# Add this new cell's neighbors to candidates
			_add_neighbors(pos, center, center_height, candidates, world_heights, global_visited)
		else:
			# If we can't afford the cheapest option, we are done with this segment
			break

## Helper: Calculates cost and adds valid neighbors to candidates
static func _add_neighbors(
	current_pos: Vector2, 
	segment_center: Vector2, 
	center_height: float,
	candidates: Array, 
	world_heights: Dictionary, 
	global_visited: Dictionary
) -> void:
	
	var directions = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	
	for dir in directions:
		var neighbor: Vector2 = current_pos + dir
		
		# validation: Check bounds (exists in world) and if already used
		if not world_heights.has(neighbor): continue
		if global_visited.has(neighbor): continue
		
		# Check if this neighbor is already in the candidates list to avoid duplicates
		var already_queued = false
		for c in candidates:
			if c.pos == neighbor:
				already_queued = true
				break
		if already_queued: continue

		# --- COST CALCULATION ---
		var neighbor_height: float = world_heights[neighbor]
		var height_diff: float = neighbor_height - center_height
		
		# If neighbor is lower, height cost is 0. If higher, it's expensive.
		var height_penalty: float = max(0.0, height_diff) * COST_HEIGHT_MULTIPLIER
		
		# Distance from the spine of the river
		var dist: float = neighbor.distance_to(segment_center)
		var dist_penalty: float = dist * COST_DISTANCE_MULTIPLIER
		
		var total_cost: float = COST_BASE + height_penalty + dist_penalty
		
		candidates.append({ "pos": neighbor, "cost": total_cost })
#
#
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
	#flood_distance_cost: float = 0.1, # NEW: Penalty for distance
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
				#
