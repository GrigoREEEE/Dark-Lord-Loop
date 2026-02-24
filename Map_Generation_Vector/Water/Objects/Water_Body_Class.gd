class_name Water_Body
extends RefCounted   # or Resource if you want to serialize

var id: String = ""
var water_type: String = ""   # "River", "Lake", "Ocean"
var water_mass: Array[Vector2] = []
var is_proper: bool = true
var all_cells: Array[Vector2] = []

func get_area() -> float:
	return 0.0  # Overridden by lakes/oceans

func get_length() -> float:
	return 0.0  # Overridden by rivers
