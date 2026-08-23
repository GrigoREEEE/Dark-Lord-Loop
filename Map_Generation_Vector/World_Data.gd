extends Resource
class_name World_Data

@export_category("Size, Seed, Noise")
@export var noise_seed: int
@export var reference_width : float = 400.0
@export var res_scale : float = 1
@export var cell_size: int = 1
@export var grid_width: int = 400
@export var grid_height: int = 600

@export_category("Terrain Generation")
# FREQUENCY controls the "zoom level" or scale of the noise patterns.
# - INCREASING it zooms OUT: Features become smaller, more frequent, and tightly packed.
# - DECREASING it zooms IN: Features become larger, wider, and more spread out.
@export var terrain_frequency: Dictionary[String, float] = {
	# Macro Elevation (Hills, Valleys, Mountains)
	# UP: Mountain ranges and valleys become small, cramped, and chaotic.
	# DOWN: Creates massive, sweeping continental plains and wide, spanning mountain ranges.
	"terrain" : 0.015,
	# Micro-Bumps (Used for surface roughness and river deflection)
	# UP: The surface becomes covered in tiny, frequent, sharp spikes (like gravel).
	# DOWN: The micro-details smooth out into gentle, subtle undulations.
	"detail" : 0.1,
	# Continental Outline & Domain Warping
	# UP: The main landmass shatters into many small, chaotic islands and jagged peninsulas.
	# DOWN: The continent merges into a single, cohesive, massive blob of land.
	"shape" : 0.02
}

# OCTAVES control the fractal complexity (how many layers of noise are stacked together).
# - INCREASING it adds detail: Shapes become rougher, craggier, and more jagged (costs more performance).
# - DECREASING it removes detail: Shapes become smoother, rounder, and softer.
@export var terrain_octaves: Dictionary[String, int] = {
	# Main Elevation Roughness
	# Lowering this toward 1-3 turns your craggy mountains into smooth, rolling hills.
	"terrain" : 6,
	# Micro-Bump Complexity
	# Increasing this turns the micro-bumps into unpredictable, static-like noise.
	"detail" : 3,
	# Coastline & Shape Complexity
	# Increasing this makes coastlines incredibly fractured and fractal (e.g., highly complex fjords).
	"shape" : 3
}


@export_category("South Islands Generation")

@export var belt_height: int = 150
@export var bottom_padding: int = 15
@export var side_padding: int = 60

@export var s_islands_frequency: Dictionary[String, float] = {
	"terrain" : 0.03,
	"detail" : 0.1,
	"shape" : 0.02
}
@export var s_islands_octaves: Dictionary[String, int] = {
	"terrain" : 6,
	"detail" : 3,
	"shape" : 3
}

@export_category("Wall Generation")

@export var wall_base_height = 15
@export var wall_variance = 10

@export var wall_frequency: Dictionary[String, float] = {
	"shape" : 0.02,
	"texture" : 0.05,
}

@export_category("River Generation")
@export var delta_streams: Dictionary[int, int] = {3:1,2:2,1:2} #size and number of streams that form the delta
@export var bands_rivers: Dictionary[int, int] = {0:1, 1:1, 2:0, 3:0, 4:0, 5:0, 6:1, 7:1, 8:0}
@export var mouth_segments: int = 3 #number of the original main river segments that get the mouth bonus
@export var to_merge: int = 0 #number of the main river segments we merge to form delta

@export_category("Erosion")
@export var water_level: float = -0.5
@export var main_river_erosion: Dictionary[String, float] = {
	"start radius": 80.0,
	"end radius": 50.0,
	"start erosion": 0.7,
	"end erosion": 0.85
}
@export var side_river_erosion: Dictionary[String, float] = {
	"start radius": 20.0,
	"end radius": 30.0,
	"start erosion": 0.5,
	"end erosion": 0.6
}


@export_category("Map Data")
@export var map_data : Dictionary[String, Dictionary] = {
	"terrain": {}, # Cell Height Data, Vector2: float
	"temperature": {}, # Cell Temperature Data, vector2: float
	"river": {} # All rivers, vector2: region, where every vector2 is a cell that is present in river, and region is some river's region.
}



@export_category("Masks")
@export var beach_distance: int = 2
@export var mask_data: Dictionary[String, Dictionary] ={
	"ocean": {},
	"beach": {},
	"delta": {},
	"river": {},
	"valley_outer": {},
	"lake": {}
}

@export_category("Ocean")

var ocean: Water_Pool # World ocean

@export_category("River_System")
var main_river: River # Main river
var river_system: Array[River]
