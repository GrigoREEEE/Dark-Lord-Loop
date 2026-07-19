extends Node
class_name Terrain_Generator

func generate_height_map(width: int, height: int, noise_seed : int, res_scale : float = 1) -> Dictionary[Vector2, float]:
	var map_data: Dictionary[Vector2, float] = {}

	# --- 1. TERRAIN NOISE (Macro Hills & Valleys) ---
	var terrain_noise = FastNoiseLite.new()
	terrain_noise.seed = noise_seed
	terrain_noise.frequency = 0.02 / res_scale
	terrain_noise.fractal_octaves = 9 

	# --- NEW: DETAIL NOISE (Micro-bumps to deflect rivers) ---
	var detail_noise = FastNoiseLite.new()
	detail_noise.seed = noise_seed + 100
	# High frequency creates small, jagged bumps
	detail_noise.frequency = 0.1 / res_scale 
	detail_noise.fractal_octaves = 3

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
			
			# --- NEW: DOMAIN WARPING THE Y-AXIS ---
			var warp = shape_noise.get_noise_2d(x + 500, y + 500) * 0.15
			var warped_ny = clamp(ny + warp, 0.0, 1.0)
			
			# --- STEP 1: CALCULATE DISTORTED MASK ---
			var current_distortion_strength = lerp(0.15, 0.04, ny)
			var distortion = shape_noise.get_noise_2d(x, y) * current_distortion_strength
			var dist_x = abs(nx - 0.5) + distortion
			var land_width = lerp(0.45, 0.50, ny) 
			var shape_mask = smoothstep(land_width, land_width - 0.15, dist_x)
			
			# --- STEP 2: THE WARPED SLANT ---
			var gradient_y = 1.0 - warped_ny
			
			# REDUCED NORTHERN SLOPE:
			# Multiplying by 0.75 drops the maximum base height of the North,
			# while the South remains completely untouched (since 0.0 * 0.75 = 0.0).
			var slant_height = pow(gradient_y, 1.5) * 0.75
			
			# --- STEP 3: ELEVATION VARIANCE ---
			var h_noise = terrain_noise.get_noise_2d(x, y)
			var d_noise = detail_noise.get_noise_2d(x, y)
			
			# You can also slightly tame the northern roughness if it's still too spiked
			var roughness = lerp(0.9, 0.2, ny) 
			
			# --- FINAL COMBINATION ---
			var final_elevation = slant_height
			final_elevation += h_noise * roughness
			
			# Add the micro-noise
			final_elevation += d_noise * 0.05
			
			final_elevation -= (1.0 - shape_mask) * 2.0
			final_elevation = max(final_elevation, -1.0)
			
			map_data[Vector2(x, y)] = final_elevation
			
	return map_data
