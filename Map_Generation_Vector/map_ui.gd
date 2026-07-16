extends CanvasLayer

@export var map_mode_selector: OptionButton # Add this in the editor!
@export var river_mode_selector: OptionButton
@export var save_button: Button
@export var lookup_button: Button
@export var X_input: LineEdit
@export var Y_input: LineEdit
@export var map: Node2D

# River Display Mode
enum RiverDisplayMode {
	NORMAL,
	DEBUG_SEGMENTS,
	HIDDEN
}

func _ready():
	add_fps_counter()
	setup_buttons()

func add_fps_counter():
	# (Keep your existing FPS code)
	pass

func setup_buttons():
	# Setup River Mode
	river_mode_selector.add_item("Normal Rivers", RiverDisplayMode.NORMAL)
	river_mode_selector.add_item("Debug Segments", RiverDisplayMode.DEBUG_SEGMENTS)
	river_mode_selector.add_item("Hide Rivers", RiverDisplayMode.HIDDEN)
	river_mode_selector.item_selected.connect(_on_river_mode_changed)
	
	# Setup Map Mode
	if map_mode_selector:
		map_mode_selector.add_item("Terrain Mode", 0) # MapDisplayMode.TERRAIN
		map_mode_selector.add_item("Winter Climate", 1) # MapDisplayMode.WINTER_CLIMATE
		map_mode_selector.add_item("Summer Climate", 2) # MapDisplayMode.SUMMER_CLIMATE
		map_mode_selector.item_selected.connect(_on_map_mode_changed)

	save_button.pressed.connect(_on_save_button_pressed)
	lookup_button.pressed.connect(_on_check_height_button_pressed)

func _on_river_mode_changed(index: int):
	map.current_river_mode = river_mode_selector.get_item_id(index) as RiverDisplayMode
	map.update_map_visuals()

func _on_map_mode_changed(index: int):
	# Using the integer directly since it matches the MapDisplayMode enum
	map.current_map_mode = index 
	map.update_map_visuals()

func save_map_to_disk():
	# (Keep your existing save code)
	pass

func _on_save_button_pressed():
	save_map_to_disk()

func get_elevation_at(map_data: Dictionary, x: int, y: int) -> float:
	# (Keep your existing lookup code)
	var pos := Vector2(x, y)
	if map_data.has(pos):
		return map_data[pos]
	else:
		return -1.0 

func _on_check_height_button_pressed():
	var x_val: int = X_input.text.to_int()
	var y_val: int = Y_input.text.to_int()
	var pos = Vector2(x_val, y_val)
	
	var elevation: float = get_elevation_at(map.terrain_data, x_val, y_val)
	
	if elevation != -1.0:
		var output = "Pos(%d, %d) | Height: %.2f" % [x_val, y_val, elevation]
		
		# If temperature data exists, append it to the readout
		if map.temperature_data.has(pos):
			var temps = map.temperature_data[pos]
			output += " | Winter: %.1f°C | Summer: %.1f°C" % [temps.x, temps.y]
			
		print(output)
	else:
		print("Invalid coordinates!")
