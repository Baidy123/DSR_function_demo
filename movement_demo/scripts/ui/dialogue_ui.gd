extends CanvasLayer

signal dialogue_started(source: Node)
signal dialogue_ended(source: Node)

var dialogue_player = null
var dialogue_resource: DialogueResource
var dialogue_line: DialogueLine
var is_loading: bool = false
var dialogue_source: Node
var _session: int = 0
var _announced: bool = false

@onready var dialogue_panel: PanelContainer = $DialoguePanel
@onready var dialogue_text: Label = $DialoguePanel/MarginContainer/Content/DialogueText
@onready var choices: VBoxContainer = $DialoguePanel/MarginContainer/Content/Choices


func _ready() -> void:
	# 交互物通过这个组打开对话，不需要知道界面在场景里的位置。
	add_to_group(&"dialogue_ui")
	dialogue_panel.hide()


func open_dialogue(player, resource: DialogueResource, start: String, source: Node = null) -> void:
	if dialogue_player != null: _close_dialogue()
	_session += 1
	dialogue_source = source
	if is_instance_valid(source): source.tree_exiting.connect(_close_dialogue, CONNECT_ONE_SHOT)
	dialogue_player = player
	dialogue_player.set_dialogue_active(true)
	dialogue_resource = resource
	await _show_line(start)


func _input(event: InputEvent) -> void:
	if dialogue_player == null:
		return
	var interact_pressed: bool = event.is_action_pressed("interact")
	var left_click: bool = (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	)
	if left_click:
		# 独立 HUD 的按钮先交给 GUI（例如无敌开关），不能同时推进对话。
		var hovered: Control = get_viewport().gui_get_hovered_control()
		if hovered is BaseButton and not dialogue_panel.is_ancestor_of(hovered):
			return
	if not interact_pressed and not left_click:
		return

	# 出现选项后，把鼠标事件留给按钮；E 仍不能跳过分支。
	if not is_loading and dialogue_line != null and not dialogue_line.responses.is_empty():
		if interact_pressed:
			get_viewport().set_input_as_handled()
		return

	# 消费推进事件，避免同一次点击落到新出现的选项按钮上。
	get_viewport().set_input_as_handled()
	if is_loading or dialogue_line == null:
		return
	_show_line(dialogue_line.next_id)


func _show_line(next_id: String) -> void:
	if is_loading:
		return
	is_loading = true
	for button in choices.get_children():
		choices.remove_child(button)
		button.queue_free()

	# DM 决定下一句及其选项，UI 负责显示。
	var session := _session
	var request_resource := dialogue_resource
	var line: DialogueLine = await request_resource.get_next_dialogue_line(next_id, [])
	# 当前 DM 在 resource.lines 的字典中注入 resource 自身。返回的 DialogueLine
	# 已持有其引用，移除源字典的临时回链，避免结束或取消会话后留下资源循环。
	for data in request_resource.lines.values():
		if data.get("resource") == request_resource: data.erase("resource")
	if session != _session or not is_inside_tree(): return
	dialogue_line = line
	if dialogue_line == null:
		_close_dialogue()
		return

	dialogue_text.text = dialogue_line.text
	if not dialogue_line.character.is_empty():
		dialogue_text.text = dialogue_line.character + ": " + dialogue_line.text

	for response in dialogue_line.responses:
		var button := Button.new()
		button.text = response.text
		button.disabled = not response.is_allowed
		button.add_theme_font_size_override("font_size", 24)
		button.pressed.connect(_show_line.bind(response.next_id))
		choices.add_child(button)

	choices.visible = not dialogue_line.responses.is_empty()
	dialogue_panel.show()
	is_loading = false
	if not _announced:
		_announced = true
		dialogue_started.emit(dialogue_source)
	for button in choices.get_children():
		if not button.disabled:
			button.grab_focus()
			break


func _close_dialogue() -> void:
	_session += 1
	var source := dialogue_source
	if is_instance_valid(source) and source.tree_exiting.is_connected(_close_dialogue):
		source.tree_exiting.disconnect(_close_dialogue)
	dialogue_source = null
	if _announced:
		_announced = false
		dialogue_ended.emit(source if is_instance_valid(source) else null)
	dialogue_panel.hide()
	if is_instance_valid(dialogue_player):
		dialogue_player.set_dialogue_active(false)
	dialogue_player = null
	dialogue_line = null
	dialogue_resource = null
	is_loading = false


func _exit_tree() -> void:
	_close_dialogue()
