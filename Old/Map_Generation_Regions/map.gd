extends Node2D

const SIMPLE_COLORS : Array[String] = [
	"#000000", "#000033", "#000066", "#000099", "#0000cc", "#0000ff",
	"#003300", "#003333", "#003366", "#003399", "#0033cc", "#0033ff",
	"#006600", "#006633", "#006666", "#006699", "#0066cc", "#0066ff",
	"#009900", "#009933", "#009966", "#009999", "#0099cc", "#0099ff",
	"#00cc00", "#00cc33", "#00cc66", "#00cc99", "#00cccc", "#00ccff",
	"#00ff00", "#00ff33", "#00ff66", "#00ff99", "#00ffcc", "#00ffff",
	"#330000", "#330033", "#330066", "#330099", "#3300cc", "#3300ff",
	"#333300", "#333333", "#333366", "#333399", "#3333cc", "#3333ff",
	"#336600", "#336633", "#336666", "#336699", "#3366cc", "#3366ff",
	"#339900", "#339933", "#339966", "#339999", "#3399cc", "#3399ff",
	"#33cc00", "#33cc33", "#33cc66", "#33cc99", "#33cccc", "#33ccff",
	"#33ff00", "#33ff33", "#33ff66", "#33ff99", "#33ffcc", "#33ffff",
	"#660000", "#660033", "#660066", "#660099", "#6600cc", "#6600ff",
	"#663300", "#663333", "#663366", "#663399", "#6633cc", "#6633ff",
	"#666600", "#666633", "#666666", "#666699", "#6666cc", "#6666ff",
	"#669900", "#669933", "#669966", "#669999", "#6699cc", "#6699ff",
	"#66cc00", "#66cc33", "#66cc66", "#66cc99", "#66cccc", "#66ccff",
	"#66ff00", "#66ff33", "#66ff66", "#66ff99", "#66ffcc", "#66ffff"
]

### Manager & Refinement node
###################### ACCESS NODES ###################### 
@export var regions_access : Node2D # where the regions are stored
@export var battlefield_access : Node2D # reverse access to the manager of the whole battlefield
@export var area_access : Sprite2D # access to the sprite that maps out the regions
@export var biomes_access : Sprite2D # access to the sprite that maps out the regions 
@export var water_access : Sprite2D # access to the sprite that maps out the regions 
@export var map_builder_access : Node2D # access to the map builder
########################################################## 
###################### MANAGEMENT NODES ##################
var regions : Dictionary[String,int]
var neighbours : Dictionary[Area2D, Array]
########################################################## 
###################### MANAGEMENT NODES ##################
#var area_points : Array[Vector2]
#var biome_points : Array[Vector2]
#var water_points : Array[Vector2]
########################################################## 

var texture_size : Vector2 = Vector2(512,512)
var min_radius : float = 20
var max_radius : float = 30

func _ready():
	randomize()
	var area_points : Array[Vector2] = PoissonDiskSampler.generate_poisson_disk_samples(texture_size.x, texture_size.y, min_radius, max_radius)
	var area_neighbours : Dictionary[Vector2, Array] = DelaunayVoronoi.get_voronoi_neighbors(area_points)
	randomize()
	var biome_points : Array[Vector2] = PoissonDiskSampler.generate_poisson_disk_samples(texture_size.x, texture_size.y, 30, 40)

	var VG = Voronoi_Generator.new()
	VG.generate_voronoi_diagram(area_points, area_access, texture_size, "area") #creates the zones of the Areas
	VG = Voronoi_Generator.new()
	VG.generate_voronoi_diagram(biome_points, biomes_access, texture_size, "biome") #creates the zones of the Biomes
