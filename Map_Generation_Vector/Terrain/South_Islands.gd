extends Node

class_name South_Islands
########################################
########## Island Generation ###########
########################################


func apply_southern_islands(world_data: World_Data) -> void:
	var terrain_data: Dictionary = world_data.map_data["terrain"]
	var width: int = world_data.grid_width
	var height: int = world_data.grid_height
	var belt_height: int = world_data.belt_height
	var bottom_padding: int = world_data.bottom_padding
	var side_padding: int = world_data.side_padding
	var noise_seed : int = world_data.noise_seed
	var res_scale : float = world_data.res_scale
	
	belt_height = int(belt_height * res_scale)
	bottom_padding = int(bottom_padding * res_scale)
	side_padding = int(side_padding * res_scale)
	
	# 1. NOISE SETUP
	var shape_noise = FastNoiseLite.new()
	shape_noise.seed = noise_seed + 200
	shape_noise.frequency = world_data.s_islands_frequency["shape"]/ res_scale
	shape_noise.fractal_octaves = world_data.s_islands_octaves["shape"]

	var terrain_noise = FastNoiseLite.new()
	terrain_noise.seed = noise_seed
	terrain_noise.frequency = world_data.s_islands_frequency["terrain"] / res_scale
	terrain_noise.fractal_octaves = world_data.s_islands_octaves["terrain"]

	var detail_noise = FastNoiseLite.new()
	detail_noise.seed = noise_seed + 300
	detail_noise.frequency = world_data.s_islands_frequency["detail"] / res_scale # High frequency for micro-bumps
	detail_noise.fractal_octaves = world_data.s_islands_octaves["terrain"]
	
	var belt_end_y = height - bottom_padding
	var belt_start_y = belt_end_y - belt_height
	
	for x in range(width):
		for y in range(belt_start_y, belt_end_y):
			var pos = Vector2(x, y)
			
			# --- NEW: DOMAIN WARPING ---
			# We use the shape noise (sampled far away) to push the X and Y coordinates around.
			# This creates a "wiggle" in the math so the island chain isn't a perfect straight line.
			var warp_x = shape_noise.get_noise_2d(x + 1000, y + 1000) * (20.0 * res_scale)
			var warp_y = shape_noise.get_noise_2d(x - 1000, y - 1000) * (20.0 * res_scale)
			
			var warped_x = clamp(x + warp_x, 0.0, width)
			var warped_y = y + warp_y
			
			# --- CALCULATE EDGE FADE (Using Warped X) ---
			var dist_to_edge = min(warped_x, width - warped_x)
			var edge_fade = smoothstep(0.0, float(side_padding), float(dist_to_edge))
			
			# --- VERTICAL MASK (Using Warped Y) ---
			var belt_progress = float(warped_y - belt_start_y) / float(belt_height)
			# Clamp is critical here because warping might push progress slightly outside 0 to 1,
			# and sin() of negative numbers would carve inverse holes in the ocean.
			belt_progress = clamp(belt_progress, 0.0, 1.0) 
			var belt_mask = sin(belt_progress * PI)
			
			# --- GENERATE TERRAIN ---
			var base_shape = shape_noise.get_noise_2d(x, y)
			var detail = terrain_noise.get_noise_2d(x, y)
			var d_noise = detail_noise.get_noise_2d(x, y)
			
			var elevation = (base_shape * 0.7) + (detail * 0.4)
			
			# Apply Vertical Mask (North/South fade)
			elevation *= belt_mask
			
			# Apply Edge Fade (East/West fade)
			elevation *= edge_fade
			
			# --- NEW: APPLY MICRO-NOISE ---
			# We add the micro-noise scaled down so it just textures the surface
			elevation += d_noise * 0.05
			
			# Add offset so islands actually peek out of the water
			elevation += 0.05 * belt_mask
			
			# --- THRESHOLD CHECK ---
			if elevation > 0.12:
				var existing_height = terrain_data.get(pos, -1.0)
				terrain_data[pos] = max(existing_height, elevation)
				
	world_data.map_data["terrain"] = terrain_data
