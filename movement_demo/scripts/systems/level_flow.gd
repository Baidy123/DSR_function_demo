extends CanvasLayer

## 五关适配器：SceneDirector 拥有完成、死亡、暂停与加载；本地流程只开放返程门。
signal continue_requested

const LEVELS: Array[String] = [
	"res://scenes/world/levels/lvl_1.tscn",
	"res://scenes/world/levels/lvl_2.tscn",
	"res://scenes/world/levels/lvl_3.tscn",
	"res://scenes/world/levels/lvl_4.tscn",
	"res://scenes/world/levels/lvl_5.tscn",
]
const RETURN_SCENE := "res://scenes/main.tscn"

@export_range(1, 5) var level_number: int = 1
@export_node_path("Interactable") var return_portal_path: NodePath

@onready var _health = get_parent().get_node_or_null("Player/Health")
@onready var _return_portal = get_node_or_null(return_portal_path) as Interactable
@onready var _result: ColorRect = $Result
@onready var _title: Label = $Result/Center/Panel/Content/Title
@onready var _message: Label = $Result/Center/Panel/Content/Message
@onready var _continue_button: Button = $Result/Center/Panel/Content/Continue

var _transition_pending := false
var _scene_director: Node


func _ready() -> void:
	$Progress.text = "第 %d 关 / %d" % [level_number, LEVELS.size()]
	_continue_button.pressed.connect(_continue)
	hide_result()
	_bind_scene_director()


## 同级SceneDirector可能先于本节点ready；在这里补接原波次完成信号。
func _bind_scene_director() -> void:
	_scene_director = get_parent().get_node_or_null("SceneDirector")
	if _scene_director == null or not _scene_director.has_signal("encounter_completed"):
		return
	if _scene_director.get("complete_when_all_waves_cleared") != true:
		return
	if not _scene_director.encounter_completed.is_connected(_request_scene_completion):
		_scene_director.encounter_completed.connect(_request_scene_completion)


func _request_scene_completion() -> void:
	var director = _scene_director.get("director") if is_instance_valid(_scene_director) else null
	if is_instance_valid(director) and director.has_method("request_completion"):
		director.request_completion()
		return
	push_error("第%d关完成但SceneDirector尚未初始化" % level_number)


## 本地返程门需要玩家继续行动并按 E 返回酒馆；无返程门时保留暂停结果面板语义。
func completion_pauses_world() -> bool:
	return return_portal_path.is_empty()


## SceneDirector 完成回调：本地五关不显示下一关按钮，只开放当前关返程门。
func show_completion() -> void:
	hide_result()
	if _health != null and _health.is_dead:
		return
	if _return_portal == null:
		push_error("第%d关完成但未配置返回酒馆传送门" % level_number)
		return
	_return_portal.visible = true
	_return_portal.enabled = true
	_return_portal.monitoring = true


func _show_result(title: String, message: String, button_text: String) -> void:
	_transition_pending = false
	_title.text = title
	_message.text = message
	_continue_button.text = button_text
	_continue_button.disabled = false
	_result.show()
	_continue_button.grab_focus()


func _continue() -> void:
	if _transition_pending or not _result.visible:
		return
	_transition_pending = true
	_continue_button.disabled = true
	continue_requested.emit()


## 五关不能跳过酒馆中的 A 解锁步骤；加载重试也只返回酒馆。
func next_scene_path() -> String:
	return RETURN_SCENE


func show_load_error() -> void:
	_show_result("返回酒馆失败", "无法返回酒馆，请重试。", "重试")


func set_transition_pending(pending: bool) -> void:
	_transition_pending = pending
	_continue_button.disabled = pending


func hide_result() -> void:
	_result.hide()
	if _continue_button.is_inside_tree():
		_continue_button.release_focus()
	set_transition_pending(false)
