extends Node

class_name Ice_Wall
########################################
######### Icewall Generation ###########
########################################

func apply_ice_wall(map_data: Dictionary, width: int, noise_seed : int, res_scale : float = 1):
	var wall_base_height = int(15 * res_scale)
	var wall_variance = int(10 * res_scale)
	
	# Separate noise for the wall shape (Wobble)
	var wall_shape_noise = FastNoiseLite.new()
	wall_shape_noise.seed = noise_seed + 99
	wall_shape_noise.frequency = 0.02 / res_scale
	
	# Separate noise for the wall texture (Spikes)
	var wall_texture_noise = FastNoiseLite.new()
	wall_texture_noise.seed = noise_seed
	wall_texture_noise.frequency = 0.05 / res_scale
	
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
			map_data[Vector2(x, y)] = wall_elevation
			
	return map_data
