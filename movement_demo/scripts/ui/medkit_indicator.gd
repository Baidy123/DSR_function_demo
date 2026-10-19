extends Control

## 只读医疗进度；将真实身体头顶投影到屏幕，不控制治疗、身体或动画。
@export_range(12.0, 48.0, 1.0) var radius: float = 22.0
@export_range(0.0, 40.0, 1.0) var head_gap: float = 10.0
var progress := 0.0
@onready var health = get_parent()
@onready var medkit = health.get_node("Medkit")
@onready var player = health.get_parent()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	medkit.state_changed.connect(_refresh)
	_refresh()

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	var camera := get_viewport().get_camera_3d()
	visible = medkit.is_using() and not health.is_dead and not player.is_in_dialogue and camera != null
	if not visible: return
	var head: Vector3 = player.global_position + Vector3.UP * player.get_body_height()
	if camera.is_position_behind(head):
		hide()
		return
	position = camera.unproject_position(head) - Vector2(0.0, radius + head_gap)
	progress = medkit.get_progress()
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius + 4.0, Color(0.025, 0.045, 0.055, 0.88))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.25, 0.34, 0.36), 4.0, true)
	if progress > 0.0:
		draw_arc(Vector2.ZERO, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 64, Color(0.35, 1.0, 0.70), 4.0, true)
	# 几何十字不依赖字体或外部纹理；医疗色与原生命／体力显示区分。
	draw_rect(Rect2(-3.0, -10.0, 6.0, 20.0), Color(0.85, 1.0, 0.93))
	draw_rect(Rect2(-10.0, -3.0, 20.0, 6.0), Color(0.85, 1.0, 0.93))
