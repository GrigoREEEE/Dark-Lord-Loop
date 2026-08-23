extends Node

class_name River_Erosion

## Applies erosion and sedimentation based on a target height and distance from the river.
## - map_data: The global terrain dictionary.
## - valley_mask: The output from `generate_river_valley_mask`.
## - target_height: The desired ground elevation for the riverbanks (e.g., 0.20).
## - erosion_data: Dictionary holding radius and strength configurations.
## - river_path_size: The total length of the river (used to calculate X cells).
## - x_cells_threshold: After this many cells, adjacent banks are strictly capped.
## - water_level: A safety floor to prevent the algorithm from filling in the ocean.

func apply_target_height_erosion(
	world_data: World_Data,
	target_height: float,
	river_path_size: int,
	x_cells_threshold: int = 10,
	water_level: float = -0.5
):
	var map_data: Dictionary = world_data.map_data["terrain"]
	var valley_mask: Dictionary = world_data.mask_data["valley_outer"]
	var _ocean_mask: Dictionary = world_data.mask_data["ocean"]

	var start_radius: float = world_data.main_river_erosion["start radius"]
	var end_radius: float = world_data.main_river_erosion["end radius"]
	var start_strength: float = world_data.main_river_erosion["start erosion"]
	var end_strength: float = world_data.main_river_erosion["end erosion"]

	# --- NEW: EROSION NOISE SETUP ---
	# We use noise to break up the perfectly smooth gradient of the valley edges.
	var erosion_noise = FastNoiseLite.new()
	erosion_noise.seed = world_data.noise_seed + 777 # Offset so it doesn't match terrain peaks
	erosion_noise.frequency = 0.08 / world_data.res_scale # Tune this to change the "chunkiness" of the edges

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
		
		# --- NEW: APPLY DISTANCE WARPING ---
		# 1. Get a noise value between -1.0 and 1.0 for this specific hex
		var noise_val: float = erosion_noise.get_noise_2d(cell.x, cell.y)
		
		# 2. Scale the noise impact so the immediate riverbed (dist ~ 0) stays mostly clear, 
		# but the outer edges (dist > 1.5) get heavily randomized.
		var edge_vulnerability: float = clamp(dist / 1.5, 0.0, 1.0)
		
		# 3. Warp the perceived distance. (Multiplier controls how extreme the jaggedness is)
		var warped_dist: float = dist + (noise_val * 2.5 * edge_vulnerability)
		
		# Use the warped distance for the falloff calculation
		var dist_factor: float = 1.0 - clamp(warped_dist / local_max_radius, 0.0, 1.0)
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
			# Target cells strictly adjacent to the river line
			if dist <= 1.5:
				var variance: float = (sin(cell.x * 0.15) + cos(cell.y * 0.15)) * 0.02
				var max_allowed: float = 0.24 + variance 
				
				if new_h > max_allowed:
					new_h = max_allowed
					
		# --- 3. HARD FLOOR AT 0.12 ---
		if total_change < 0: 
			if current_h >= 0.12:
				new_h = max(new_h, 0.12)
			else:
				new_h = current_h
				
		map_data[cell] = new_h
#func apply_target_height_erosion(
	#world_data: World_Data,
	#target_height: float,
	#river_path_size: int,
	#x_cells_threshold: int = 10,
	#water_level: float = -0.5
#):
	#var map_data: Dictionary = world_data.map_data["terrain"]
	#var valley_mask: Dictionary = world_data.mask_data["valley_outer"]
	#var _ocean_mask: Dictionary = world_data.mask_data["ocean"]
#
	#var start_radius: float = world_data.main_river_erosion["start radius"]
	#var end_radius: float = world_data.main_river_erosion["end radius"]
	#var start_strength: float = world_data.main_river_erosion["start erosion"]
	#var end_strength: float = world_data.main_river_erosion["end erosion"]
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
		#var height_diff: float = (target_height - current_h)
		#var total_change: float = 0.0
		#
		#if height_diff < 0:
			## --- 2. SLIGHTLY STRONGER EROSION ON HIGH POINTS ---
			#var over_height: float = abs(height_diff)
			## Increased base multipliers and exponent for a stronger bite into mountains
			#var progress_multiplier: float = lerp(1.5, 6.0, prog)
			#var carving_boost: float = 1.0 + (pow(over_height, 1.8) * progress_multiplier)
			#
			#total_change = height_diff * dist_factor * local_strength * carving_boost
		#else:
			## NERFED SEDIMENTATION: Prevent generating large, silly flatlands.
			#total_change = height_diff * dist_factor * local_strength * 0.05
			#
		#var new_h: float = current_h + total_change
		#
		## --- 1. STRICT HEIGHT CAP AFTER 'X' CELLS ---
		#var current_cell_index: float = prog * river_path_size
		#if current_cell_index >= x_cells_threshold:
			## Target cells strictly adjacent to the river line (dist <= 1.5 covers orthogonals + diagonals)
			#if dist <= 1.5:
				## sin/cos variance calculates between -2 and +2. Multiplied by 0.02, it yields -0.04 to +0.04.
				## 0.24 +/- 0.04 gives a strict terrain cap fluctuating naturally between 0.20 and 0.28.
				#var variance: float = (sin(cell.x * 0.15) + cos(cell.y * 0.15)) * 0.02
				#var max_allowed: float = 0.24 + variance 
				#
				## Force the height down if it exceeds the cap (but allow it to remain lower)
				#if new_h > max_allowed:
					#new_h = max_allowed
					#
		## --- 3. HARD FLOOR AT 0.12 ---
		#if total_change < 0: # Only intervene if we are actually eroding
			#if current_h >= 0.12:
				## If terrain is above the floor, cap the erosion at exactly 0.12
				#new_h = max(new_h, 0.12)
			#else:
				## If terrain was ALREADY naturally below 0.12, do not erode it further
				#new_h = current_h
				#
		#map_data[cell] = new_h

		
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
		
	var effective_len: int = path_len - stop_cells_from_end
		
	# --- 1. SEED THE MULTI-SOURCE BFS ---
	for i in range(path_len):
		var pos: Vector2 = river_path[i]
		var prog: float = float(i) / float(max(1, path_len - 1))
		
		mask[pos] = {"dist": 0.0, "progress": prog}
		
		if i < effective_len:
			queue.append({"pos": pos, "origin": pos, "progress": prog})

	# --- 2. BFS EXPANSION ---
	var head: int = 0 
	
	while head < queue.size():
		var current: Dictionary = queue[head]
		head += 1
		
		var c_pos: Vector2 = current.pos
		var origin: Vector2 = current.origin
		var c_prog: float = current.progress
		
		var local_max_radius: float = lerp(erosion_data["start radius"], erosion_data["end radius"], c_prog)
		
		# FIX 1: Fetch the 6 true hex neighbors instead of 4-way directions
		var neighbors = global._get_hex_neighbors(c_pos)
		
		for neighbor in neighbors:
			if not mask.has(neighbor):
				
				# FIX 2: Convert grid positions to physical space before measuring distance
				var physical_neighbor = global._get_hex_physical_pos(neighbor)
				var physical_origin = global._get_hex_physical_pos(origin)
				
				var dist: float = physical_neighbor.distance_to(physical_origin)
				
				if dist <= local_max_radius:
					mask[neighbor] = {"dist": dist, "progress": c_prog}
					queue.append({"pos": neighbor, "origin": origin, "progress": c_prog})
					
	return mask
	
