extends Node3D

const Director = preload("res://scripts/systems/scene_director.gd")
const Request = preload("res://scripts/systems/scene_request.gd")
var _scene_request: Request

## 门扇打开时相对于门根节点的 X 坐标（米），关闭回到 0；正负值决定滑动方向。
@export var slide_distance: float = 2.0
## 每次开门或关门动画的完整时长（秒）；途中折返会从当前位置重新计时。
@export var animation_seconds: float = 0.3
var is_open: bool = false
var door_tween: Tween


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	for body in $Sensor.get_overlapping_bodies():
		if body.is_in_group("player") and not body.is_in_dialogue:
			get_viewport().set_input_as_handled()
			if not is_open:
				_set_open(true)
			return


func _physics_process(_delta: float) -> void:
	var player_nearby: bool = false
	for body in $Sensor.get_overlapping_bodies():
		if body.is_in_group("player"):
			player_nearby = true
	if is_open and not player_nearby:
		_set_open(false)
	elif not is_open and player_nearby and door_tween != null and door_tween.is_running():
		# 关门途中折返，重新打开防止夹住；完全关好后仍需按 E。
		_set_open(true)


func _set_open(open: bool) -> void:
	request_open(open)

func scene_action_is_background() -> bool:
	return true

func request_open(open: bool) -> Request:
	var director = Director.for_node(self)
	if director == null: return null
	if _scene_request != null and _scene_request.is_current():
		if is_open == open: return _scene_request
		director.cancel_request(_scene_request.id, &"door_reversed")
	return director.request_action(&"script", {"source": self, "target": self,
		"scope": 1, "scope_owner": director.region_owner(), "parameters": {"open": open}})

func begin_scene_action(request: Request) -> void:
	if not request.is_current() or request.node(&"target") != self or request.kind != &"script": return
	_scene_request = request
	_animate_open(request.parameters.get("open", false))
	door_tween.finished.connect(_finished.bind(request))

func cancel_scene_action(request: Request, _reason: StringName) -> void:
	if _scene_request != request: return
	_scene_request = null
	if door_tween != null and door_tween.is_valid(): door_tween.kill()

func _finished(request: Request) -> void:
	if _scene_request != request: return
	_scene_request = null
	request.complete()

func _exit_tree() -> void:
	if door_tween != null and door_tween.is_valid(): door_tween.kill()

func _animate_open(open: bool) -> void:
	is_open = open
	$Label.text = "离开门口后自动关闭" if is_open else "E 开门"
	if door_tween != null and door_tween.is_valid():
		door_tween.kill()
	# 门扇向墙内滑动，碰撞随门一起移动；保留真实开关过程。
	door_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	door_tween.tween_property($Panel, "position:x", slide_distance if is_open else 0.0, animation_seconds)
