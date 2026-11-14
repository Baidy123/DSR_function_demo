extends CanvasLayer

## 只展示菜单和回传意图；暂停所有权由 SceneDirector 管理。
signal pause_requested
signal resume_requested
signal quit_requested

@onready var _main: VBoxContainer = $Backdrop/Center/Panel/Content/Main
@onready var _settings: VBoxContainer = $Backdrop/Center/Panel/Content/Settings
@onready var _quit: VBoxContainer = $Backdrop/Center/Panel/Content/Quit
@onready var _title: Label = $Backdrop/Center/Panel/Content/Title
@onready var _guide: CanvasLayer = $PlayGuide

func _ready() -> void:
	_main.get_node("Resume").pressed.connect(func(): resume_requested.emit())
	_main.get_node("Settings").pressed.connect(_show_settings)
	_main.get_node("Exit").pressed.connect(_show_quit)
	_settings.get_node("Guide").pressed.connect(_show_guide)
	_settings.get_node("Back").pressed.connect(_show_main)
	_quit.get_node("Cancel").pressed.connect(_show_main)
	_quit.get_node("Confirm").pressed.connect(func(): quit_requested.emit())
	_guide.finished.connect(_show_settings)
	_guide.get_node("Backdrop/Panel/Content/Close").text = "返回设置"
	_guide.get_node("Backdrop/Panel/Content/Hint").text = "游戏已暂停 · 滚轮查看说明 · Esc 返回设置"
	close_menu()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"ui_cancel"): return
	if not visible:
		pause_requested.emit()
		if not visible: return
	elif _guide.visible:
		_guide.close_guide()
	elif _settings.visible or _quit.visible:
		_show_main()
	else:
		resume_requested.emit()
	get_viewport().set_input_as_handled()

func open_menu() -> void:
	show()
	_show_main()

func close_menu() -> void:
	_guide.cancel()
	hide()
	if not is_inside_tree(): return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused): focused.release_focus()

func _show_main() -> void:
	_show_page(_main, "游戏暂停", _main.get_node("Resume"))

func _show_settings() -> void:
	_show_page(_settings, "设置", _settings.get_node("Guide"))

func _show_quit() -> void:
	_show_page(_quit, "退出游戏", _quit.get_node("Cancel"))

func _show_page(page: Control, title: String, focus: Button) -> void:
	_main.visible = page == _main
	_settings.visible = page == _settings
	_quit.visible = page == _quit
	_title.text = title
	focus.grab_focus()

func _show_guide() -> void:
	_guide.begin()
