extends RefCounted

## 复用 Health 下的死亡界面节点；只展示结果和发送按钮意图。
signal restart_requested

var _screen: Control
var _message: Label
var _restart_button: Button
var _default_message := ""
var _pending := false


## 传入 null 解除旧界面绑定；场景调度器负责绑定与卸载。
func bind(health: Node) -> void:
	hide_result()
	if is_instance_valid(_restart_button) and _restart_button.pressed.is_connected(_on_restart_pressed):
		_restart_button.pressed.disconnect(_on_restart_pressed)
	_screen = null
	_message = null
	_restart_button = null
	_default_message = ""
	if not is_instance_valid(health): return
	_screen = health.get_node_or_null("DeathScreen") as Control
	_message = health.get_node_or_null("DeathScreen/Center/Panel/Content/Message") as Label
	_restart_button = health.get_node_or_null("DeathScreen/Center/Panel/Content/Restart") as Button
	if is_instance_valid(_message):
		_default_message = _message.text
	if is_instance_valid(_restart_button):
		_restart_button.pressed.connect(_on_restart_pressed)
	hide_result()


func show_death() -> void:
	if not is_instance_valid(_screen) or _screen.visible: return
	if is_instance_valid(_message):
		_message.text = _default_message
	set_pending(false)
	_screen.show()
	if is_instance_valid(_restart_button):
		_restart_button.grab_focus()


func set_pending(pending: bool) -> void:
	_pending = pending
	if is_instance_valid(_restart_button):
		_restart_button.disabled = pending


func show_load_error() -> void:
	if not is_instance_valid(_screen): return
	if is_instance_valid(_message):
		_message.text = "重新开始失败，请重试"
	set_pending(false)
	_screen.show()
	if is_instance_valid(_restart_button):
		_restart_button.grab_focus()


func hide_result() -> void:
	if is_instance_valid(_screen):
		_screen.hide()
	if is_instance_valid(_message):
		_message.text = _default_message
	if is_instance_valid(_restart_button) and _restart_button.is_inside_tree():
		_restart_button.release_focus()
	set_pending(false)


func _on_restart_pressed() -> void:
	if _pending or not is_instance_valid(_screen) or not _screen.visible: return
	restart_requested.emit()
