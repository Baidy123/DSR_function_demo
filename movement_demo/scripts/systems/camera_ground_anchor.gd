extends Node3D

## 只提供相机跟随位置，过滤翻越抬升；不修改玩家或第三方相机插件。
@export var player_path: NodePath = ^"../Player"
var actor: Node3D

func _ready() -> void:
	var camera := get_parent()
	actor = camera.get_follow_actor() if camera.has_method("get_follow_actor") else get_node_or_null(player_path)
	if is_instance_valid(actor) and not actor.is_node_ready():
		actor.ready.connect(_update_anchor, CONNECT_ONE_SHOT)
	_update_anchor()

func _physics_process(_delta: float) -> void:
	_update_anchor()

func _update_anchor() -> void:
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return
	global_position = actor.global_position
	if actor.is_node_ready() and actor.has_method("get_camera_ground_height"):
		global_position.y = actor.get_camera_ground_height()

func _exit_tree() -> void:
	if is_instance_valid(actor) and actor.ready.is_connected(_update_anchor):
		actor.ready.disconnect(_update_anchor)
