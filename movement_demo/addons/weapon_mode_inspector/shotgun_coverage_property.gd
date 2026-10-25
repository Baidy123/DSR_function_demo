@tool
extends EditorProperty

var distance := SpinBox.new()
var area := SpinBox.new()
var details := Label.new()
var status := Label.new()
var _read_only := false
var _undo_redo: EditorUndoRedoManager
var _watched_settings: ShotgunSettings
var _watched_pattern: ShotgunPattern


func _init() -> void:
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
	distance.tooltip_text = "规定这把枪到多远才扩散到下方面积。修改距离时面积保持不变；同样面积下距离越远，弹道越集中。"
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
	var settings := get_edited_object() as ShotgunSettings
	if settings == null: return
	if _watched_settings != settings:
		_disconnect_signals()
		_watched_settings = settings
		settings.changed.connect(_update_property)
	if _watched_pattern != settings.pattern:
		if _watched_pattern != null: _watched_pattern.changed.disconnect(_update_property)
		_watched_pattern = settings.pattern
		if _watched_pattern != null: _watched_pattern.changed.connect(_update_property)
	distance.set_value_no_signal(settings.pattern_calibration_distance_m)
	area.set_value_no_signal(settings.get_pattern_coverage_area())
	var angle := clampf(settings.pattern_angle_degrees, 0.0, ShotgunSettings.MAX_PATTERN_ANGLE_DEGREES)
	var side := 2.0 * settings.pattern_calibration_distance_m * tan(deg_to_rad(angle))
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point in settings.get_pattern_points():
		var projected := Vector2(tan(deg_to_rad(point.x * angle)), tan(deg_to_rad(point.y * angle))) * settings.pattern_calibration_distance_m
		minimum = minimum.min(projected)
		maximum = maximum.max(projected)
	var extent := maximum - minimum
	details.text = "标定处画板：%.3f × %.3f m\n固定落点：宽 %.3f × 高 %.3f m\n落点包围矩形：%.3f m²（不含随机偏移）\n图样角度尺度：%.3f°" % [side, side, extent.x, extent.y, extent.x * extent.y, angle]


func _disconnect_signals() -> void:
	if _watched_settings != null: _watched_settings.changed.disconnect(_update_property)
	if _watched_pattern != null: _watched_pattern.changed.disconnect(_update_property)
	_watched_settings = null
	_watched_pattern = null


func _exit_tree() -> void:
	_disconnect_signals()


func _distance_changed(value: float) -> void:
	var settings := get_edited_object() as ShotgunSettings
	if settings != null: _commit_calibration(value, settings.get_pattern_coverage_area())


func _area_changed(value: float) -> void:
	var settings := get_edited_object() as ShotgunSettings
	if settings != null: _commit_calibration(settings.pattern_calibration_distance_m, value)


func _commit_calibration(distance_m: float, area_m2: float) -> void:
	if _read_only: return
	var settings := get_edited_object() as ShotgunSettings
	if settings == null: return
	var angle := settings.calibration_angle_degrees(distance_m, area_m2)
	if not is_finite(angle):
		status.text = "未修改：距离须大于 0、面积须非负，且组合后的角度尺度不能超过 15°。"
		status.visible = true
		_update_property()
		return
	status.visible = false
	if distance_m == settings.pattern_calibration_distance_m and is_equal_approx(angle, settings.pattern_angle_degrees): return
	# 两个保存值属于同一条历史；撤销恢复原值，避免加载／舍入产生反向换算。
	_undo_redo.create_action("编辑霰弹散布标定", UndoRedo.MERGE_DISABLE, settings)
	_undo_redo.add_do_method(settings, "set_pattern_calibration", distance_m, area_m2)
	_undo_redo.add_undo_property(settings, "pattern_calibration_distance_m", settings.pattern_calibration_distance_m)
	_undo_redo.add_undo_property(settings, "pattern_angle_degrees", settings.pattern_angle_degrees)
	_undo_redo.add_undo_method(settings, "emit_changed")
	_undo_redo.commit_action()
	_update_property()


func _set_read_only(value: bool) -> void:
	_read_only = value
	distance.editable = not value
	area.editable = not value
