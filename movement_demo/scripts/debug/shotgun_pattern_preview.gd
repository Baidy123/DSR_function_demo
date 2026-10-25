@tool
extends Control

const Ballistics = preload("res://scripts/weapons/shotgun_ballistics.gd")
const PATTERNS = [preload("res://resources/weapons/patterns/balanced.tres"),
	preload("res://resources/weapons/patterns/horizontal.tres"), preload("res://resources/weapons/patterns/vertical.tres")]
var weapon: ShotgunSettings = preload("res://resources/weapons/test_shotgun.tres").shotgun.duplicate(true)
var stability: float = 1.0
var distance_m: float = 10.0
var shots: Array[PackedVector2Array] = []
var rng := RandomNumberGenerator.new()
var status: Label


func _ready() -> void:
	var title := Label.new()
	title.text = "霰弹图样实验台"
	title.position = Vector2(32, 20)
	title.add_theme_font_size_override("font_size", 28)
	add_child(title)
	var hint := Label.new()
	hint.text = "空心圆：固定落点 · 实心点：本枪弹丸 · F6 运行后可调参数；编辑落点请打开 Pattern 资源的检查器画板"
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
	slider.custom_minimum_size.x = 220
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = stability
	controls.add_child(slider)
	slider.value_changed.connect(func(value): stability = value; fire())
	var distance_label := Label.new()
	distance_label.text = "距离（米）"
	controls.add_child(distance_label)
	var distance := SpinBox.new()
	distance.min_value = 2
	distance.max_value = 30
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
	fire()


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		fire()
		accept_event()


func fire() -> void:
	shots.clear()
	for pattern in PATTERNS:
		weapon.pattern = pattern
		shots.append(Ballistics.sample_offsets(weapon, stability, rng))
	status.text = "稳定度 %d%%  ·  每颗最大偏差 %.2f°  ·  固定图样尺度 %.1f°（不随稳定度变化）" % [roundi(stability * 100), weapon.get_jitter_degrees(stability), weapon.pattern_angle_degrees]
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101822"))
	if shots.is_empty(): return
	var font := ThemeDB.fallback_font
	var width := (size.x - 80.0) / 3.0
	var panel_height := maxf(240.0, size.y - 244.0)
	var radius := minf(width - 28, panel_height - 70) * 0.5
	# 每个图恒定显示左右各 1.8 米，调距离会真实扩大覆盖，而调精度不会缩放固定点。
	var scale_m := radius / 1.8
	for index in PATTERNS.size():
		var rect := Rect2(24 + index * (width + 16), 208, width, panel_height)
		var center := rect.get_center() + Vector2(0, 12)
		draw_style_box(_panel_style(), rect)
		draw_string(font, rect.position + Vector2(16, 30), PATTERNS[index].display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 21, Color("e8eef5"))
		for ring in [0.5, 1.0, 1.5]:
			draw_arc(center, ring * scale_m, 0, TAU, 64, Color("304052"), 1, true)
			draw_string(font, center + Vector2(4, -ring * scale_m + 14), "%.1fm" % ring, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("8296ac"))
		draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color("304052"))
		draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color("304052"))
		for point in PATTERNS[index].valid_points():
			var position_2d := center + _project(point * weapon.pattern_angle_degrees) * scale_m
			draw_arc(position_2d, 7, 0, TAU, 24, Color("6f879d"), 1.5, true)
		for offset in shots[index]:
			draw_circle(center + _project(offset) * scale_m, 4, Color("5de0ba"), true, -1, true)
	var footer := "越远覆盖越大；稳定度只改变每颗弹丸的偏差。实际开枪试玩：shotgun_range.tscn"
	draw_string(font, Vector2(32, size.y - 16), footer, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("9db0c4"))


func _project(offset: Vector2) -> Vector2:
	return Vector2(tan(deg_to_rad(offset.x)), -tan(deg_to_rad(offset.y))) * distance_m


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182431")
	style.set_corner_radius_all(12)
	return style
