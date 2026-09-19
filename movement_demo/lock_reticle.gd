extends Control

## 精度为 1.0 时准星的半径（屏幕像素）；数值越小，收拢后的准星越小。
@export var minimum_radius: float = 12.0
## 精度为 0.0 时准星的半径（屏幕像素）；中间精度在两个半径之间插值，通常不小于 Minimum Radius。
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
	var point: Vector3 = target.global_position + Vector3.UP * 0.8
	if camera.is_position_behind(point):
		hide()
		return
	# 3D 目标位置投影到 HUD：准星尺寸用屏幕像素，不受目标远近影响。
	position = camera.unproject_position(point)
	radius = lerpf(maximum_radius, minimum_radius, clampf(combat.accuracy, 0.0, 1.0))
	tint = Color(1.0, 0.55, 0.2).lerp(Color(0.35, 1.0, 0.55), combat.accuracy)
	queue_redraw()


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.8), 4.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, tint, 2.0, true)
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(direction * (radius - 5.0), direction * (radius + 6.0), tint, 2.0, true)
