@tool
extends Control

signal changed

const Ballistics = preload("res://scripts/weapons/shotgun_ballistics.gd")

# 与预览原角度一起保存。加载只恢复值，不因字段顺序重新标定。
@export_storage var preview_calibration_distance_m: float = 4.0

@export_group("预览图样（三个独立槽位）")
## 左侧图样。拖入 ShotgunPattern .tres；留空显示空面板，不会覆盖图样文件。
@export var pattern_1: ShotgunPattern:
	set(value):
		pattern_1 = value
		_queue_refresh()
## 中间图样；可与其他槽引用同一图样。
@export var pattern_2: ShotgunPattern:
	set(value):
		pattern_2 = value
		_queue_refresh()
## 右侧图样；三个面板共用下方预览数值。
@export var pattern_3: ShotgunPattern:
	set(value):
		pattern_3 = value
		_queue_refresh()

@export_group("独立预览参数（不影响实际武器）")
## 完全稳定时，每颗弹丸的最大随机偏移角。只影响此预览，0 可观察准确固定落点。
@export_range(0.0, 5.0, 0.01, "suffix:°") var preview_stable_jitter_degrees: float = 0.08:
	set(value):
		preview_stable_jitter_degrees = clampf(value, 0.0, 5.0)
		_queue_refresh()
## 完全不稳定时的最大随机偏移角。沿原采样规则，不小于完全稳定时的有效偏移。
@export_range(0.0, 5.0, 0.01, "suffix:°") var preview_unstable_jitter_degrees: float = 0.55:
	set(value):
		preview_unstable_jitter_degrees = clampf(value, 0.0, 5.0)
		_queue_refresh()
## 三栏共用的固定图样尺度；检查器用独立距离／面积标定，保存时保留原角度。
@export_range(0.0, 15.0, 0.05, "suffix:°") var preview_pattern_angle_degrees: float = 3.0:
	set(value):
		preview_pattern_angle_degrees = clampf(value, 0.0, 15.0)
		_queue_refresh()
## 编辑器与 F6 的初始稳定度。运行时滑块只改变本次预览，不自动保存回场景。
@export_range(0.0, 1.0, 0.01) var preview_initial_stability: float = 1.0:
	set(value):
		preview_initial_stability = clampf(value, 0.0, 1.0)
		if is_node_ready(): stability = preview_initial_stability
		_queue_refresh()
## 观察同一弹道在此距离的截面。只改变显示，不是枪械的散布标定距离。
@export_range(0.1, 1000.0, 0.1, "or_greater", "suffix:m") var preview_distance_m: float = 10.0:
	set(value):
		if not is_finite(value): return
		preview_distance_m = maxf(0.1, value)
		if is_node_ready(): distance_m = preview_distance_m
		_queue_refresh()

var stability: float = 1.0
var distance_m: float = 10.0
var shots: Array[PackedVector2Array] = []
var rng := RandomNumberGenerator.new()
var status: Label
var _settings := ShotgunSettings.new()
var _watched_patterns: Array[ShotgunPattern] = []
var _refresh_queued := false
var _stability_slider: HSlider
var _distance_spin: SpinBox


func _ready() -> void:
	stability = preview_initial_stability
	distance_m = preview_distance_m
	var title := Label.new()
	title.text = "霰弹图样实验台"
	title.position = Vector2(32, 20)
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)
	var hint := Label.new()
	hint.text = "空心圆：固定落点 · 实心点：本枪弹丸 · 选中预览根节点可拖入三个图样，调整独立覆盖与偏移参数"
	hint.position = Vector2(32, 66)
	add_child(hint)
	var controls := HBoxContainer.new()
	controls.position = Vector2(32, 108)
	controls.add_theme_constant_override("separation", 16)
	add_child(controls)
	var caption := Label.new()
	caption.text = "稳定度"
	controls.add_child(caption)
	var slider := HSlider.new()
	_stability_slider = slider
	slider.custom_minimum_size.x = 220
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = stability
	controls.add_child(slider)
	slider.value_changed.connect(func(value): stability = value; fire())
	var distance_label := Label.new()
	distance_label.text = "预览观察距离（米）"
	controls.add_child(distance_label)
	var distance := SpinBox.new()
	_distance_spin = distance
	distance.min_value = 0.1
	distance.max_value = 1000
	distance.allow_greater = true
	distance.step = 0.1
	distance.value = distance_m
	controls.add_child(distance)
	distance.value_changed.connect(func(value): distance_m = value; queue_redraw())
	var button := Button.new()
	button.text = "试射 / 空格"
	button.pressed.connect(fire)
	controls.add_child(button)
	status = Label.new()
	status.position = Vector2(32, 156)
	add_child(status)
	resized.connect(queue_redraw)
	_refresh()


func get_patterns() -> Array[ShotgunPattern]:
	return [pattern_1, pattern_2, pattern_3]


func get_pattern_coverage_area() -> float:
	return ShotgunSettings.coverage_area_at(preview_calibration_distance_m, preview_pattern_angle_degrees)


