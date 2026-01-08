class_name MapGenerator_V3
extends RefCounted

func generate_heightmap(grid: Dictionary, width: int, height: int) -> Dictionary:
	var heightmap = {}
	
	var noise = FastNoiseLite.new()
	noise.seed = randi()
	# Lower frequency = smoother, more "continent-like" shapes
	noise.frequency = 0.025
	noise.fractal_octaves = 4
	
	var center = Vector2(width / 2.0, height / 2.0)
	# Use the shorter side for the radius to ensure it's a circle, not an oval
	var max_radius = min(width, height) * 0.45 
	
	for y in grid.keys():
		var row = grid[y]
		for x in range(row.size()):
			var cell_id = row[x]
			var pos = Vector2(x, y)
			
			# 1. Get raw noise (-1.0 to 1.0)
			var n = noise.get_noise_2d(x, y)
			
			# 2. Calculate Distance Gradient (0.0 at center, 1.0 at edges)
			var dist = pos.distance_to(center) / max_radius
			
			# 3. The "Continent Formula"
			# We start with land (1.0) and subtract the distance and the noise
			# This creates a solid center that gets 'chewed' by noise as it moves out
			var elevation = 1.0 - dist + (n * 0.5)
			
			# 4. Map to your -3 to 3 scale
			# -3 to 0 will be water, 0 to 3 will be land
			# We use a curve to make the transition sharper
			var final_val = remap(elevation, -0.5, 1.0, -3.0, 3.0)
			heightmap[cell_id] = clamp(final_val, -3.0, 3.0)
			
	return heightmap
