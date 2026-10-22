extends CanvasLayer

## Display existing coordinator values, never calculate or submit a movement plan.
const REFRESH_SECONDS := 0.1
const LEVELS := ["仅视野共享", "战术配合", "强配合"]
const ACTIONS := {&"none": "无动作", &"engage": "接敌", &"search": "调查搜索", &"cover": "掩体行动",
	&"reload": "换弹行动", &"cooperate": "协作行动", &"suppression": "压制", &"patrol": "巡逻"}
const COLORS := [Color("55dcff"), Color("ffcf5c"), Color("e196ff"), Color("79e6a4"), Color("ff9696"), Color("a6b9ff")]
const WORDS := {&"approach": "接近站位", &"crossing": "共同检查", &"preparing": "规划中",
	&"assigning": "切换任务", &"staging": "集结", &"executing": "执行",
	&"moving": "移动", &"waiting": "等待", &"blocked": "受阻", &"arrived": "到位",
	&"complete": "完成", &"unaccepted": "切换动作", &"unavailable": "暂不可用",
	&"self_preservation": "紧急自保", &"assembly_barrier": "等待全员到位", &"observing": "观察",
	&"repair": "调整通路", &"yield": "让路", &"occupied": "身体挡路", &"passage_order": "通行顺序",
	&"physical_motion": "实际移动受阻", &"static_obstacle": "障碍挡路", &"static_crossing": "绕角受阻",
	&"planning": "分配岗位", &"unassigned": "尚未分配", &"reloading": "实际换弹中",
	&"execution_busy": "执行占用", &"awaiting_candidates": "等待可行候选",
	&"execution_valid": "保留有效岗位", &"prepared_combat_member": "补充分工",
	&"complementary_offers": "分配互补岗位", &"repair_unavailable": "当前布局需重排",
	&"no_complete_combination": "缺少兼容岗位", &"search_slots_pending": "搜索站位未齐"}
var snapshots: Array[Dictionary] = []
var refresh_count := 0
var _elapsed := 0.0
var _canvas: Control
var _settings: Node
var _background: StyleBoxFlat

func _ready() -> void:
	layer = 9
	_background = StyleBoxFlat.new()
	_background.bg_color = Color(0.025, 0.035, 0.05, 0.87)
	_background.set_corner_radius_all(5)
	_canvas = Control.new()
	_canvas.name = "Overlay"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_overlay)
	_settings = get_parent()
	_settings.changed.connect(_apply_debug_mode)
	_apply_debug_mode(_settings.enabled)

func _apply_debug_mode(enabled: bool) -> void:
	set_process(enabled)
	_canvas.visible = enabled
	_elapsed = 0.0
	if not enabled: snapshots.clear()
	_canvas.queue_redraw()

func _process(delta: float) -> void:
	_elapsed -= delta
	if _elapsed > 0.0: return
	_elapsed = REFRESH_SECONDS
	snapshots.clear()
	for actor in get_tree().get_nodes_in_group("combat_target"):
		var ai := actor.get_node_or_null("AI")
		if ai == null or not ai.get("context") is RefCounted: continue
		var value: Dictionary = ai.context.coordination_debug_snapshot()
		if value.is_empty(): continue
		value.member_path = str(actor.get_path())
		snapshots.append(value)
	snapshots.sort_custom(func(a, b): return a.member_path < b.member_path)
	refresh_count += 1
	_canvas.queue_redraw()

