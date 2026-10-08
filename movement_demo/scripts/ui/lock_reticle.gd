extends Control

## 稳定度为 1.0 时准星的半径（屏幕像素）；数值越小，收拢后的准星越小。
@export var minimum_radius: float = 12.0
## 稳定度为 0.0 时准星的半径（屏幕像素）；中间稳定度在两个半径之间插值，通常不小于 Minimum Radius。
@export var maximum_radius: float = 52.0
var radius: float = 52.0
var tint: Color = Color.WHITE

@onready var combat = get_parent().get_parent()


func _process(_delta: float) -> void:
	var target = combat.locked_target
	var camera := get_viewport().get_camera_3d()
	visible = combat.is_aiming and is_instance_valid(target) and camera != null and not combat.player.is_in_dialogue
	if not visible:
		return
	var point: Vector3 = combat.get_locked_aim_point()
	if camera.is_position_behind(point):
		hide()
		return
	# 两种模式共用原圆形准星，大小提示稳定度，不代表实际弹道范围。
	position = camera.unproject_position(point)
	var stability: float = combat.get_effective_accuracy()
	radius = lerpf(maximum_radius, minimum_radius, stability)
	tint = Color(1.0, 0.55, 0.2).lerp(Color(0.35, 1.0, 0.55), stability)
	queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.8), 4.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, tint, 2.0, true)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(direction * (radius - 5.0), direction * (radius + 6.0), tint, 2.0, true)
