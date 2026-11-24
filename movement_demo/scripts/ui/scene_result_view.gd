extends RefCounted

## 复用 Health 下的死亡界面节点；只展示结果和发送按钮意图。
signal restart_requested
signal return_to_tavern_requested
signal load_game_requested

var _screen: Control
var _message: Label
var _restart_button: Button
var _tavern_button: Button
var _load_button: Button
var _default_message := ""
var _pending := false
var _tavern_available := true
var _load_available := false


## 传入 null 解除旧界面绑定；场景调度器负责绑定与卸载。
func bind(health: Node) -> void:
	hide_result()
	if is_instance_valid(_restart_button) and _restart_button.pressed.is_connected(_on_restart_pressed):
		_restart_button.pressed.disconnect(_on_restart_pressed)
	if is_instance_valid(_tavern_button) and _tavern_button.pressed.is_connected(_on_tavern_pressed):
		_tavern_button.pressed.disconnect(_on_tavern_pressed)
	if is_instance_valid(_load_button) and _load_button.pressed.is_connected(_on_load_pressed):
		_load_button.pressed.disconnect(_on_load_pressed)
	_screen = null
	_message = null
	_restart_button = null
	_tavern_button = null
	_load_button = null
	_default_message = ""
	if not is_instance_valid(health): return
	_screen = health.get_node_or_null("DeathScreen") as Control
	_message = health.get_node_or_null("DeathScreen/Center/Panel/Content/Message") as Label
	_restart_button = health.get_node_or_null("DeathScreen/Center/Panel/Content/Restart") as Button
	_tavern_button = health.get_node_or_null("DeathScreen/Center/Panel/Content/ReturnToTavern") as Button
	_load_button = health.get_node_or_null("DeathScreen/Center/Panel/Content/LoadGame") as Button
	if is_instance_valid(_message):
		_default_message = _message.text
	if is_instance_valid(_restart_button):
		_restart_button.pressed.connect(_on_restart_pressed)
	if is_instance_valid(_tavern_button):
		_tavern_button.pressed.connect(_on_tavern_pressed)
		_tavern_button.visible = _tavern_available
	if is_instance_valid(_load_button):
		_load_button.pressed.connect(_on_load_pressed)
	hide_result()


func set_tavern_available(available: bool) -> void:
	_tavern_available = available
	if is_instance_valid(_tavern_button):
		_tavern_button.visible = available
		_tavern_button.disabled = _pending or not available


func set_saved_game_available(available: bool) -> void:
	_load_available = available
	if is_instance_valid(_load_button):
		_load_button.disabled = _pending or not available
		_load_button.tooltip_text = "恢复最近保存的进度并返回酒馆" if available else "没有可加载的存档"


func show_death() -> void:
	if not is_instance_valid(_screen) or _screen.visible: return
	if is_instance_valid(_message):
		_message.text = _default_message if _tavern_available else "重新挑战当前关卡，按本关保存配置恢复。"
	set_pending(false)
	_screen.show()
	if is_instance_valid(_restart_button):
		_restart_button.grab_focus()


func set_pending(pending: bool) -> void:
	_pending = pending
	if is_instance_valid(_restart_button):
		_restart_button.disabled = pending
	if is_instance_valid(_tavern_button):
		_tavern_button.disabled = pending or not _tavern_available
	if is_instance_valid(_load_button):
		_load_button.disabled = pending or not _load_available


func show_load_error(message: String = "场景切换失败，请重试") -> void:
	if not is_instance_valid(_screen): return
	if is_instance_valid(_message):
		_message.text = message
	set_pending(false)
	_screen.show()
	if is_instance_valid(_restart_button):
		_restart_button.grab_focus()


func show_saved_game_load_error() -> void:
	show_load_error("加载已保存游戏失败，请重试")


func hide_result() -> void:
	if is_instance_valid(_screen):
		_screen.hide()
	if is_instance_valid(_message):
		_message.text = _default_message
	if is_instance_valid(_restart_button) and _restart_button.is_inside_tree():
		_restart_button.release_focus()
	if is_instance_valid(_tavern_button) and _tavern_button.is_inside_tree():
		_tavern_button.release_focus()
	if is_instance_valid(_load_button) and _load_button.is_inside_tree():
		_load_button.release_focus()
	set_pending(false)


func _on_restart_pressed() -> void:
	if _pending or not is_instance_valid(_screen) or not _screen.visible: return
	restart_requested.emit()


func _on_tavern_pressed() -> void:
	if _pending or not is_instance_valid(_screen) or not _screen.visible: return
	return_to_tavern_requested.emit()


func _on_load_pressed() -> void:
	if _pending or not _load_available or not is_instance_valid(_screen) or not _screen.visible: return
	load_game_requested.emit()
