extends CanvasLayer

const Director = preload("res://scripts/systems/scene_director.gd")
const Request = preload("res://scripts/systems/scene_request.gd")
signal scene_action_finished(id: int, result: StringName)
signal scene_action_opened(id: int)
var _scene_request: Request

signal dialogue_started(source: Node)
signal dialogue_ended(source: Node)
signal camera_cue_started(cue: String)
signal scripted_seat_assigned(cue: String)

var dialogue_player = null
var dialogue_resource: DialogueResource
var dialogue_line: DialogueLine
var dialogue_text: Label
var is_loading: bool = false
var dialogue_source: Node
var _session: int = 0
var _announced: bool = false
var _pages: PackedStringArray
var _page := 0
var _skip_followup := ""
var _presenting_camera := false

const PORTRAITS := {
	"酒保": preload("res://resources/dialogue/portraits/bartender.png"),
	"{大姐头名字}": preload("res://resources/dialogue/portraits/commissioner.png"),
	"商人": preload("res://resources/dialogue/portraits/merchant.png"),
	"A": preload("res://resources/dialogue/portraits/commissioner.png"),
}
const PAGE_LENGTH := 52

@onready var dialogue_panel: PanelContainer = $DialoguePanel
@onready var transcript: ScrollContainer = $DialoguePanel/MarginContainer/Content/Transcript
@onready var history: VBoxContainer = $DialoguePanel/MarginContainer/Content/Transcript/History
@onready var choices: VBoxContainer = $DialoguePanel/MarginContainer/Content/Choices
@onready var portrait: TextureRect = $Portrait
@onready var page_hint: Label = $DialoguePanel/MarginContainer/Content/PageHint
@onready var skip_followup: Button = $DialoguePanel/MarginContainer/Content/SkipFollowup


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 交互物通过这个组打开对话，不需要知道界面在场景里的位置。
	add_to_group(&"dialogue_ui")
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()
	dialogue_panel.hide()
	portrait.hide()
	skip_followup.pressed.connect(_skip_optional_followup)


func _fit_panel() -> void:
	var width := get_viewport().get_visible_rect().size.x
	dialogue_panel.offset_left = -minf(width - 116.0, clampf(width * 0.38, 300.0, 530.0)) - 14.0
	portrait.offset_right = dialogue_panel.offset_left - 10.0
	portrait.offset_left = portrait.offset_right - 76.0


func open_dialogue(player, resource: DialogueResource, start: String, source: Node = null) -> void:
	var director = Director.for_node(self)
	if director == null: return
	var request = director.request_action(&"dialogue", {"source": source if source != null else self,
		"target": self, "player": player, "origin": &"interaction",
		"parameters": {"resource": resource, "start": start}})
	if request.is_terminal(): return
	if _scene_request == request and is_loading: await scene_action_opened

func begin_scene_action(request: Request) -> void:
	if not request.is_current() or request.kind != &"dialogue" or request.node(&"target") != self: return
	if request.parameters.get("resource") == null or request.node(&"player") == null:
		request.fail("missing_dialogue_resource_or_player")
		return
	_scene_request = request
	_session += 1
	_skip_followup = ""
	dialogue_text = null
	for row in history.get_children():
		history.remove_child(row)
		row.queue_free()
	dialogue_source = request.node(&"source")
	dialogue_player = request.node(&"player")
	dialogue_resource = request.parameters.resource
	await _show_line(request.parameters.get("start", "start"))
	scene_action_opened.emit(request.id)

func finish_scene_action(request: Request) -> void:
	if _scene_request == request: _close_authorized(&"completed")

func cancel_scene_action(request: Request, _reason: StringName) -> void:
	if _scene_request == request: _close_authorized(&"cancelled")


func _input(event: InputEvent) -> void:
	if dialogue_player == null:
		return
	var interact_pressed: bool = event.is_action_pressed("interact") and not event.is_echo()
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
		var scroll_bar := transcript.get_v_scroll_bar()
		if scroll_bar.visible and scroll_bar.get_global_rect().has_point(event.position):
			return
	if not interact_pressed and not left_click:
		return
	if _presenting_camera:
		get_viewport().set_input_as_handled()
		return

	# 出现选项后，把鼠标事件留给按钮；E 仍不能跳过分支。
	if dialogue_line != null and _page == _pages.size() - 1 and not dialogue_line.responses.is_empty():
		if interact_pressed:
			get_viewport().set_input_as_handled()
		return

	# 消费推进事件，避免同一次点击落到新出现的选项按钮上。
	get_viewport().set_input_as_handled()
	if is_loading or dialogue_line == null:
		return
	if _page < _pages.size() - 1:
		_page += 1
		_show_page()
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

	var skip := dialogue_line.get_tag_value("skip_followup")
	if not skip.is_empty():
		_skip_followup = skip
	_pages = _paginate(dialogue_line.text)
	_page = 0

	for response in dialogue_line.responses:
		var button := Button.new()
		button.text = response.text
		button.disabled = not response.is_allowed
		button.add_theme_font_size_override("font_size", 17)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(_choose_reply.bind(response.text, response.next_id))
		choices.add_child(button)

	dialogue_panel.show()
	var cue := dialogue_line.get_tag_value("camera")
	_presenting_camera = not cue.is_empty()
	_show_page()
	if not _announced:
		_announced = true
		dialogue_started.emit(dialogue_source)
	await _assign_scripted_seat(dialogue_line.get_tag_value("sit"))
	if session != _session:
		return
	await _present_dialogue_cue(cue)
	if session == _session:
		_presenting_camera = false
		is_loading = false
		_refresh_replies()
		if not cue.is_empty():
			_scroll_to_latest.call_deferred(session)


