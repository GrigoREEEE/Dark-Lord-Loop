extends Node

class_name River_Erosion

########################################
############### Erosion ################
########################################

# Modifies the map_data in-place to carve a valley around the river
func apply_river_erosion(map_data: Dictionary, river: River, start_radius: float, end_radius: float, start_strength: float, end_strength: float, res_scale : float = 1.0):
	
	end_radius = int(end_radius * res_scale)
	start_radius = int(start_radius * res_scale)
	
	var erosion_buffer = {}
	var path_length = river.river_path.size()
	
	for i in range(path_length):
		var center_pos = river.river_path[i]
		
		# --- 1. BRUSH SETTINGS ---
		var progress = float(i) / float(path_length)
		var current_radius = lerp(start_radius, end_radius, progress)
		var current_strength = lerp(start_strength, end_strength, progress)
		
		# --- 2. ITERATE NEIGHBORS ---
		var scan_range = int(ceil(current_radius))
		
		for dx in range(-scan_range, scan_range + 1):
			for dy in range(-scan_range, scan_range + 1):
				var neighbor = center_pos + Vector2(dx, dy)
				
				if not map_data.has(neighbor): continue
				
				var dist = center_pos.distance_to(neighbor)
				if dist > current_radius: continue
				
				# --- 3. CALCULATE EROSION ---
				var current_elevation = map_data[neighbor]
				
				# SKIP if we are already at or below the safety floor
				# This preserves existing lowlands from being dug into ocean holes
				if current_elevation <= 0.16:
					continue
				
				# FACTOR A: Distance Falloff (Same as before)
				var dist_factor = 1.0 - (dist / current_radius)
				dist_factor = pow(dist_factor, 1.5)
				
				# FACTOR B: Elevation Scaling (MODIFIED)
				# 1. Base scaling: Higher ground = more erosion
				var elev_factor = max(current_elevation, 0.1)
				
				# 2. High Altitude Boost: If above 0.45, hit it harder!
				if current_elevation > 0.45:
					# We boost the effect significantly for mountains.
					# e.g., a 0.8 mountain gets eroded 2.5x harder than a plain.
					elev_factor *= 1.1 
				
				# Calculate Drop
				var drop_amount = current_strength * dist_factor * elev_factor
				var target_height = current_elevation - drop_amount
				
				# --- CRITICAL CHANGE: THE SAFETY FLOOR ---
				# We maximize against 0.16 (just above 0.15 water level).
				# This guarantees we NEVER create new ocean.
				target_height = max(target_height, 0.16)
				
				# --- 4. BUFFER RESULT ---
				if erosion_buffer.has(neighbor):
					erosion_buffer[neighbor] = min(erosion_buffer[neighbor], target_height)
				else:
					erosion_buffer[neighbor] = min(current_elevation, target_height)

	# --- 5. COMMIT CHANGES ---
	for pos in erosion_buffer:
		map_data[pos] = erosion_buffer[pos]
