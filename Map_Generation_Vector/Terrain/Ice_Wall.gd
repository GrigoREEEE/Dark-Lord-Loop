extends Node

class_name Ice_Wall
########################################
######### Icewall Generation ###########
########################################

func apply_ice_wall(world_data: World_Data) -> void:
	var terrain_data: Dictionary = world_data.map_data["terrain"]
	var width: int = world_data.grid_width
	var noise_seed : int = world_data.noise_seed
	var res_scale : float = world_data.res_scale
	
	var wall_base_height = int(world_data.wall_base_height * res_scale)
	var wall_variance = int(world_data.wall_variance * res_scale)
	
	# Separate noise for the wall shape (Wobble)
	var wall_shape_noise = FastNoiseLite.new()
	wall_shape_noise.seed = noise_seed + 99
	wall_shape_noise.frequency = world_data.wall_frequency["shape"]/ res_scale
	
	# Separate noise for the wall texture (Spikes)
	var wall_texture_noise = FastNoiseLite.new()
	wall_texture_noise.seed = noise_seed
	wall_texture_noise.frequency = world_data.wall_frequency["texture"] / res_scale
	
	for x in range(width):
		# 1. Determine how tall the wall is at this specific X coordinate
		var wobble = wall_shape_noise.get_noise_2d(x, 0.0) * wall_variance
		var current_wall_height = int(wall_base_height + wobble)
		
		# 2. Overwrite the top pixels with Wall Data
		for y in range(current_wall_height):
			var n = abs(wall_texture_noise.get_noise_2d(x, y))
			
			# Height: 1.2 (Base) + Noise. Guaranteed to be higher than the land.
			var wall_elevation = 1.2 + (n * 0.5)
			
			# This simply overwrites whatever land/ocean was generated there
			terrain_data[Vector2(x, y)] = wall_elevation
			
	world_data.map_data["terrain"] = terrain_data
