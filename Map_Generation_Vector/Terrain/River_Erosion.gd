extends Node

class_name River_Erosion

# Applies erosion and sedimentation based on a target height and distance from the river.
# - map_data: The global terrain dictionary.
# - valley_mask: The output from `generate_river_valley_mask`.
# - target_height: The desired ground elevation for the riverbanks (e.g., 0.20).
# - water_level: A safety floor to prevent the algorithm from filling in the ocean.
func apply_target_height_erosion(
	map_data: Dictionary, 
	valley_mask: Dictionary, 
	_ocean_mask: Dictionary[Vector2, bool],
	target_height: float,
	erosion_data : Dictionary[String, float],
	water_level: float = -0.5
):
	var start_radius: float = erosion_data["start radius"]
	var end_radius: float = erosion_data["end radius"]
	var start_strength: float = erosion_data["start erosion"]
	var end_strength: float = erosion_data["end erosion"]
	#var ocean_cells: Array[Vector2] = _ocean_mask.keys()
	for cell: Vector2 in valley_mask:
		if not map_data.has(cell): # and not cell in ocean_cells:
			continue
			
		var current_h: float = map_data[cell]
		
		# --- SAFETY CHECK: PRESERVE DEEP WATER ---
		# Since your logic fills in lowlands, it will accidentally turn the ocean 
		# into a dirt bridge if the river gets too close. This prevents that.
		if current_h <= water_level:
			continue
			
		# Extract the pre-calculated data for this specific pixel
		var data: Dictionary = valley_mask[cell]
		var dist: float = data.dist
		var prog: float = data.progress
		
		# Calculate the max radius and max strength for this specific point along the river
		var local_max_radius: float = lerp(start_radius, end_radius, prog)
		var local_strength: float = lerp(start_strength, end_strength, prog)
		
		# --- FACTOR 1: DISTANCE FALLOFF ---
		# 1.0 at the river itself, scaling down to 0.0 at the edge of the local_max_radius.
		# We clamp it just to be mathematically safe.
		var dist_factor: float = 1.0 - clamp(dist / local_max_radius, 0.0, 1.0)
		
		# Squaring the falloff smooths the edge of the valley so it curves naturally 
		# instead of looking like a harsh V-shape.
		dist_factor = dist_factor * dist_factor
		
		# --- FACTOR 2: HEIGHT DIFFERENCE ---
		# Positive value = terrain is too low (needs dirt / sedimentation)
		# Negative value = terrain is too high (needs carving / erosion)
		var height_diff: float = (target_height - current_h)
		
		# --- APPLY THE CHANGE ---
		# The total change is proportional to the height difference, 
		# but weakened by the distance from the river and the brush strength.
		var total_change: float = height_diff * dist_factor * local_strength
		
		map_data[cell] = current_h + total_change
		
## Generates a perfect erosion mask expanding outward from the river.
# - stop_cells_from_end: Prevents the valley from expanding outward for the last N cells of the river.
func generate_river_valley_mask(
	river_path: Array[Vector2], 
	start_radius: float, 
	end_radius: float,
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
		var local_max_radius: float = lerp(start_radius, end_radius, c_prog)
		
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
	
