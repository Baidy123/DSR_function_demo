extends CanvasLayer

## 只衔接已保存的五关；完成仍由 EnemyWaves 判定，死亡重开仍由 Health 执行。
const LEVELS: Array[String] = [
	"res://scenes/world/levels/lvl_1.tscn",
	"res://scenes/world/levels/lvl_2.tscn",
	"res://scenes/world/levels/lvl_3.tscn",
	"res://scenes/world/levels/lvl_4.tscn",
	"res://scenes/world/levels/lvl_5.tscn",
]

@export_range(1, 5) var level_number: int = 1

@onready var _health = get_parent().get_node("Player/Health")
@onready var _result: ColorRect = $Result
@onready var _title: Label = $Result/Center/Panel/Content/Title
@onready var _message: Label = $Result/Center/Panel/Content/Message
@onready var _continue_button: Button = $Result/Center/Panel/Content/Continue

var _transition_pending := false
var _owns_pause := false
var _previous_pause := false
var _target_scene := ""


func _ready() -> void:
	$Progress.text = "第 %d 关 / %d" % [level_number, LEVELS.size()]
	get_parent().get_node("EnemyWaves").encounter_completed.connect(_on_encounter_completed)
	_continue_button.pressed.connect(_continue)


func _on_encounter_completed() -> void:
	if _transition_pending or _result.visible: return
	_transition_pending = true
	# 完成来自物理更新，界面留到回调结束后；同帧死亡优先，不自动切关。
	_show_completion.call_deferred()


func _show_completion() -> void:
	_transition_pending = false
	if _health.is_dead: return
	if level_number < LEVELS.size():
		_show_result("第 %d 关完成" % level_number, "全部敌人波次已清空。准备好后进入下一关。", "进入第 %d 关" % (level_number + 1), LEVELS[level_number])
	else:
		_show_result("五关挑战完成", "你已完成全部 5 关。可以从第 1 关重新挑战。", "从第 1 关重新开始", LEVELS[0])


func _show_result(title: String, message: String, button_text: String, target: String) -> void:
	_title.text = title
	_message.text = message
	_continue_button.text = button_text
	_continue_button.disabled = false
	_target_scene = target
	_result.show()
	if not _owns_pause:
		_previous_pause = get_tree().paused
		_owns_pause = true
	get_tree().paused = true
	_continue_button.grab_focus()


func _continue() -> void:
	if _transition_pending: return
	_transition_pending = true
	_continue_button.disabled = true
	_change_scene.call_deferred(_target_scene)


func _change_scene(path: String) -> void:
	_restore_pause()
	var result := get_tree().change_scene_to_file(path)
	if result != OK:
		_transition_pending = false
		_show_result("关卡加载失败", "无法加载下一关，请重试。", "重试", path)
		push_error("无法切换到 %s：%s" % [path, error_string(result)])


func _exit_tree() -> void:
	_restore_pause()


func _restore_pause() -> void:
	if not _owns_pause: return
	_owns_pause = false
	get_tree().paused = _previous_pause
