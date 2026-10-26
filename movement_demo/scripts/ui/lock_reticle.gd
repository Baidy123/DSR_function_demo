extends Control

## 稳定度为 1.0 时准星的半径（屏幕像素）；数值越小，收拢后的准星越小。
@export var minimum_radius: float = 12.0
## 稳定度为 0.0 时准星的半径（屏幕像素）；中间稳定度在两个半径之间插值，通常不小于 Minimum Radius。
@export var maximum_radius: float = 52.0
var radius: float = 52.0
var tint: Color = Color.WHITE
var _draw_aim := false
var _headshot_ready := false
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


func _process(delta: float) -> void:
	if combat.player.is_in_dialogue or combat.player.is_dead():
		_headshot_markers.clear()
		hide()
		return
	var target = combat.locked_target
	var camera := get_viewport().get_camera_3d()
	if camera == null:
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
	_headshot_ready = false
	if _draw_aim:
		var point: Vector3 = combat.get_locked_aim_point()
		# UI 跟随渲染插值；弹道仍使用物理位置。
		point = target.get_global_transform_interpolated() * target.to_local(point)
		_draw_aim = not camera.is_position_behind(point)
		if _draw_aim:
			position = camera.unproject_position(point)
			var stability: float = combat.get_effective_accuracy()
			# 姿态影响大小；颜色与爆头菱形仍取基础收敛进度，不能因蹲下提前亮起。
			radius = lerpf(maximum_radius, minimum_radius, combat.get_spread_stability())
			tint = Color(1.0, 0.55, 0.2).lerp(Color(0.35, 1.0, 0.55), stability)
			_headshot_ready = combat.weapon != null and combat.weapon.get_headshot_chance(stability) > 0.0
	visible = _draw_aim or not _headshot_markers.is_empty()
	queue_redraw()


func _draw() -> void:
	if _draw_aim:
		# 原圆形准星继续只表示精度，不代表实际散布范围。
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.8), 4.0, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, tint, 2.0, true)
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(direction * (radius - 5.0), direction * (radius + 6.0), tint, 2.0, true)
		if _headshot_ready:
			var top := Vector2(0, -radius - 13)
			draw_polyline(PackedVector2Array([top + Vector2(0, -4), top + Vector2(4, 0), top + Vector2(0, 4), top + Vector2(-4, 0), top + Vector2(0, -4)]), HEADSHOT_COLOR, 2.0, true)
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
