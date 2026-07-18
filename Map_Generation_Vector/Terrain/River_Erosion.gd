extends Node

class_name River_Erosion

# Applies erosion and sedimentation based on a target height and distance from the river.
# - map_data: The global terrain dictionary.
# - valley_mask: The output from `generate_river_valley_mask`.
# - target_height: The desired ground elevation for the riverbanks (e.g., 0.20).
# - erosion_data: Dictionary holding radius and strength configurations.
# - river_path_size: The total length of the river (used to calculate X cells).
# - x_cells_threshold: After this many cells, adjacent banks are strictly capped.
# - water_level: A safety floor to prevent the algorithm from filling in the ocean.
func apply_target_height_erosion(
	map_data: Dictionary, 
	valley_mask: Dictionary, 
	_ocean_mask: Dictionary[Vector2, bool],
	target_height: float,
	erosion_data : Dictionary[String, float],
	river_path_size: int,
	x_cells_threshold: int = 10,
	water_level: float = -0.5
):
	var start_radius: float = erosion_data["start radius"]
	var end_radius: float = erosion_data["end radius"]
	var start_strength: float = erosion_data["start erosion"]
	var end_strength: float = erosion_data["end erosion"]

	for cell: Vector2 in valley_mask:
		if not map_data.has(cell):
			continue
			
		var current_h: float = map_data[cell]
		
		# --- SAFETY CHECK: PRESERVE DEEP WATER ---
		if current_h <= water_level:
			continue
			
		var data: Dictionary = valley_mask[cell]
		var dist: float = data.dist
		var prog: float = data.progress
		
		var local_max_radius: float = lerp(start_radius, end_radius, prog)
		var local_strength: float = lerp(start_strength, end_strength, prog)
		
		var dist_factor: float = 1.0 - clamp(dist / local_max_radius, 0.0, 1.0)
		dist_factor = dist_factor * dist_factor
		
		var height_diff: float = (target_height - current_h)
		var total_change: float = 0.0
		
		if height_diff < 0:
			# --- 2. SLIGHTLY STRONGER EROSION ON HIGH POINTS ---
			var over_height: float = abs(height_diff)
			# Increased base multipliers and exponent for a stronger bite into mountains
			var progress_multiplier: float = lerp(1.5, 6.0, prog)
			var carving_boost: float = 1.0 + (pow(over_height, 1.8) * progress_multiplier)
			
			total_change = height_diff * dist_factor * local_strength * carving_boost
		else:
			# NERFED SEDIMENTATION: Prevent generating large, silly flatlands.
			total_change = height_diff * dist_factor * local_strength * 0.05
			
		var new_h: float = current_h + total_change
		
		# --- 1. STRICT HEIGHT CAP AFTER 'X' CELLS ---
		var current_cell_index: float = prog * river_path_size
		if current_cell_index >= x_cells_threshold:
			# Target cells strictly adjacent to the river line (dist <= 1.5 covers orthogonals + diagonals)
			if dist <= 1.5:
				# sin/cos variance calculates between -2 and +2. Multiplied by 0.02, it yields -0.04 to +0.04.
				# 0.24 +/- 0.04 gives a strict terrain cap fluctuating naturally between 0.20 and 0.28.
				var variance: float = (sin(cell.x * 0.15) + cos(cell.y * 0.15)) * 0.02
				var max_allowed: float = 0.24 + variance 
				
				# Force the height down if it exceeds the cap (but allow it to remain lower)
				if new_h > max_allowed:
					new_h = max_allowed
					
		# --- 3. HARD FLOOR AT 0.12 ---
		if total_change < 0: # Only intervene if we are actually eroding
			if current_h >= 0.12:
				# If terrain is above the floor, cap the erosion at exactly 0.12
				new_h = max(new_h, 0.12)
			else:
				# If terrain was ALREADY naturally below 0.12, do not erode it further
				new_h = current_h
				
		map_data[cell] = new_h

## Applies erosion and sedimentation based on a target height and distance from the river.
## - map_data: The global terrain dictionary.
## - valley_mask: The output from `generate_river_valley_mask`.
## - target_height: The desired ground elevation for the riverbanks (e.g., 0.20).
## - water_level: A safety floor to prevent the algorithm from filling in the ocean.
## - flatland_threshold: How far along the river's progress (0.0 to 1.0) the delta flatlands begin.
#func apply_target_height_erosion(
	#map_data: Dictionary, 
	#valley_mask: Dictionary, 
	#_ocean_mask: Dictionary[Vector2, bool],
	#target_height: float,
	#erosion_data : Dictionary[String, float],
	#water_level: float = -0.5,
	#flatland_threshold: float = 0.4
#):
	#var start_radius: float = erosion_data["start radius"]
	#var end_radius: float = erosion_data["end radius"]
	#var start_strength: float = erosion_data["start erosion"]
	#var end_strength: float = erosion_data["end erosion"]