func set_pattern_calibration(distance_meters: float, area_m2: float) -> bool:
	var angle := ShotgunSettings.calibration_angle_degrees(distance_meters, area_m2)
	if not is_finite(angle): return false
	preview_calibration_distance_m = distance_meters
	preview_pattern_angle_degrees = angle
	return true


func _queue_refresh() -> void:
	changed.emit()
	if not is_inside_tree() or not is_node_ready() or _refresh_queued: return
	_refresh_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	if not is_inside_tree() or status == null: return
	var patterns := get_patterns()
	for previous in _watched_patterns:
		if not patterns.has(previous) and previous.changed.is_connected(_queue_refresh):
			previous.changed.disconnect(_queue_refresh)
	_watched_patterns.clear()
	for pattern in patterns:
		if pattern == null or _watched_patterns.has(pattern): continue
		_watched_patterns.append(pattern)
		if not pattern.changed.is_connected(_queue_refresh): pattern.changed.connect(_queue_refresh)
	_stability_slider.set_value_no_signal(stability)
	_distance_spin.set_value_no_signal(distance_m)
	fire()


func _exit_tree() -> void:
	for pattern in _watched_patterns:
		if pattern.changed.is_connected(_queue_refresh): pattern.changed.disconnect(_queue_refresh)
	_watched_patterns.clear()


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		fire()
		accept_event()


func fire() -> void:
	_settings.pattern_angle_degrees = preview_pattern_angle_degrees
	_settings.stable_jitter_degrees = preview_stable_jitter_degrees
	_settings.unstable_jitter_degrees = preview_unstable_jitter_degrees
	shots.clear()
	for pattern in get_patterns():
		_settings.pattern = pattern
		shots.append(Ballistics.sample_offsets(_settings, stability, rng) if pattern != null else PackedVector2Array())
	_settings.pattern = null
	if status != null:
		status.text = "独立预览 · 稳定度 %d%% · 每颗最大偏差 %.2f° · 固定图样尺度 %.2f°" % [roundi(stability * 100), _settings.get_jitter_degrees(stability), preview_pattern_angle_degrees]
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101822"))
	if shots.is_empty(): return
	var font := ThemeDB.fallback_font
	var width := (size.x - 80.0) / 3.0
	var panel_height := maxf(240.0, size.y - 244.0)
	var radius := minf(width - 28, panel_height - 70) * 0.5
	# 三栏使用同一米制比例尺；远距离时扩大可视范围，不裁掉测试落点。
	var view_radius := get_view_radius_m()
	var scale_m := radius / view_radius
	var patterns := get_patterns()
	for index in patterns.size():
		var rect := Rect2(24 + index * (width + 16), 208, width, panel_height)
		var center := rect.get_center() + Vector2(0, 12)
		draw_style_box(_panel_style(), rect)
		var pattern := patterns[index]
		draw_string(font, rect.position + Vector2(16, 30), pattern.display_name if pattern != null else "未指定图样", HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("e8eef5"))
		if pattern == null: continue
		for fraction in [0.5, 1.0, 1.5]:
			var ring: float = fraction * view_radius / 1.8
			draw_arc(center, ring * scale_m, 0, TAU, 64, Color("304052"), 1, true)
			draw_string(font, center + Vector2(4, -ring * scale_m + 14), "%.1fm" % ring, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("8296ac"))
		draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color("304052"))
		draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color("304052"))
		for point in pattern.valid_points():
			var position_2d := center + _project(point * preview_pattern_angle_degrees) * scale_m
			draw_arc(position_2d, 7, 0, TAU, 24, Color("6f879d"), 1.5, true)
		for offset in shots[index]:
			draw_circle(center + _project(offset) * scale_m, 4, Color("5de0ba"), true, -1, true)
	var footer := "观察截面 %.1f m · 标定 %.1f m / %.3f m² · 三栏同一比例尺，远距离自动扩大视野" % [distance_m, preview_calibration_distance_m, get_pattern_coverage_area()]
	draw_string(font, Vector2(32, size.y - 16), footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("9db0c4"))


func _project(offset: Vector2) -> Vector2:
	return Vector2(tan(deg_to_rad(offset.x)), -tan(deg_to_rad(offset.y))) * distance_m


func get_view_radius_m() -> float:
	var required := 1.8
	for pattern in get_patterns():
		if pattern == null: continue
		for point in pattern.valid_points():
			var projected := _project(point * preview_pattern_angle_degrees).abs()
			required = maxf(required, maxf(projected.x, projected.y) * 1.15)
	for offsets in shots:
		for offset in offsets:
			var projected := _project(offset).abs()
			required = maxf(required, maxf(projected.x, projected.y) * 1.15)
	# 按倍数扩展，减少微小随机偏移引起的比例尺变动。
	return 1.8 * pow(2.0, ceil(log(required / 1.8) / log(2.0)))


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182431")
	style.set_corner_radius_all(12)
	return style
