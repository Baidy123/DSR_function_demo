@tool
extends EditorProperty

var distance := SpinBox.new()
var area := SpinBox.new()
var details := Label.new()
var status := Label.new()
var _read_only := false
var _undo_redo: EditorUndoRedoManager
var _watched_settings: Object
var _watched_patterns: Array[ShotgunPattern] = []
var _preview_mode := false
var _distance_field := "pattern_calibration_distance_m"
var _angle_field := "pattern_angle_degrees"


func _init(preview_mode := false) -> void:
	_preview_mode = preview_mode
	if _preview_mode:
		_distance_field = "preview_calibration_distance_m"
		_angle_field = "preview_pattern_angle_degrees"
	var bridge := EditorPlugin.new()
	_undo_redo = bridge.get_undo_redo()
	bridge.free()
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	add_child(content)
	set_bottom_editor(content)
	distance.min_value = 0.001
	distance.max_value = 1000.0
	distance.allow_greater = true
	distance.step = 0.001
	distance.suffix = "m"
	distance.tooltip_text = "规定固定图样到多远才扩散到下方面积。修改距离时面积保持不变；同样面积下距离越远，弹道越集中。"
	_add_row(content, "散布标定距离", distance)
	area.min_value = 0.0
	area.max_value = 10000.0
	area.allow_greater = true
	area.step = 0.001
	area.suffix = "m²"
	area.tooltip_text = "标定距离处整个正方形画板的面积，包含空白，不含随机偏移。修改面积时距离保持不变；同样距离下面积越小，弹道越集中。"
	_add_row(content, "标定覆盖面积", area)
	for label in [details, status]:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(label)
	status.visible = false
	distance.value_changed.connect(_distance_changed)
	area.value_changed.connect(_area_changed)


func _add_row(content: VBoxContainer, title: String, spin: SpinBox) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(spin)
	content.add_child(row)
	add_focusable(spin.get_line_edit())


func _update_property() -> void:
	var settings := get_edited_object()
	if settings == null: return
	if _watched_settings != settings:
		_disconnect_signals()
		_watched_settings = settings
		Signal(settings, "changed").connect(_update_property)
	var patterns: Array[ShotgunPattern] = []
	if _preview_mode: patterns = settings.get_patterns()
	else: patterns.append(settings.pattern)
	for previous in _watched_patterns:
		if not patterns.has(previous): previous.changed.disconnect(_update_property)
	_watched_patterns.clear()
	for pattern in patterns:
		if pattern == null or _watched_patterns.has(pattern): continue
		_watched_patterns.append(pattern)
		if not pattern.changed.is_connected(_update_property): pattern.changed.connect(_update_property)
	var distance_m: float = settings.get(_distance_field)
	distance.set_value_no_signal(distance_m)
	area.set_value_no_signal(settings.get_pattern_coverage_area())
	var angle := clampf(settings.get(_angle_field), 0.0, ShotgunSettings.MAX_PATTERN_ANGLE_DEGREES)
	var side := sqrt(settings.get_pattern_coverage_area())
	details.text = "标定处画板：%.3f × %.3f m" % [side, side]
	for index in patterns.size():
		var pattern := patterns[index]
		var title := "图样 %d" % (index + 1) if _preview_mode else "固定落点"
		if _preview_mode and pattern == null:
			details.text += "\n%s：未指定图样" % title
			continue
		var points := pattern.valid_points() if pattern != null else PackedVector2Array([Vector2.ZERO])
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for point in points:
			var projected := Vector2(tan(deg_to_rad(point.x * angle)), tan(deg_to_rad(point.y * angle))) * distance_m
			minimum = minimum.min(projected)
			maximum = maximum.max(projected)
		var extent := maximum - minimum
		details.text += "\n%s：宽 %.3f × 高 %.3f m\n落点包围矩形：%.3f m²" % [title, extent.x, extent.y, extent.x * extent.y]
	details.text += "\n不含随机偏移；图样角度尺度：%.3f°" % angle


func _disconnect_signals() -> void:
	if is_instance_valid(_watched_settings): Signal(_watched_settings, "changed").disconnect(_update_property)
	for pattern in _watched_patterns: pattern.changed.disconnect(_update_property)
	_watched_settings = null
	_watched_patterns.clear()


func _exit_tree() -> void:
	_disconnect_signals()


func _distance_changed(value: float) -> void:
	var settings := get_edited_object()
	if settings != null: _commit_calibration(value, settings.get_pattern_coverage_area())


func _area_changed(value: float) -> void:
	var settings := get_edited_object()
	if settings != null: _commit_calibration(settings.get(_distance_field), value)


func _commit_calibration(distance_m: float, area_m2: float) -> void:
	if _read_only: return
	var settings := get_edited_object()
	if settings == null: return
	var angle := ShotgunSettings.calibration_angle_degrees(distance_m, area_m2)
	if not is_finite(angle):
		status.text = "未修改：距离须大于 0、面积须非负，且组合后的角度尺度不能超过 15°。"
		status.visible = true
		_update_property()
		return
	status.visible = false
	if distance_m == settings.get(_distance_field) and is_equal_approx(angle, settings.get(_angle_field)): return
	# 两个保存值属于同一条历史；撤销恢复原值，避免加载／舍入产生反向换算。
	_undo_redo.create_action("编辑预览散布标定" if _preview_mode else "编辑霰弹散布标定", UndoRedo.MERGE_DISABLE, settings)
	_undo_redo.add_do_method(settings, "set_pattern_calibration", distance_m, area_m2)
	_undo_redo.add_undo_property(settings, _distance_field, settings.get(_distance_field))
	_undo_redo.add_undo_property(settings, _angle_field, settings.get(_angle_field))
	_undo_redo.add_undo_method(settings, "emit_signal", "changed")
	_undo_redo.commit_action()
	_update_property()


func _set_read_only(value: bool) -> void:
	_read_only = value
	distance.editable = not value
	area.editable = not value
