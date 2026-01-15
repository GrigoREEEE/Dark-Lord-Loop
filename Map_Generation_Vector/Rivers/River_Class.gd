extends Node
class_name River

var id: String          			   # e.g. "RI0001"
var river_type: String   			  # "Central", "Natural"
var source: Vector2     			   # Where it started
var mouth: Vector2       			  # Where it hit the ocean
var river_path: Array[Vector2] = [] # The list of all coordinates
var segments: Array[Array] = []     

#func _init(_id: String, _type: String, _start: Vector2):
	#id = _id
	#river_type = _type
	#source = _start
	## Path always starts with the source
	#river_path.append(source)
