extends Node3D

const Director = preload("res://scripts/systems/scene_director.gd")

@export var route: Array[Vector3] = []
var _loop: Tween


func _ready() -> void:
	_start_activity.call_deferred()


func _start_activity() -> void:
	var director = Director.for_node(self)
	if director != null:
		director.request_action(&"script", {"source": self, "target": self})


func scene_action_is_background() -> bool:
	return true


func begin_scene_action(request: SceneRequest) -> void:
	if not request.is_current() or request.node(&"target") != self:
		return
	_loop = create_tween().set_loops()
	if route.size() >= 2:
		var previous := route.back() as Vector3
		position = previous
		for point in route:
			_loop.tween_property(self, "position", point, maxf(0.25, previous.distance_to(point) / 1.15))
			previous = point
			_loop.tween_interval(1.1)
	else:
		_loop.tween_property(self, "rotation:y", rotation.y + 0.28, 2.0)
		_loop.tween_property(self, "rotation:y", rotation.y, 1.7)


func cancel_scene_action(_request: SceneRequest, _reason: StringName) -> void:
	if _loop != null:
		_loop.kill()
		_loop = null
