extends RefCounted
class_name MapGenerator

var noise: FastNoiseLite

func _init():
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4 # Increased octaves for more detail layers
	noise.fractal_gain = 0.5

## jaggedness: range 0.01 to 0.1 (0.02 is smooth, 0.08 is very jagged)
func generate_height_map(grid: Dictionary, width: int, height: int, land_mass: float = 1.2, variance: float = 1.0, jaggedness: float = 0.01) -> Dictionary:
	# Update the noise frequency based on desired jaggedness
	noise.frequency = jaggedness
	
	var height_map = {}
	var center = Vector2(width / 2.0, height / 2.0)
	var max_dist = min(width, height) / 2.0

	for y in grid.keys():
		var row_values = []
		for x in range(grid[y].size()):
			var n = noise.get_noise_2d(float(x), float(y))
			
			var dist_from_center = Vector2(x, y).distance_to(center)
			var normalized_dist = dist_from_center / max_dist
			var falloff = _calculate_falloff(normalized_dist)
			
			var land_bias = land_mass - 0.5
			var final_val = (n * variance) + land_bias - falloff
			
			row_values.append(_quantize_elevation(final_val))
			
		height_map[y] = row_values
		
	return height_map

func _calculate_falloff(d: float) -> float:
	var a = 3.0
	var b = 0.5 
	return pow(d, a) / (pow(d, a) + pow(b - b * d, a))

func _quantize_elevation(val: float) -> int:
	if val < -0.15: return -1
	if val < 0.2:   return 0 
	if val < 0.5:   return 1 
	if val < 0.8:   return 2 
	return 3
