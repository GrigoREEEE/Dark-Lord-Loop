extends Node

class_name WorldGenerator

# CONFIGURATION
var noise_seed: int = randi()
var frequency: float = 0.007 
var octaves: int = 4

# LAND CONTROL
var land_mass_ratio: float = 0.7 # 0.0 to 1.0

# MOUNTAIN CONTROL
# 1.0 = Linear (current look)
# 2.0 = Fewer mountains, more plains
# 4.0 = Rare, isolated peaks
var mountain_scarcity: float = 1.5 

func generate_height_map(grid: Dictionary, width: int, height: int) -> Dictionary:
	var height_map = {}
	var noise = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	
	for row_index in grid.keys():
		var row_values = grid[row_index]
		var heights_row = []
		
		for col_index in range(row_values.size()):
			var x = float(col_index)
			var y = float(row_index)
			
			# 1. Basic Noise + Mask
			var e = noise.get_noise_2d(x, y)
			var nx = 2.0 * x / (width - 1) - 1.0
			var ny = 2.0 * y / (height - 1) - 1.0
			var dist = sqrt(nx*nx + ny*ny)
			var mask = pow(dist, 3.0)
			var bias = lerp(-0.2, 0.8, land_mass_ratio)
			
			var elevation = (e + bias) - mask
			
			# 2. Mountain Scarcity (Redistribution)
			# We only want to "thin out" the land.
			if elevation > 0:
				# Raise the positive elevation to a power to make peaks rarer
				elevation = pow(elevation, mountain_scarcity)
			
			# 3. Scale to [-3, 3]
			# Note: We scale slightly differently now to ensure 
			# mountains still reach '3' even after redistribution.
			var final_height = clamp(elevation * 3.0, -3.0, 3.0)
			heights_row.append(final_height)
			
		height_map[row_index] = heights_row
		
	return height_map

#extends Node
#
#class_name WorldGenerator
#
## CONFIGURATION
#var noise_seed: int = randi()
#var frequency: float = 0.01 
#var octaves: int = 5
#
## LANDMASS CONTROL
## 0.0 = Small island/continent
## 0.5 = Large balanced continent
## 1.0 = Massive landmass filling most of the map
#var land_mass_ratio: float = 0.6 
#
#func generate_height_map(grid: Dictionary, width: int, height: int) -> Dictionary:
	#var height_map = {}
	#
	#var noise = FastNoiseLite.new()
	#noise.seed = noise_seed
	#noise.frequency = frequency
	#noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	#noise.fractal_octaves = octaves
	#
	#for row_index in grid.keys():
		#var row_values = grid[row_index]
		#var heights_row = []
		#
		#for col_index in range(row_values.size()):
			#var x = float(col_index)
			#var y = float(row_index)
			#
			## 1. Get raw noise (-1.0 to 1.0)
			#var e = noise.get_noise_2d(x, y)
			#
			## 2. Normalize coordinates for mask
			#var nx = 2.0 * x / (width - 1) - 1.0
			#var ny = 2.0 * y / (height - 1) - 1.0
			#var dist = sqrt(nx*nx + ny*ny)
			#
			## 3. Apply the Radial Mask
			## We use a power of 3.0 here to keep the center very flat 
			## so the landmass doesn't become a "peak" but a "plateau"
			#var mask = pow(dist, 3.0)
			#
			## 4. Apply Land Mass Ratio
			## We map the ratio (0 to 1) to a bias range (e.g., -0.2 to 0.8)
			#var bias = lerp(-0.2, 0.8, land_mass_ratio)
			#
			#var elevation = (e + bias) - mask
			#
			## 5. Scale to your [-3, 3] range
			#var final_height = clamp(elevation * 4.0, -3.0, 3.0)
			#heights_row.append(final_height)
			#
		#height_map[row_index] = heights_row
		#
	#return height_map
