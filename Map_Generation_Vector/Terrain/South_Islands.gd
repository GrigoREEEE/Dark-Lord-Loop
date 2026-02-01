extends Node

class_name South_Islands
########################################
########## Island Generation ###########
########################################


func apply_southern_islands(map_data: Dictionary, width: int, height: int, belt_height: int, bottom_padding: int, side_padding: int, noise_seed : int, res_scale : float = 1):
	
	belt_height = int(belt_height * res_scale)
	bottom_padding = int(bottom_padding * res_scale)
	side_padding = int(side_padding * res_scale)
	
	# 1. NOISE SETUP
	var shape_noise = FastNoiseLite.new()
	shape_noise.seed = noise_seed + 200
	shape_noise.frequency = 0.015 / res_scale
	shape_noise.fractal_octaves = 3 

	var terrain_noise = FastNoiseLite.new()
	terrain_noise.seed = noise_seed
	terrain_noise.frequency = 0.02 / res_scale
	terrain_noise.fractal_octaves = 6
	
	var belt_end_y = height - bottom_padding
	var belt_start_y = belt_end_y - belt_height
	
	# --- CHANGE 1: LOOP THE FULL WIDTH ---
	# We iterate the full width so we can handle the fade logic per-pixel.
	# We rely on math to hide the islands, not the loop range.
	for x in range(width):
		for y in range(belt_start_y, belt_end_y):
			var pos = Vector2(x, y)
			
			# --- CHANGE 2: CALCULATE EDGE FADE ---
			# We measure how close we are to the nearest Left/Right edge.
			var dist_to_edge = min(x, width - x)
			
			# If we are inside the padding zone, this multiplier drops to 0.0.
			# If we are safe inside the map, it is 1.0.
			# We use a smooth transition so it looks like a natural beach slope.
			var edge_fade = smoothstep(0.0, float(side_padding), float(dist_to_edge))
			
			# --- VERTICAL MASK ---
			var belt_progress = float(y - belt_start_y) / float(belt_height)
			var belt_mask = sin(belt_progress * PI)
			
			# --- GENERATE TERRAIN ---
			var base_shape = shape_noise.get_noise_2d(x, y)
			var detail = terrain_noise.get_noise_2d(x, y)
			var elevation = (base_shape * 0.7) + (detail * 0.4)
			
			# Apply Vertical Mask (North/South fade)
			elevation *= belt_mask
			
			# --- CHANGE 3: APPLY EDGE FADE ---
			# This pushes the land underwater as it nears the left/right border.
			elevation *= edge_fade
			
			# Add offset
			elevation += 0.05 * belt_mask
			
			# --- THRESHOLD CHECK ---
			# Only write if it's actually land/beach.
			if elevation > 0.12:
				var existing_height = map_data.get(pos, -1.0)
				map_data[pos] = max(existing_height, elevation)
				
	return map_data
