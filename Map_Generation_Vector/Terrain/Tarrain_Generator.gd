extends Node
class_name Terrain_Generator

func generate_height_map(world_data: World_Data) -> void:
	var width: int = world_data.grid_width
	var height: int = world_data.grid_height
	var res_scale : float = world_data.res_scale
	var noise_seed : int = world_data.noise_seed
	var terrain_data: Dictionary[Vector2, float] = {}

	# --- 1. TERRAIN NOISE (Macro Hills & Valleys) ---
	var terrain_noise = FastNoiseLite.new()
	terrain_noise.seed = noise_seed
	terrain_noise.frequency = world_data.terrain_frequency["terrain"] / res_scale
	terrain_noise.fractal_octaves = world_data.terrain_octaves["terrain"] 

	# --- 2. DETAIL NOISE (Micro-bumps to deflect rivers) ---
	var detail_noise = FastNoiseLite.new()
	detail_noise.seed = noise_seed + 100
	detail_noise.frequency = world_data.terrain_frequency["detail"] / res_scale 
	detail_noise.fractal_octaves = world_data.terrain_octaves["detail"]

	# --- 3. SHAPE NOISE ---
	var shape_noise = FastNoiseLite.new()
	shape_noise.seed = noise_seed + 50
	shape_noise.frequency = world_data.terrain_frequency["shape"] / res_scale
	shape_noise.fractal_octaves = world_data.terrain_octaves["shape"]

	# --- PHASE 1: GENERATE CONTINENT ---
	for x in range(width):
		for y in range(height):
			var nx: float = float(x) / width
			var ny: float = float(y) / height
			
			# --- DOMAIN WARPING THE Y-AXIS ---
			var warp = shape_noise.get_noise_2d(x + 500, y + 500) * 0.15
			var warped_ny = clamp(ny + warp, 0.0, 1.0)
			
			# --- STEP 1: CALCULATE DISTORTED MASK ---
			var current_distortion_strength = lerp(0.15, 0.04, ny)
			var distortion = shape_noise.get_noise_2d(x, y) * current_distortion_strength
			var dist_x = abs(nx - 0.5) + distortion
			var land_width = lerp(0.45, 0.50, ny) 
			var shape_mask = smoothstep(land_width, land_width - 0.15, dist_x)
			
			# --- STEP 2: THE TARGETED SLANT ---
			var gradient_y = 1.0 - warped_ny
			
			# THE FIX: 
			# Changing the exponent to 1.3 keeps the South full and prevents sinking.
			# Multiplying by 0.85 keeps the North from plateauing into solid white peaks.
			var curve = pow(gradient_y, 1.3) 
			var slant_height = curve * 0.85
			
			# --- STEP 3: ELEVATION VARIANCE ---
			var h_noise = terrain_noise.get_noise_2d(x, y)
			var d_noise = detail_noise.get_noise_2d(x, y)
			var roughness = lerp(0.9, 0.2, ny) 
			
			# --- FINAL COMBINATION ---
			var final_elevation = slant_height
			final_elevation += h_noise * roughness
			
			# Add the micro-noise
			final_elevation += d_noise * 0.05
			
			final_elevation -= (1.0 - shape_mask) * 2.0
			final_elevation = max(final_elevation, -1.0)
			
			terrain_data[Vector2(x, y)] = final_elevation
			
	world_data.map_data["terrain"] = terrain_data