func _draw_overlay() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or snapshots.is_empty(): return
	var names := {}
	for value in snapshots: names[value.actor_id] = value.name
	var panel_width := minf(350.0, get_viewport().get_visible_rect().size.x * 0.38)
	var panel_position := Vector2(get_viewport().get_visible_rect().size.x - panel_width - 16.0, 82.0)
	_canvas.draw_style_box(_background, Rect2(panel_position, Vector2(panel_width, 64.0 + snapshots.size() * 67.0)))
	_text(panel_position + Vector2(10, 20), "实际行动 / 小队任务 · 每人一种颜色", Color.WHITE, 15)
	_text(panel_position + Vector2(10, 39), "实线：当前路线   虚线：后续路线", Color.LIGHT_GRAY, 13)
	_text(panel_position + Vector2(10, 56), "方框：准备位   ×：检查目标   橙线：等队友", Color.LIGHT_GRAY, 13)
	for index in snapshots.size():
		var value := snapshots[index]
		var color: Color = COLORS[index % COLORS.size()]
		_route(camera, value.get("route", PackedVector3Array()), color, false)
		_route(camera, value.get("next_route", PackedVector3Array()), Color(color, 0.55), true)
		_marker(camera, value.position, color, "circle")
		_marker(camera, value.get("staging_position", Vector3.INF), color, "square", value.name + " 准备")
		_marker(camera, value.get("target_position", Vector3.INF), color, "cross", value.name + " 目标")
		var goal: Vector3 = value.get("goal", Vector3.INF)
		if goal.is_finite() and goal != value.get("staging_position") and goal != value.get("target_position"):
			_marker(camera, goal, color, "square", value.name + " 让路位")
		if value.get("source") in [&"personal", &"pending"]:
			_marker(camera, value.get("personal_goal", Vector3.INF), Color.GRAY, "cross", value.name + " 个人目标")
		for id: int in value.get("waiting_for", []):
			for other in snapshots:
				if other.actor_id == id:
					_line(camera, value.position, other.position, Color("ff8b40"), true)
		var row := panel_position + Vector2(10, 78 + index * 67)
		_text(row, "%s  %s" % [value.name, _task_label(value)], color, 14)
		_text(row + Vector2(0, 19), _execution_label(value), Color.WHITE, 13)
		var waiting: Array[String] = []
		for id: int in value.get("waiting_for", []): waiting.append(str(names.get(id, id)))
		var detail: String = _word(value.get("reason", &""))
		if not waiting.is_empty(): detail += " 等 " + ", ".join(waiting)
		if value.get("source") == &"personal": detail = "无团队任务 · 个人自主选择"
		elif value.get("source") == &"pending": detail = "规划：" + _word(value.get("planning_reason", &"awaiting_candidates"))
		else:
			detail = "%s · %s" % [_word(value.get("phase", &"")), detail]
			detail += "  剩余 %.1fs" % value.get("remaining_seconds", 0.0)
		_text(row + Vector2(0, 37), detail, Color("ffbd82") if not waiting.is_empty() else Color.LIGHT_GRAY, 12)

func _task_label(value: Dictionary) -> String:
	var level: String = LEVELS[clampi(int(value.get("cooperation_level", 0)), 0, 2)]
	if value.get("source") == &"inspection": return "%s · 搜查 #%s" % [level, value.get("order_id", 0)]
	if value.get("source") == &"assignment":
		var kind := "建议" if value.get("constraint_mode") == &"advisory" else "任务"
		return "%s · %s #%s · %s" % [level, kind, value.get("assignment_id", 0), "已接受" if value.get("accepted", false) else "未接受"]
	if value.get("source") == &"pending": return level + " · 规划中"
	return level + " · 个人"

func _execution_label(value: Dictionary) -> String:
	var action: StringName = value.get("action", &"none")
	var body := "移动中" if value.get("moving", false) else "原地"
	if value.get("reloading", false): body += " · 换弹剩余 %.1fs" % value.get("reload_remaining", 0.0)
	return "实际：%s · %s" % [ACTIONS.get(action, str(action)), body]

func _word(value: StringName) -> String:
	return WORDS.get(value, str(value))

func _route(camera: Camera3D, points: PackedVector3Array, color: Color, dashed: bool) -> void:
	for index in range(1, points.size()): _line(camera, points[index - 1], points[index], color, dashed)

func _line(camera: Camera3D, start: Vector3, end: Vector3, color: Color, dashed: bool) -> void:
	if not start.is_finite() or not end.is_finite(): return
	start += Vector3.UP * 0.12
	end += Vector3.UP * 0.12
	if camera.is_position_behind(start) or camera.is_position_behind(end): return
	var a := camera.unproject_position(start)
	var b := camera.unproject_position(end)
	if dashed: _canvas.draw_dashed_line(a, b, color, 1.5, 6.0)
	else:
		_canvas.draw_line(a, b, Color(0, 0, 0, 0.8), 4.5, true)
		_canvas.draw_line(a, b, color, 2.5, true)
		if a.distance_to(b) > 18.0:
			var tip := a.lerp(b, 0.7)
			var direction := (b - a).normalized()
			_canvas.draw_line(tip, tip - direction.rotated(0.5) * 8.0, color, 2.0, true)
			_canvas.draw_line(tip, tip - direction.rotated(-0.5) * 8.0, color, 2.0, true)

func _marker(camera: Camera3D, point: Vector3, color: Color, shape: String, label: String = "") -> void:
	if not point.is_finite() or camera.is_position_behind(point): return
	var screen := camera.unproject_position(point + Vector3.UP * 0.15)
	match shape:
		"square": _canvas.draw_rect(Rect2(screen - Vector2(5, 5), Vector2(10, 10)), color, false, 2.0)
		"cross":
			_canvas.draw_line(screen - Vector2(5, 5), screen + Vector2(5, 5), color, 2.0, true)
			_canvas.draw_line(screen - Vector2(-5, 5), screen + Vector2(-5, 5), color, 2.0, true)
		_: _canvas.draw_circle(screen, 5, color)
	if not label.is_empty(): _text(screen + Vector2(8, -7), label, color, 12)

func _text(point: Vector2, value: String, color: Color, size: int) -> void:
	var font := _canvas.get_theme_default_font()
	_canvas.draw_string_outline(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, 0.9))
	_canvas.draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
