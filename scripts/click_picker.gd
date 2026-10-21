extends Node

## Forwards mouse clicks on the maze (anything the HUD's own controls didn't
## consume) as world-space positions. Runs with PROCESS_MODE_ALWAYS, set in
## Main.tscn, so characters can still be inspected -- and given Guidance --
## while the game is paused.
##
## A left click is a press and release that stay within
## MapCamera.DRAG_THRESHOLD of each other: holding the button and moving
## drags the view about instead (see MapCamera), and selects nothing.
signal clicked(world_pos: Vector2)
signal right_clicked(world_pos: Vector2)

## Where the left button went down (screen pixels), while it's held.
var _left_down_at := Vector2.INF

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_down_at = event.position
			elif _left_down_at != Vector2.INF:
				var moved: float = event.position.distance_to(_left_down_at)
				_left_down_at = Vector2.INF
				if moved <= MapCamera.DRAG_THRESHOLD:
					clicked.emit(world_pos)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				right_clicked.emit(world_pos)
