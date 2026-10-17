extends Node

## Forwards mouse clicks on the maze (anything the HUD's own controls didn't
## consume) as world-space positions. Runs with PROCESS_MODE_ALWAYS, set in
## Main.tscn, so characters can still be inspected -- and given Guidance --
## while the game is paused.
signal clicked(world_pos: Vector2)
signal right_clicked(world_pos: Vector2)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			clicked.emit(world_pos)
		MOUSE_BUTTON_RIGHT:
			right_clicked.emit(world_pos)
