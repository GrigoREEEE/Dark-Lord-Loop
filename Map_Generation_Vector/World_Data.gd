extends Resource
class_name World_Data

@export_category("Size, Seed, Noise")
@export var noise_seed: int
@export var reference_width = 400.0
@export var cell_size: int = 1
@export var grid_width: int = 400
@export var grid_height: int = 600

@export_category("Terrain Generation")
@export var terrain_frequency: Dictionary[String, float] = {
	"terrain" : 0.02,
	"detail" : 0.1,
	"shape" : 0.05
}
@export var terrain_octaves: Dictionary[String, int] = {
	"terrain" : 9,
	"detail" : 3,
	"shape" : 3
}


@export_category("South Islands Generation")

@export var belt_height: int = 150
@export var bottom_padding: int = 15
@export var side_padding: int = 60

@export var s_islands_frequency: Dictionary[String, float] = {
	"terrain" : 0.02,
	"detail" : 0.08,
	"shape" : 0.015
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
	"terrain": {}, # Cell Height Data
	"temperature": {}, # Cell Temperature Data
	"river": {}, # Cell Temperature Data
	"lake": {}
}


@export_category("Masks")
@export var mask_data: Dictionary[String, Dictionary] ={
	"ocean": {},
	"beach": {},
	"delta": {},
	"river": {},
	"vally_outer": {},
	"lake": {}
}