#
	#for cell: Vector2 in valley_mask:
		#if not map_data.has(cell):
			#continue
			#
		#var current_h: float = map_data[cell]
		#
		## --- SAFETY CHECK: PRESERVE DEEP WATER ---
		#if current_h <= water_level:
			#continue
			#
		#var data: Dictionary = valley_mask[cell]
		#var dist: float = data.dist
		#var prog: float = data.progress
		#
		#var local_max_radius: float = lerp(start_radius, end_radius, prog)
		#var local_strength: float = lerp(start_strength, end_strength, prog)
		#
		#var dist_factor: float = 1.0 - clamp(dist / local_max_radius, 0.0, 1.0)
		#dist_factor = dist_factor * dist_factor
		#
		## --- 1. DYNAMIC TARGET HEIGHT (AFTER 'X') ---
		#var local_target: float = target_height
		#if prog >= flatland_threshold:
			## Create a smooth, deterministic wave pattern based on the map coordinates.
			## (sin + cos) ranges from -2 to +2. Multiplied by 0.02 = +/- 0.04 variance.
			## 0.24 +/- 0.04 = A fluctuating target exactly between 0.20 and 0.28.
			#var variance: float = (sin(cell.x * 0.15) + cos(cell.y * 0.15)) * 0.02
			#local_target = 0.24 + variance
			#
		#var height_diff: float = (local_target - current_h)
		#var total_change: float = 0.0
		#
		#if height_diff < 0:
			## --- 2. STRONGER EROSION ON HIGH POINTS ---
			#var over_height: float = abs(height_diff)
			#var progress_multiplier: float = lerp(1.0, 5.0, prog)
			#
			## Using pow(over_height, 1.5) creates exponential damage to high mountains,
			## but gentle sculpting on tiny bumps.
			#var carving_boost: float = 1.0 + (pow(over_height, 1.5) * progress_multiplier)
			#
			#total_change = height_diff * dist_factor * local_strength * carving_boost
		#else:
			## --- FIX: NERFED SEDIMENTATION ---
			## If the terrain is lower than the target, we only fill it in slightly (10% strength).
			## This completely eliminates the artificial "silly patch of lowlands" issue.
			#total_change = height_diff * dist_factor * local_strength * 0.1
			#
		#var new_h: float = current_h + total_change
		#
		## --- STRICT CEILING FOR IMMEDIATE RIVERBANKS ---
		## If we are past the threshold, and this cell is immediately adjacent to the river 
		## (distance <= 2.0 pixels), we brutally clamp it so it is NEVER higher than the local target.
		#if prog >= flatland_threshold and dist <= 2.0:
			#if new_h > local_target:
				#new_h = local_target
		#
		## --- 3. HARD FLOOR AT 0.12 ---
		#if new_h < current_h: # Only check if we actually removed terrain
			## If the terrain was ALREADY below 0.12 (e.g., 0.05), its personal floor stays 0.05.
			## Otherwise, the erosion hits a solid bedrock floor exactly at 0.12.
			#var cell_floor: float = min(current_h, 0.12)
			#if new_h < cell_floor:
				#new_h = cell_floor
				#
		#map_data[cell] = new_h
		
## Generates a perfect erosion mask expanding outward from the river.
# - stop_cells_from_end: Prevents the valley from expanding outward for the last N cells of the river.
func generate_river_valley_mask(
	river_path: Array[Vector2],
	erosion_data: Dictionary[String, float],
	stop_cells_from_end: int = 0
) -> Dictionary:
	
	var mask: Dictionary = {}
	var queue: Array[Dictionary] = []
	var path_len: int = river_path.size()
	
	if path_len == 0:
		return mask
		
	# Determine the cutoff point for expansion
	var effective_len: int = path_len - stop_cells_from_end
		
	# --- 1. SEED THE MULTI-SOURCE BFS ---
	for i in range(path_len):
		var pos: Vector2 = river_path[i]
		# Calculate how far along the river this point is (0.0 to 1.0)
		var prog: float = float(i) / float(max(1, path_len - 1))
		
		# Record the core river cell in the mask. 
		mask[pos] = {"dist": 0.0, "progress": prog}
		
		# ONLY add to the expansion queue if it is before the cutoff point.
		# This stops the valley from widening at the river's mouth.
		if i < effective_len:
			queue.append({"pos": pos, "origin": pos, "progress": prog})

	# --- 2. BFS EXPANSION ---
	var directions: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	
	# Using a 'head' index is much faster than array.pop_front() in Godot
	var head: int = 0 
	
	while head < queue.size():
		var current: Dictionary = queue[head]
		head += 1
		
		var c_pos: Vector2 = current.pos
		var origin: Vector2 = current.origin
		var c_prog: float = current.progress
		
		# Determine exactly how wide the valley is allowed to be at this specific progress point
		var local_max_radius: float = lerp(erosion_data["start radius"], erosion_data["end radius"], c_prog)
		
		for d in directions:
			var neighbor: Vector2 = c_pos + d
			
			if not mask.has(neighbor):
				# Calculate true Euclidean distance back to the original river pixel
				var dist: float = neighbor.distance_to(origin)
				
				# If we are still within the valley boundary, claim this pixel!
				if dist <= local_max_radius:
					mask[neighbor] = {"dist": dist, "progress": c_prog}
					
					# Queue the neighbor so the flood fill continues outward
					queue.append({"pos": neighbor, "origin": origin, "progress": c_prog})
					
	return mask
	
