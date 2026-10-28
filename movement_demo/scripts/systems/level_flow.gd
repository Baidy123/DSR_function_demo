extends CanvasLayer

## 五关结果视图及关卡表；完成判定、暂停和切关由场景调度器负责。
signal continue_requested

const LEVELS: Array[String] = [
	"res://scenes/world/levels/lvl_1.tscn",
	"res://scenes/world/levels/lvl_2.tscn",
	"res://scenes/world/levels/lvl_3.tscn",
	"res://scenes/world/levels/lvl_4.tscn",
	"res://scenes/world/levels/lvl_5.tscn",
]

@export_range(1, 5) var level_number: int = 1

@onready var _result: ColorRect = $Result
@onready var _title: Label = $Result/Center/Panel/Content/Title
@onready var _message: Label = $Result/Center/Panel/Content/Message
@onready var _continue_button: Button = $Result/Center/Panel/Content/Continue

var _transition_pending := false


func _ready() -> void:
	$Progress.text = "第 %d 关 / %d" % [level_number, LEVELS.size()]
	_continue_button.pressed.connect(_continue)
	hide_result()


func show_completion() -> void:
	if _result.visible: return
	if level_number < LEVELS.size():
		_show_result("第 %d 关完成" % level_number, "全部敌人波次已清空。准备好后进入下一关。", "进入第 %d 关" % (level_number + 1))
	else:
		_show_result("五关挑战完成", "你已完成全部 5 关。可以从第 1 关重新挑战。", "从第 1 关重新开始")


func _show_result(title: String, message: String, button_text: String) -> void:
	_title.text = title
	_message.text = message
	_continue_button.text = button_text
	set_transition_pending(false)
	_result.show()
	_continue_button.grab_focus()


func _continue() -> void:
	if _transition_pending or not _result.visible: return
	continue_requested.emit()


func next_scene_path() -> String:
	return LEVELS[clampi(level_number, 1, LEVELS.size()) % LEVELS.size()]


func show_load_error() -> void:
	_show_result("关卡加载失败", "无法加载下一关，请重试。", "重试")


func set_transition_pending(pending: bool) -> void:
	_transition_pending = pending
	_continue_button.disabled = pending


func hide_result() -> void:
	_result.hide()
	if _continue_button.is_inside_tree(): _continue_button.release_focus()
	set_transition_pending(false)
