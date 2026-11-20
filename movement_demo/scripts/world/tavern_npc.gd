class_name TavernNPC
extends CharacterBody3D

const Director = preload("res://scripts/systems/scene_director.gd")
const ARRIVAL_DISTANCE := 0.12
const DETOUR_FORWARD := 1.75

@export var seated := false
@export var tint := Color("#8b8075")
@export var carry_crate := false
@export var starts_hidden := false
@export var patrol_on_ready := false
@export_node_path("CollisionShape3D") var floor_path: NodePath = ^"../BarEnvironment/Architecture/Floor/Collision"
## World positions arranged in visiting order. A vacant route keeps this actor at its authored spot.
@export var route: Array[Vector3] = []
@export_range(0.0, 20.0, 0.1) var waypoint_pause := 1.8
@export_range(0.2, 5.0, 0.05) var walk_speed := 1.35

@onready var _body: MeshInstance3D = $Body
var _request: SceneRequest
var _points: Array[Vector3] = []
var _detour: Array[Vector3] = []
var _index := 0
var _delay := 0.0
var _patrolling := false
var _vanish_at_end := false
var _floor_plane := Plane(Vector3.UP, 0.0)
var _detour_blocked_time := 0.0


func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	_body.material_override = material
	if seated:
		_body.scale.y = 0.68
		_body.position.y = 0.96
	$Crate.visible = carry_crate
	var floor_shape := get_node_or_null(floor_path) as CollisionShape3D
	if floor_shape != null and floor_shape.shape is BoxShape3D:
		var top := floor_shape.to_global(Vector3.UP * floor_shape.shape.size.y * 0.5)
		_floor_plane = Plane(floor_shape.global_basis.y.normalized(), top)
		var floor_body := floor_shape.get_parent() as PhysicsBody3D
		if floor_body != null:
			add_collision_exception_with(floor_body)
	set_physical_presence(not starts_hidden)
	set_physics_process(false)
	if patrol_on_ready and not seated and not route.is_empty():
		_start_patrol.call_deferred()


func set_physical_presence(present: bool) -> void:
	visible = present
	collision_layer = 1 if present else 0


func _start_patrol() -> void:
	var director = Director.for_node(self)
	if director != null:
		director.request_action(&"script", {"source": self, "target": self,
			"parameters": {"patrol": true}, "dedupe_key": &"patrol"})


func scene_action_is_background() -> bool:
	return true


func begin_scene_action(request: SceneRequest) -> void:
	if not request.is_current() or request.node(&"target") != self:
		return
	if _request != null and _request.is_current():
		request.fail("actor_is_moving")
		return
	_request = request
	_patrolling = request.parameters.get("patrol", false)
	_vanish_at_end = request.parameters.get("vanish_at_end", false)
	_points.assign(request.parameters.get("points", route))
	_detour.clear()
	_index = 0
	_delay = 0
	_detour_blocked_time = 0
	if _points.is_empty():
		_finish()
	else:
		set_physics_process(true)


func cancel_scene_action(request: SceneRequest, _reason: StringName) -> void:
	if request == _request:
		_stop()


func _physics_process(delta: float) -> void:
	if _request == null or not _request.is_current():
		_stop()
		return
	if _delay > 0:
		_delay -= delta
		return
	var goal := _detour[0] if not _detour.is_empty() else _points[_index]
	var offset := goal - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= ARRIVAL_DISTANCE:
		if not _detour.is_empty():
			_detour.pop_front()
		else:
			_next_waypoint()
		return
	var direction := offset / distance
	var step := minf(walk_speed * delta, distance)
	if test_move(global_transform, _floor_motion(global_transform, direction * minf(0.86, distance))):
		if _detour.is_empty() and _find_detour(direction, distance):
			return
		if test_move(global_transform, _floor_motion(global_transform, direction * step)):
			_detour_blocked_time += delta
			if _detour_blocked_time > 0.25:
				_detour.clear()
				_detour_blocked_time = 0.0
			return
	_detour_blocked_time = 0.0
	_body.rotation.y = rotate_toward(_body.rotation.y, atan2(direction.x, direction.z), 7.0 * delta)
	move_and_collide(_floor_motion(global_transform, direction * step))


func _find_detour(direction: Vector3, distance: float) -> bool:
	var side := Vector3(-direction.z, 0, direction.x)
	for width in [0.75, -0.75, 1.08, -1.08]:
		var sideways := side * float(width)
		var forward := direction * minf(distance, DETOUR_FORWARD)
		var side_motion := _floor_motion(global_transform, sideways)
		var adjacent := global_transform.translated(side_motion)
		var forward_motion := _floor_motion(adjacent, forward)
		var alongside := adjacent.translated(forward_motion)
		var return_motion := _floor_motion(alongside, -sideways)
		if test_move(global_transform, side_motion) or test_move(adjacent, forward_motion) or test_move(alongside, return_motion):
			continue
		_detour.assign([adjacent.origin, alongside.origin, alongside.origin + return_motion])
		return true
	return false


func floor_position(point: Vector3) -> Vector3:
	point.y -= _floor_plane.distance_to(point) / _floor_plane.normal.y
	return point


func _floor_motion(from: Transform3D, planar: Vector3) -> Vector3:
	return floor_position(from.origin + planar) - from.origin


func _next_waypoint() -> void:
	_index += 1
	if _index == _points.size():
		if not _patrolling:
			_finish()
			return
		_index = 0
	if _patrolling:
		_delay = waypoint_pause


func _finish() -> void:
	var finished := _request
	if _vanish_at_end:
		set_physical_presence(false)
	_stop()
	finished.complete()


func _stop() -> void:
	set_physics_process(false)
	_request = null
	_detour.clear()
