@tool
extends Control

signal points_edited(value: PackedVector2Array)

var points := PackedVector2Array()
var read_only := false
var _drag_index := -1
var _drag_start := PackedVector2Array()


func _init() -> void:
	custom_minimum_size = Vector2(220, 260)
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "左键空白处添加弹丸；拖动已有点移动；右键点删除。中心为瞄准方向，X 向右、Y 向上。"
	resized.connect(queue_redraw)


func set_points(value: PackedVector2Array) -> void:
	# 检查器定期同步同一个已提交值时，不打断尚未松开的拖动。
	if _drag_index >= 0 and value == _drag_start: return
	points = value.duplicate()
	_drag_index = -1
	queue_redraw()


func board_rect() -> Rect2:
	var side := maxf(1.0, minf(size.x, size.y) - 36.0)
	return Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)


func point_to_pixel(point: Vector2) -> Vector2:
	var rect := board_rect()
	return rect.get_center() + Vector2(point.x, -point.y) * rect.size.x * 0.5


func pixel_to_point(pixel: Vector2) -> Vector2:
	var rect := board_rect()
	var offset := (pixel - rect.get_center()) / (rect.size.x * 0.5)
	return Vector2(offset.x, -offset.y).clamp(Vector2(-1, -1), Vector2(1, 1)).snapped(Vector2(0.01, 0.01))


func _nearest(pixel: Vector2) -> int:
	var nearest := -1
	var distance := 11.0 * 11.0
	for index in points.size():
		if not points[index].is_finite(): continue
		var candidate := pixel.distance_squared_to(point_to_pixel(points[index]))
		if candidate <= distance:
			nearest = index
			distance = candidate
	return nearest


func _gui_input(event: InputEvent) -> void:
	if read_only: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if _drag_index >= 0:
				_drag_index = -1
				if points != _drag_start: points_edited.emit(points.duplicate())
				queue_redraw()
				accept_event()
			return
		if not event.pressed or not board_rect().grow(10).has_point(event.position): return
		grab_focus()
		var index := _nearest(event.position)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if index >= 0:
				points.remove_at(index)
				points_edited.emit(points.duplicate())
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if index >= 0:
				_drag_start = points.duplicate()
				_drag_index = index
			elif board_rect().has_point(event.position) and points.size() < 64:
				points.append(pixel_to_point(event.position))
				points_edited.emit(points.duplicate())
		else:
			return
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and _drag_index >= 0:
		points[_drag_index] = pixel_to_point(event.position)
		queue_redraw()
		accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _drag_index >= 0:
		points = _drag_start.duplicate()
		_drag_index = -1
		queue_redraw()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101822"))
	var rect := board_rect()
	var center := rect.get_center()
	for step in range(-4, 5):
		var offset := rect.size.x * step / 8.0
		var color := Color("536b80") if step == 0 else Color("263747")
		draw_line(Vector2(center.x + offset, rect.position.y), Vector2(center.x + offset, rect.end.y), color)
		draw_line(Vector2(rect.position.x, center.y + offset), Vector2(rect.end.x, center.y + offset), color)
	draw_rect(rect, Color("536b80"), false)
	draw_arc(center, rect.size.x * 0.5, 0, TAU, 64, Color("32495c"), 1, true)
	var font := get_theme_default_font()
	draw_string(font, Vector2(center.x + 5, rect.position.y - 4), "Y +", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("b5c5d4"))
	draw_string(font, Vector2(rect.end.x - 22, center.y - 6), "X +", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("b5c5d4"))
	for index in points.size():
		if not points[index].is_finite(): continue
		var pixel := point_to_pixel(points[index].clamp(Vector2(-1, -1), Vector2(1, 1)))
		draw_circle(pixel, 6, Color.WHITE if index == _drag_index else Color("5de0ba"), true, -1, true)
		draw_string(font, pixel + Vector2(8, -5), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("d6e5f0"))
