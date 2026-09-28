extends CanvasLayer

var dialogue_player = null
var dialogue_resource: DialogueResource
var dialogue_line: DialogueLine
var is_loading: bool = false

@onready var dialogue_panel: PanelContainer = $DialoguePanel
@onready var dialogue_text: Label = $DialoguePanel/MarginContainer/Content/DialogueText
@onready var choices: VBoxContainer = $DialoguePanel/MarginContainer/Content/Choices


func _ready() -> void:
	dialogue_panel.hide()


func open_dialogue(player, resource: DialogueResource, start: String) -> void:
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
	dialogue_line = await dialogue_resource.get_next_dialogue_line(next_id)
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
	for button in choices.get_children():
		if not button.disabled:
			button.grab_focus()
			break


func _close_dialogue() -> void:
	dialogue_panel.hide()
	if is_instance_valid(dialogue_player):
		dialogue_player.set_dialogue_active(false)
	dialogue_player = null
	dialogue_line = null
	dialogue_resource = null
	is_loading = false
