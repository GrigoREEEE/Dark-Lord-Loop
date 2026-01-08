extends Area2D



func _on_mouse_entered() -> void:
	self.modulate = Color(0.478, 0.478, 0.478, 1.0)


func _on_mouse_exited() -> void:
	self.modulate = Color(1.0, 1.0, 1.0, 1.0)
