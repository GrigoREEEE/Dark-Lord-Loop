extends Node

class_name Terrain_Generator


# Update your Enum to include COAST

########################################
########## World Generation ############
########################################

func generate_height_map(width: int, height: int, noise_seed : int, res_scale : float = 1) -> Dictionary:
	var map_data = {}

	
	# --- 1. TERRAIN NOISE ---
	var terrain_noise = FastNoiseLite.new()
	terrain_noise.seed = noise_seed
	terrain_noise.frequency = 0.013 / res_scale
	terrain_noise.fractal_octaves = 6 

	# --- 2. SHAPE NOISE ---
	var shape_noise = FastNoiseLite.new()
	shape_noise.seed = noise_seed + 50
	shape_noise.frequency = 0.005 / res_scale
	shape_noise.fractal_octaves = 3

	# --- PHASE 1: GENERATE CONTINENT ---
	for x in range(width):
		for y in range(height):
			var nx: float = float(x) / width
			var ny: float = float(y) / height
			
			# --- STEP 1: CALCULATE DISTORTED MASK ---
			var current_distortion_strength = lerp(0.15, 0.04, ny)
			var distortion = shape_noise.get_noise_2d(x, y) * current_distortion_strength
			var dist_x = abs(nx - 0.5) + distortion
			var land_width = lerp(0.45, 0.50, ny) 
			var shape_mask = smoothstep(land_width, land_width - 0.15, dist_x)
			
			# --- STEP 2: THE SLANT ---
			var gradient_y = 1.0 - ny
			var slant_height = pow(gradient_y, 1.5)
			
			# --- STEP 3: ELEVATION VARIANCE ---
			var h_noise = terrain_noise.get_noise_2d(x, y)
			var roughness = lerp(1.0, 0.2, ny)
			
			# --- FINAL COMBINATION ---
			var final_elevation = slant_height
			final_elevation += h_noise * roughness
			final_elevation -= (1.0 - shape_mask) * 2.0
			final_elevation = max(final_elevation, -1.0)
			
			map_data[Vector2(x, y)] = final_elevation
			
	return map_data
	
	
