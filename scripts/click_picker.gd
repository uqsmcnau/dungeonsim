extends Node

## Forwards left-clicks on the maze (anything the HUD's own controls didn't
## consume) as world-space positions. Runs with PROCESS_MODE_ALWAYS, set in
## Main.tscn, so characters can still be inspected while the game is paused.
signal clicked(world_pos: Vector2)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
		clicked.emit(world_pos)
