extends Control

## 稳定度为 1.0 时准星的半径（屏幕像素）；数值越小，收拢后的准星越小。
@export var minimum_radius: float = 12.0
## 稳定度为 0.0 时准星的半径（屏幕像素）；中间稳定度在两个半径之间插值，通常不小于 Minimum Radius。
@export var maximum_radius: float = 52.0
## 爆头概率接近0／达到100%时，金色菱形的半尺寸（屏幕像素）。
@export_range(2.0, 20.0, 0.5) var headshot_minimum_size: float = 4.0
@export_range(2.0, 30.0, 0.5) var headshot_maximum_size: float = 10.0
var radius: float = 52.0
var tint: Color = Color.WHITE
var _draw_aim := false
var _draw_switch_target := false
var _headshot_ready := false
var _headshot_probability := 0.0
var _headshot_full_precision := false
var _headshot_size := 10.0
var _headshot_markers: Array[Dictionary] = []
const HEADSHOT_COLOR := Color(1.0, 0.8, 0.25)
const HEADSHOT_SECONDS := 0.65

@onready var combat = get_parent().get_parent()


func _ready() -> void:
	combat.headshot_resolved.connect(_on_headshot_resolved)
	combat.weapon_changed.connect(func(_weapon): _headshot_markers.clear())


func _on_headshot_resolved(point: Vector3, outcome: StringName) -> void:
	if outcome.is_empty(): return
	var label := "爆头击杀" if outcome == &"killed" else ("爆头 · 硬直" if outcome == &"staggered" else "爆头")
	_headshot_markers.append({"point": point, "remaining": HEADSHOT_SECONDS,
		"text": label, "screen": Vector2.ZERO})
	# 只保留最近的少量表现，不持有死亡目标或为每颗弹丸创建节点。
	if _headshot_markers.size() > 12: _headshot_markers.pop_front()


func _notification(what: int) -> void:
	# A paused HUD may not tick again until camera presentation has finished.
	# Hide immediately; retain timers and recompute from actual state on resume.
	if what == NOTIFICATION_PAUSED: hide()


func _process(delta: float) -> void:
	if combat.player.is_in_dialogue or combat.player.is_dead():
		_draw_aim = false
		_draw_switch_target = false
		_headshot_markers.clear()
		_headshot_ready = false
		_headshot_probability = 0.0
		_headshot_full_precision = false
		hide()
		return
	if get_tree().paused:
		hide()
		return
	var target = combat.locked_target
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_draw_aim = false
		_draw_switch_target = false
		_headshot_markers.clear()
		hide()
		return
	for index in range(_headshot_markers.size() - 1, -1, -1):
		var marker := _headshot_markers[index]
		marker.remaining -= delta
		if marker.remaining <= 0.0 or camera.is_position_behind(marker.point):
			_headshot_markers.remove_at(index)
		else:
			marker.screen = camera.unproject_position(marker.point)
	_draw_aim = combat.is_aiming and is_instance_valid(target)
	_draw_switch_target = false
	_headshot_ready = false
	_headshot_probability = 0.0
	_headshot_full_precision = false
	if _draw_aim:
		var point: Vector3 = combat.get_locked_aim_point()
		# UI 跟随渲染插值；弹道仍使用物理位置。
		point = target.get_global_transform_interpolated() * target.to_local(point)
		_draw_aim = not camera.is_position_behind(point)
		if _draw_aim:
			position = camera.unproject_position(point)
			_draw_switch_target = combat.is_turning_to_target()
			_draw_aim = not _draw_switch_target
		if _draw_aim:
			var stability: float = combat.get_effective_accuracy()
			# 姿态影响大小；颜色与爆头菱形仍取基础收敛进度，不能因蹲下提前亮起。
			radius = lerpf(maximum_radius, minimum_radius, combat.get_spread_stability())
			tint = Color(1.0, 0.55, 0.2).lerp(Color(0.35, 1.0, 0.55), stability)
			_headshot_probability = combat.get_target_headshot_chance(target)
			_headshot_ready = _headshot_probability > 0.0
			_headshot_full_precision = _headshot_ready and stability >= 1.0 - 0.000001
			_headshot_size = lerpf(maxf(headshot_maximum_size, headshot_minimum_size), headshot_minimum_size, _headshot_probability)
	visible = _draw_aim or _draw_switch_target or not _headshot_markers.is_empty()
	queue_redraw()


func _draw() -> void:
	if _draw_switch_target:
		# 小方括号只表示正在转向的下一目标，不使用准度圆或爆头菱形。
		var color := Color(0.55, 0.85, 1.0, 0.9)
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var point: Vector2 = corner * 14.0
			for offset in [Vector2(-corner.x * 6.0, 0), Vector2(0, -corner.y * 6.0)]:
				draw_line(point, point + offset, Color(0, 0, 0, 0.8), 4.0, true)
				draw_line(point, point + offset, color, 2.0, true)
		draw_string_outline(get_theme_default_font(), Vector2(-40, -22), "转向中", HORIZONTAL_ALIGNMENT_CENTER, 80, 14, 3, Color.BLACK)
		draw_string(get_theme_default_font(), Vector2(-40, -22), "转向中", HORIZONTAL_ALIGNMENT_CENTER, 80, 14, color)
	if _draw_aim:
		# 原圆形准星继续只表示精度，不代表实际散布范围。
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.8), 4.0, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, tint, 2.0, true)
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(direction * (radius - 5.0), direction * (radius + 6.0), tint, 2.0, true)
		if _headshot_ready:
			_draw_headshot_marker(Vector2(0, -radius - _headshot_size - 9.0))
	for marker in _headshot_markers:
		var center: Vector2 = marker.screen - position
		var color := HEADSHOT_COLOR
		color.a = minf(1.0, marker.remaining / 0.2)
		for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_line(center + direction * 5, center + direction * 10, Color(0, 0, 0, color.a), 5.0, true)
			draw_line(center + direction * 5, center + direction * 10, color, 2.0, true)
		var label_position := center + Vector2(-70, -22)
		draw_string_outline(get_theme_default_font(), label_position, marker.text, HORIZONTAL_ALIGNMENT_CENTER, 140, 18, 4, Color(0, 0, 0, color.a))
		draw_string(get_theme_default_font(), label_position, marker.text, HORIZONTAL_ALIGNMENT_CENTER, 140, 18, color)


func _draw_headshot_marker(center: Vector2) -> void:
	var points := PackedVector2Array()
	for direction in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		points.append(center + direction * _headshot_size)
	if _headshot_full_precision:
		# 2D柔和外光不依赖3D Bloom，兼容当前OpenGL渲染器。
		for layer in [3, 2, 1]:
			var glow := HEADSHOT_COLOR
			glow.a = 0.08 + (3 - layer) * 0.06
			draw_polyline(points, glow, 2.0 + layer * 3.0, true)
		draw_colored_polygon(points.slice(0, 4), Color(1.0, 0.9, 0.5, 0.3))
	draw_polyline(points, Color(1.0, 0.96, 0.72) if _headshot_full_precision else HEADSHOT_COLOR, 2.0, true)
