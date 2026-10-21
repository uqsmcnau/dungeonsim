class_name MapCamera
extends Camera2D

## The spectator's view of the maze: the mouse wheel zooms in and out
## (towards the cursor), dragging with the left or middle mouse button moves
## the maze about, and the keyboard does both too -- WASD or the arrow keys
## to move, + and - to zoom, Home to put the view back as it started. Works
## while paused. The HUD sits on its own canvas layer, so only the maze moves.
##
## A left-button press that turns into a drag moves the view rather than
## selecting anything: ClickPicker only counts a left press and release
## that stayed within DRAG_THRESHOLD of each other as a click.

const MIN_ZOOM := 0.4
const MAX_ZOOM := 4.0
## Zoom in by this much a wheel notch (or + press); out by its inverse.
const ZOOM_STEP := 1.15
## Keyboard panning, in screen pixels a second whatever the zoom.
const KEY_PAN_SPEED := 700.0
## How far (screen pixels) a held left button has to move before it's a
## drag rather than a click.
const DRAG_THRESHOLD := 6.0
## However the view's moved, at least this much of the maze (screen pixels)
## stays on screen.
const KEEP_IN_VIEW := 120.0

## The world-space rect that has to stay partly in view (see set_bounds).
var maze_rect := Rect2()
## The part of the screen the maze is seen through, between the HUD's
## columns and toolbar (see set_view_area) -- the whole screen until told.
var view_area := Rect2()
var _home_position := Vector2.ZERO
var _home_zoom := Vector2.ONE
## The button held down for a drag, and where it went down (screen pixels).
var _drag_button := MOUSE_BUTTON_NONE
var _drag_from := Vector2.ZERO
var _dragging := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The top-left of the screen is `position`, until frame() sets the view
	# up to take the whole maze in.
	anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	_home_position = position
	_home_zoom = zoom

## The maze's world-space rect, which can't be moved wholly out of view.
func set_bounds(rect: Rect2) -> void:
	maze_rect = rect

## The part of the screen (pixels) the maze is seen through.
func set_view_area(rect: Rect2) -> void:
	view_area = rect

## Sets the view up to take all of `rect` (world space) in, centred in the
## view area, and makes that the view Home goes back to.
func frame(rect: Rect2) -> void:
	var area := _view_area()
	var z := clampf(minf(area.size.x / rect.size.x, area.size.y / rect.size.y), MIN_ZOOM, MAX_ZOOM)
	_home_zoom = Vector2(z, z)
	_home_position = rect.get_center() - area.get_center() / z
	reset_view()

## Back to the view the game started with.
func reset_view() -> void:
	position = _home_position
	zoom = _home_zoom

## Zooms by `factor` (within MIN_ZOOM..MAX_ZOOM), keeping whatever's under
## `screen_point` where it is.
func zoom_at(screen_point: Vector2, factor: float) -> void:
	var under := screen_to_world(screen_point)
	var z := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	position = under - screen_point / z
	_keep_maze_in_view()

## Moves the maze `screen_delta` pixels across the screen -- as when it's
## dragged by that much.
func pan_by(screen_delta: Vector2) -> void:
	position -= screen_delta / zoom.x
	_keep_maze_in_view()

func screen_to_world(screen_point: Vector2) -> Vector2:
	return position + screen_point / zoom.x

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion and _drag_button != MOUSE_BUTTON_NONE:
		if not _dragging and event.position.distance_to(_drag_from) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			pan_by(event.relative)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				zoom_at(_screen_middle(), ZOOM_STEP)
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_at(_screen_middle(), 1.0 / ZOOM_STEP)
			KEY_HOME:
				reset_view()

func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				zoom_at(event.position, ZOOM_STEP)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				zoom_at(event.position, 1.0 / ZOOM_STEP)
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
			# Left and right presses are left for ClickPicker too; a middle
			# drag moves the view from the first pixel.
			if event.pressed:
				_drag_button = event.button_index
				_drag_from = event.position
				_dragging = event.button_index == MOUSE_BUTTON_MIDDLE
			elif event.button_index == _drag_button:
				_drag_button = MOUSE_BUTTON_NONE
				_dragging = false

func _process(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y += 1.0
	if direction != Vector2.ZERO:
		# Moving the view right moves the maze left across the screen -- at
		# the same pace whatever the game speed (which scales `delta`).
		pan_by(-direction.normalized() * KEY_PAN_SPEED * delta / Engine.time_scale)

func _view_area() -> Rect2:
	return view_area if view_area.size != Vector2.ZERO else get_viewport_rect()

## The middle of the view area -- where the keyboard zooms towards.
func _screen_middle() -> Vector2:
	return _view_area().get_center()

## However the view's been moved, keeps at least KEEP_IN_VIEW pixels of the
## maze inside the view area.
func _keep_maze_in_view() -> void:
	if maze_rect.size == Vector2.ZERO:
		return
	var area := _view_area()
	var z := zoom.x
	var keep := KEEP_IN_VIEW / z
	position.x = clampf(position.x, maze_rect.position.x + keep - area.end.x / z, maze_rect.end.x - keep - area.position.x / z)
	position.y = clampf(position.y, maze_rect.position.y + keep - area.end.y / z, maze_rect.end.y - keep - area.position.y / z)
