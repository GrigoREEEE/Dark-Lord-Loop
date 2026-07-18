class_name Water_Body
extends RefCounted  

var id: String = ""
var water_type: String = ""   # "River", "Lake", "Ocean"
var all_cells: Array[Vector2] = []
var segments: Array[Region] = []
