extends Camera2D

var dragging = false
var drag_start_position = Vector2()

func _unhandled_input(event):
	# 1. Check if the drag button (e.g., Middle Mouse) is pressed
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			dragging = true
			drag_start_position = get_global_mouse_position()
		else:
			dragging = false
	
	# 2. Move the camera if dragging
	if event is InputEventMouseMotion and dragging:
		# Calculate how far we moved the mouse
		var current_mouse_position = get_global_mouse_position()
		var ofst = drag_start_position - current_mouse_position
		
		# Apply the offset to the camera position
		position += ofst
