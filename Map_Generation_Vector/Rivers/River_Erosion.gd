extends Node

class_name River_Erosion

########################################
############### Erosion ################
########################################

# Modifies the map_data in-place to carve a valley around the river
func apply_river_erosion(map_data: Dictionary, river: River, start_radius: float, end_radius: float, start_strength: float, end_strength: float, res_scale : float = 1.0):
	
	end_radius = int(end_radius * res_scale)
	start_radius = int(start_radius * res_scale)
	
	# We use this to store the "Proposed Lowest Height" for cells we touch.
	# Key: Vector2, Value: Float (Height)
	var erosion_buffer = {}
	
	var path_length = river.river_path.size()
	
	for i in range(path_length):
		var center_pos = river.river_path[i]
		
		# --- 1. CALCULATE CURRENT BRUSH SETTINGS ---
		var progress = float(i) / float(path_length)
		
		# River gets WIDER as it goes South (Radius increases)
		var current_radius = lerp(start_radius, end_radius, progress)
		
		# River erosion gets WEAKER as it goes South (Strength decreases)
		# (Headwaters cut deep V-shapes; Deltas are wide and shallow)
		var current_strength = lerp(start_strength, end_strength, progress)
		
		# --- 2. ITERATE NEIGHBORS ---
		# We scan a square area around the point for efficiency
		var scan_range = int(ceil(current_radius))
		
		for dx in range(-scan_range, scan_range + 1):
			for dy in range(-scan_range, scan_range + 1):
				var neighbor = center_pos + Vector2(dx, dy)
				
				# Skip if outside map
				if not map_data.has(neighbor):
					continue
					
				# Check actual circular distance
				var dist = center_pos.distance_to(neighbor)
				if dist > current_radius:
					continue
				
				# --- 3. CALCULATE EROSION ---
				var current_elevation = map_data[neighbor]
				
				# FACTOR A: Distance Falloff
				# 1.0 at center, 0.0 at edge.
				# We use pow() to make the valley bottom rounded (bowl shape) rather than a sharp V spike.
				var dist_factor = 1.0 - (dist / current_radius)
				dist_factor = pow(dist_factor, 1.5)
				
				# FACTOR B: Elevation Scaling
				# "Erosion should be higher on cells with high elevation"
				# We multiply by elevation so mountains crumble heavily, but plains change very little.
				# We maximize with 0.1 so even sea-level land gets a tiny bit of erosion (the river bed).
				var elev_factor = max(current_elevation, 0.1)
				
				# Calculate the specific drop for this brush stroke
				var drop_amount = current_strength * dist_factor * elev_factor
				
				var target_height = current_elevation - drop_amount
				
				# --- 4. BUFFER RESULT ---
				# Since the river path overlaps itself constantly, we don't apply this yet.
				# We only want the "Deepest" cut this river makes at this spot.
				
				if erosion_buffer.has(neighbor):
					# Keep the lowest value (Strongest erosion wins)
					erosion_buffer[neighbor] = min(erosion_buffer[neighbor], target_height)
				else:
					# Initialize buffer with the existing map height if we haven't touched it yet
					# (We compare against current map data vs calculated target)
					erosion_buffer[neighbor] = min(current_elevation, target_height)

	# --- 5. COMMIT CHANGES ---
	# Now we apply the buffer to the real map
	for pos in erosion_buffer:
		map_data[pos] = erosion_buffer[pos]
