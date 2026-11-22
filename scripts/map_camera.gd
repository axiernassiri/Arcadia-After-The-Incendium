extends Camera2D
## Pan with WASD/arrows or by dragging (any mouse button); zoom with the wheel toward the cursor.
## Must sit after the MapView in the tree so it sees input first and can mark drags.

signal zoom_changed(z: float)

const MIN_ZOOM := 0.4
const MAX_ZOOM := 6.0
const KEY_PAN_SPEED := 900.0
const EDGE := 6.0   # px from the window edge that starts edge-scrolling (when enabled in Settings)
const Settings = preload("res://scripts/settings.gd")

var bounds := Rect2(0, 0, 2000, 1092)
var wrap_width := 0.0          # > 0: the map loops east-west every this many pixels (main.gd sets it per layer)
var focus := Vector2.INF       # where fit_bounds centres the view
var _press_pos := Vector2.ZERO
var _pressing := false
var _dragging := false


func _ready() -> void:
	make_current()
	fit_bounds()


func fit_bounds() -> void:
	var vp := get_viewport_rect().size
	var z := minf(vp.x / bounds.size.x, (vp.y - 120.0) / bounds.size.y) * 1.25
	zoom = Vector2(z, z)
	position = focus if focus != Vector2.INF and bounds.has_point(focus) else bounds.get_center()
	zoom_changed.emit(z)


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir == Vector2.ZERO and Settings.get_value("edge_scroll") and DisplayServer.window_is_focused() and not _pressing:
		var m := get_viewport().get_mouse_position()
		var vs := get_viewport_rect().size
		if Rect2(Vector2.ZERO, vs).has_point(m):
			dir.x = -1.0 if m.x < EDGE else (1.0 if m.x > vs.x - EDGE else 0.0)
			dir.y = -1.0 if m.y < EDGE else (1.0 if m.y > vs.y - EDGE else 0.0)
	if dir != Vector2.ZERO and not (get_viewport().gui_get_focus_owner() is LineEdit):
		position += dir.normalized() * KEY_PAN_SPEED * delta / zoom.x
		_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and get_viewport().gui_get_hovered_control() != null:
		return   # never start a zoom or drag on top of a panel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(1.15, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(1.0 / 1.15, event.position)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if event.pressed and event.shift_pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_pressing = false   # shift + left-drag draws a selection box (map_view.gd), not a pan
			elif event.pressed:
				_pressing = true
				_dragging = false
				_press_pos = event.position
			else:
				if _dragging:
					event.set_meta("dragged", true)
				_pressing = false
				_dragging = false
	elif event is InputEventMouseMotion and _pressing:
		if not _dragging and event.position.distance_to(_press_pos) > 6.0:
			_dragging = true
		if _dragging:
			position -= event.relative / zoom.x
			_clamp()


func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var half := get_viewport_rect().size / 2.0
	var world := position + (screen_pos - half) / zoom.x
	var z := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	position = world - (screen_pos - half) / z
	_clamp()
	zoom_changed.emit(z)


func _clamp() -> void:
	if wrap_width > 0.0:
		# east-west the world loops: keep x inside one copy (the copies either side look the same)
		position = Vector2(fposmod(position.x, wrap_width), clampf(position.y, bounds.position.y, bounds.end.y))
	else:
		position = position.clamp(bounds.position, bounds.end)
