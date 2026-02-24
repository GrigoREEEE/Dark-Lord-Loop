class_name Water_Pool
extends Water_Body

var regions: Array[Vector2]
var rivers_in: Array[River] = []
var rivers_out: Array[River] = []

func _init():
	water_type = "Lake"
