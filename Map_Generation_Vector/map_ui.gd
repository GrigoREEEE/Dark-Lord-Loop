extends CanvasLayer

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
	var fps_label = Label.new()
	self.add_child(fps_label)
	fps_label.position = Vector2(10, 10)
	fps_label.modulate = Color(0, 1, 0) # Green text
	get_tree().process_frame.connect(func():
		var fps = Engine.get_frames_per_second()
		fps_label.text = "FPS: " + str(fps)
	)

func setup_buttons():
	# Setup the dropdown options
	river_mode_selector.add_item("Normal Rivers", RiverDisplayMode.NORMAL)
	river_mode_selector.add_item("Debug Segments", RiverDisplayMode.DEBUG_SEGMENTS)
	river_mode_selector.add_item("Hide Rivers", RiverDisplayMode.HIDDEN)
	river_mode_selector.item_selected.connect(_on_river_mode_changed)
	save_button.pressed.connect(_on_save_button_pressed)
	lookup_button.pressed.connect(_on_check_height_button_pressed)
	
func _on_river_mode_changed(index: int):
	map.current_river_mode = river_mode_selector.get_item_id(index) as RiverDisplayMode
	map.update_map_visuals()

func save_map_to_disk():
	if map._map_texture == null:
		print("Error: No map texture to save.")
		return

	# 1. Get the image data from the texture
	var img = map._map_texture.get_image()
	
	# 2. Ensure the directory exists
	var base_dir = "res://pictures/"
	# specific for exported games use: var base_dir = "user://pictures/"
	
	var dir = DirAccess.open("res://")
	if not dir.dir_exists(base_dir):
		# Create the directory if it doesn't exist
		var err = dir.make_dir_recursive(base_dir)
		if err != OK:
			print("Error creating directory: ", err)
			return

	# 3. Generate a unique filename using the current time
	var time = Time.get_datetime_dict_from_system()
	var filename = "map_%04d-%02d-%02d_%02d-%02d-%02d.png" % [
		time.year, time.month, time.day, 
		time.hour, time.minute, time.second
	]
	
	var full_path = base_dir + filename
	
	# 4. Save the file
	var err = img.save_png(full_path)
	
	if err == OK:
		print("Map saved successfully to: ", full_path)
		# Refresh the filesystem so the new file appears in the FileSystem dock (Editor only)
	else:
		print("Failed to save map. Error code: ", err)

func _on_save_button_pressed():
	save_map_to_disk()
	
# Retrieves the elevation data for a specific X, Y coordinate.
# Returns the elevation as a float, or -1.0 if the cell doesn't exist.
func get_elevation_at(map_data: Dictionary, x: int, y: int) -> float:
	var pos := Vector2(x, y)
	
	# Check if the coordinate actually exists in our generated map
	if map_data.has(pos):
		return map_data[pos]
	else:
		push_warning("Coordinate not found in map data: ", pos)
		return -1.0 # Return an impossible height to indicate an error

func _on_check_height_button_pressed():
	# Assuming you have two LineEdit nodes named InputX and InputY
	var x_val: int = X_input.text.to_int()
	var y_val: int = Y_input.text.to_int()
	
	var elevation: float = get_elevation_at(map.terrain_data, x_val, y_val)
	
	if elevation != -1.0:
		print("The height at (", x_val, ", ", y_val, ") is: ", elevation)
	else:
		print("Invalid coordinates!")
