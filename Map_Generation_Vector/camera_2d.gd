extends Camera2D

# --- Settings ---
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0

# --- Internal Variables ---
var is_dragging: bool = false
var drag_start_mouse_pos: Vector2 = Vector2.ZERO

func _unhandled_input(event):
	# 1. Handle Dragging (Middle Mouse or Right C=lick)
	if event is InputEventMouseButton:
		# Change MOUSE_BUTTON_MIDDLE to MOUSE_BUTTON_LEFT or RIGHT if you prefer
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				# Record where the mouse was in the world when we started clicking
				drag_start_mouse_pos = get_global_mouse_position()
			else:
				is_dragging = false
	
	# 2. Handle Mouse Movement (Panning)
	if event is InputEventMouseMotion and is_dragging:
		# Calculate the difference between where we clicked and where the mouse is now
		var current_mouse_pos = get_global_mouse_position()
		var offset = drag_start_mouse_pos - current_mouse_pos
		
		# Move the camera by that offset to "pull" the map
		position += offset

	# 3. Handle Zooming (Scroll Wheel)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_out()

func zoom_in():
	var target_zoom = zoom + Vector2(zoom_speed, zoom_speed)
	zoom = target_zoom.clamp(Vector2(min_zoom, min_zoom), Vector2(max_zoom, max_zoom))

func zoom_out():
	var target_zoom = zoom - Vector2(zoom_speed, zoom_speed)
	zoom = target_zoom.clamp(Vector2(min_zoom, min_zoom), Vector2(max_zoom, max_zoom))
