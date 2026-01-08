extends Node

class_name WorldGeneratorVector

# CONFIGURATION
@export var noise_seed: int = randi()
@export var frequency: float = 0.007 
@export var octaves: int = 4

# LAND CONTROL
@export_range(0.0, 1.0) var land_mass_ratio: float = 0.6 

# MOUNTAIN CONTROL
@export var mountain_scarcity: float = 1.5 

# Update your Enum to include COAST
enum LandType {
	DEEP_WATER = 1,
	SHALLOW_WATER = 2,
	LOWS = 3,
	PLAINS = 4,
	HILLS = 5,
	MOUNTAINS = 6,
	LAKE = 7,
	RIVER = 8
}

########################################
########## World Generation ############
########################################
func generate_height_map(width: int, height: int) -> Dictionary:
	var height_map: Dictionary = {} # Will store Dictionary[Vector2, float]
	
	var noise = FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	
	# Iterate through every cell in the grid
	for y in range(height):
		for x in range(width):
			# 1. Basic Noise + Mask
			var e = noise.get_noise_2d(float(x), float(y))
			
			# Normalize coordinates to [-1, 1] for the circular mask
			var nx = 2.0 * x / (width - 1) - 1.0
			var ny = 2.0 * y / (height - 1) - 1.0
			var dist = sqrt(nx*nx + ny*ny)
			
			# Circular mask to ensure an island shape
			var mask = pow(dist, 3.0)
			var bias = lerp(-0.2, 0.8, land_mass_ratio)
			
			var elevation = (e + bias) - mask
			
			# 2. Mountain Scarcity (Redistribution)
			if elevation > 0:
				elevation = pow(elevation, mountain_scarcity)
			
			# 3. Scale and Clamp
			# Mapping the result to a usable height range
			var final_height = clamp(elevation * 3.0, -3.0, 3.0)
			
			# 4. Store using Vector2 as the key
			height_map[Vector2(x, y)] = final_height
			
	return height_map
	
########################################
########## World Elevation #############
########################################

# Configuration: How much base height to add per cell type
const TERRAIN_BOOST = {
	3: 0.3, # Coastlines: Small bump to get just above 0
	4: 0.5, # Grass/Forest: Moderate lift
	5: 1.2, # Hills: Significant lift
	6: 2.5, # Mountains: Massive lift
	7: 0.4  # Lakes: Lifted to be shallower than deep ocean, but lower than land
}

# Configuration: "The higher the place, the more elevation it gets"
# 0.2 means we add 20% of the current positive elevation on top of the base boost
const HEIGHT_SCALING_FACTOR = 0.25 

func apply_terrain_elevation(world_data: Dictionary, elevation_data: Dictionary) -> Dictionary:
	
	# Duplicate the elevation map so we don't destructively edit the original input
	# Note: in Godot 4 typed dictionaries, you might need to cast or init specifically
	# if strict typing is enforced, but .duplicate() usually preserves the internal structure.
	var new_elevation: Dictionary = elevation_data.duplicate()
	
	for pos: Vector2 in world_data:
		var cell_type: int = world_data[pos]
		
		# Skip Ocean types (1 and 2)
		if not TERRAIN_BOOST.has(cell_type):
			continue
			
		var current_h: float = new_elevation.get(pos, -3.0)
		var base_boost: float = TERRAIN_BOOST[cell_type]
		
		# Calculate the non-uniform scaler
		# We use max(0.0, current_h) so we don't accidentally multiply 
		# negative depths for lakes (which would lower them further).
		var height_bonus: float = maxf(0.0, current_h) * HEIGHT_SCALING_FACTOR
		
		# Special handling for Lakes (Type 7)
		# Lakes often generate at negative noise values. 
		# We might want to force them closer to sea level (0.0) before applying the boost.
		var final_h: float
		if cell_type == 7:
			# If it's a lake and deep, clamp it to a minimum "shallow" level before boosting
			# This ensures lakes aren't -3.0 deep.
			var lake_base = maxf(current_h, -0.5) 
			final_h = lake_base + base_boost
		else:
			final_h = current_h + base_boost + height_bonus
		
		# Clamp to valid range if necessary (optional, but good for safety)
		new_elevation[pos] = clampf(final_h, -3.0, 3.0)
		
	return new_elevation