func _show_page() -> void:
	var character := dialogue_line.character
	var narration := dialogue_line.has_tag("narration") or character == "旁白" or character.is_empty()
	if not _pages[_page].is_empty():
		_append_history(character if not narration and _page == 0 else "", _pages[_page], narration)
		portrait.texture = PORTRAITS.get(character) if not narration else null
		portrait.visible = portrait.texture != null
	_refresh_replies()


func _refresh_replies() -> void:
	choices.visible = not _presenting_camera and _page == _pages.size() - 1 and not dialogue_line.responses.is_empty()
	skip_followup.visible = choices.visible and not _skip_followup.is_empty()
	page_hint.visible = not _presenting_camera and not choices.visible
	page_hint.text = "左键 / E  继续"
	if _pages.size() > 1:
		page_hint.text += "    %d / %d" % [_page + 1, _pages.size()]
	if not choices.visible:
		return
	for button in choices.get_children():
		if not button.disabled:
			button.grab_focus()
			break


func _choose_reply(text: String, next_id: String) -> void:
	if is_loading:
		return
	_skip_followup = ""
	portrait.hide()
	_append_history("主角", text, false, true)
	_show_line(next_id)


func _skip_optional_followup() -> void:
	if is_loading or _skip_followup.is_empty():
		return
	var next_id := _skip_followup
	_skip_followup = ""
	_show_line(next_id)


func _append_history(character: String, text: String, narration: bool, reply := false) -> void:
	var row := VBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	history.add_child(row)
	if not character.is_empty():
		var name_label := Label.new()
		name_label.text = character
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color("#d2a875"))
		row.add_child(name_label)
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_constant_override("line_spacing", 5)
	if narration:
		body.add_theme_color_override("font_color", Color("#b0a9a2"))
	elif reply:
		body.add_theme_color_override("font_color", Color("#d9b1a1"))
	row.add_child(body)
	dialogue_text = body
	_scroll_to_latest.call_deferred(_session)


func _scroll_to_latest(session: int) -> void:
	await get_tree().process_frame
	if session == _session:
		transcript.scroll_vertical = int(ceilf(transcript.get_v_scroll_bar().max_value))


func _present_dialogue_cue(cue: String) -> void:
	if cue.is_empty() or _scene_request == null:
		return
	var paths: Dictionary = _scene_request.parameters.get("camera_cues", {})
	if not paths.has(cue):
		return
	var target := get_node_or_null(paths[cue]) as Node3D
	var director = Director.for_node(self)
	if target == null or director == null:
		return
	var camera: Request = director.request_child(_scene_request, &"presentation", {
		"source": self, "target": target,
		"parameters": {"size": 10.0, "move_seconds": 0.6, "hold_seconds": 0.85, "return_seconds": 0.55},
	})
	if camera.has_started():
		camera_cue_started.emit(cue)
	await camera.wait_result()


func _assign_scripted_seat(cue: String) -> void:
	if cue.is_empty() or _scene_request == null:
		return
	var dialogue_request := _scene_request
	var seats: Dictionary = dialogue_request.parameters.get("seat_cues", {})
	var director = Director.for_node(self)
	if director == null:
		return
	for path: NodePath in seats.get(cue, []):
		var seat := get_node_or_null(path) as TavernSeat
		if seat == null:
			continue
		var action: Request = director.request_child(dialogue_request, &"script", {
			"source": self, "target": seat, "player": dialogue_player,
			"parameters": {"scripted": true},
		})
		var result := await action.wait_result()
		if not dialogue_request.is_current():
			return
		if result.status == &"completed":
			scripted_seat_assigned.emit(cue)
			return


func _paginate(text: String) -> PackedStringArray:
	var pages := PackedStringArray()
	var remaining := text.strip_edges()
	while remaining.length() > PAGE_LENGTH:
		var cut := PAGE_LENGTH
		for index in range(PAGE_LENGTH - 1, 27, -1):
			if remaining[index] in ["。", "！", "？", "；", "，", ".", "!", "?", " "]:
				cut = index + 1
				break
		pages.append(remaining.left(cut))
		remaining = remaining.substr(cut).strip_edges()
	pages.append(remaining)
	return pages


func _close_dialogue() -> void:
	if _scene_request != null and _scene_request.is_current():
		var director = Director.for_node(self)
		if director != null: director.finish_request(_scene_request.id)
	else: _close_authorized(&"cancelled")

func _close_authorized(result: StringName) -> void:
	var request := _scene_request
	_scene_request = null
	_session += 1
	var source := dialogue_source
	if is_instance_valid(source) and source.tree_exiting.is_connected(_close_dialogue):
		source.tree_exiting.disconnect(_close_dialogue)
	dialogue_source = null
	if _announced:
		_announced = false
		dialogue_ended.emit(source if is_instance_valid(source) else null)
	dialogue_panel.hide()
	portrait.hide()
	dialogue_player = null
	dialogue_line = null
	dialogue_resource = null
	is_loading = false
	_presenting_camera = false
	if request != null:
		scene_action_finished.emit(request.id, result)
		scene_action_opened.emit(request.id)


func _exit_tree() -> void:
	_close_authorized(&"cancelled")
