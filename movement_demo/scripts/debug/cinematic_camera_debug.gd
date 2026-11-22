extends CanvasLayer

## 调试面板：只枚举当前场景的演出镜头，并通过控制器公开接口播放或取消。

const SHOT_GROUP := &"cinematic_shot"

@onready var _debug_settings = get_node("/root/DebugSettings")
@onready var _shot_list: OptionButton = $Panel/Content/ShotList
@onready var _status: Label = $Panel/Content/Status
@onready var _play: Button = $Panel/Content/Play
@onready var _cancel: Button = $Panel/Content/Cancel

var _shots: Array[CinematicShot3D] = []
var _shot_names := PackedStringArray()
var _controller
var _notice: StringName
var _recent_result: StringName
var _scene_id := 0
var _refresh_queued := false

func _ready() -> void:
	visible = false
	_debug_settings.changed.connect(_on_debug_changed)
	get_tree().node_added.connect(_on_tree_node_added)
	get_tree().node_removed.connect(_on_tree_node_removed)
	_shot_list.item_selected.connect(_on_shot_selected)
	_play.pressed.connect(_on_play_pressed)
	_cancel.pressed.connect(_on_cancel_pressed)
	_clear_state()
	_on_debug_changed(_debug_settings.enabled)

func refresh() -> void:
	if not OS.is_debug_build():
		_clear_state()
		visible = false
		return
	var selected_id := _selected_instance_id()
	_disconnect_controller()
	_controller = null
	_shots.clear()
	_shot_names.clear()
	var current := get_tree().current_scene
	if not is_instance_valid(current):
		_notice = &""
		_recent_result = &""
		_scene_id = 0
		_render_shot_list(0)
		_render_state()
		return
	var current_id := current.get_instance_id()
	if current_id != _scene_id:
		_notice = &""
		_recent_result = &""
		_scene_id = current_id
	for node in get_tree().get_nodes_in_group(SHOT_GROUP):
		if node is CinematicShot3D and node.is_inside_tree() \
				and current.is_ancestor_of(node):
			_shots.append(node)
	_shots.sort_custom(_path_before)
	_controller = _find_controller(current)
	_connect_controller()
	_render_shot_list(selected_id)
	_render_state()

func shot_names() -> PackedStringArray:
	return _shot_names.duplicate()

func current_status() -> String:
	return _status_text()

func _on_debug_changed(enabled: bool) -> void:
	var allowed := enabled and OS.is_debug_build()
	visible = allowed
	if allowed:
		refresh()
	else:
		_clear_state()

func _on_tree_node_added(_node: Node) -> void:
	if _debug_settings.enabled: _queue_refresh()

func _on_tree_node_removed(_node: Node) -> void:
	if _debug_settings.enabled: _queue_refresh()

func _on_shot_selected(_index: int) -> void:
	_render_state()

func _on_play_pressed() -> void:
	_notice = &""
	_recent_result = &""
	var shot := _selected_shot()
	if not is_instance_valid(_controller):
		_notice = &"no_controller"
		_render_state()
		return
	if shot == null:
		_notice = &"no_shot"
		_render_state()
		return
	var admission: Dictionary = _controller.play_shot(shot)
	if not bool(admission.get("accepted", false)):
		_notice = StringName(admission.get("result", &"rejected"))
	_render_state()

func _on_cancel_pressed() -> void:
	_notice = &""
	if is_instance_valid(_controller) and _controller.cancel_shot(&"manual"):
		_recent_result = &"cancelled"
	else:
		_notice = &"not_active"
	_render_state()

func _on_controller_started(_request_id: int, _shot: CinematicShot3D) -> void:
	_notice = &""
	_recent_result = &""
	_queue_refresh()

func _on_controller_phase_changed(_request_id: int, _phase: StringName) -> void:
	_queue_refresh()

func _on_controller_finished(_request_id: int, result: StringName) -> void:
	_notice = &""
	_recent_result = result
	_queue_refresh()

func _queue_refresh() -> void:
	if _refresh_queued or not is_inside_tree(): return
	_refresh_queued = true
	_refresh_deferred.call_deferred()

func _refresh_deferred() -> void:
	_refresh_queued = false
	if is_inside_tree() and _debug_settings.enabled: refresh()

func _find_controller(current: Node):
	var found := current.find_child("CinematicCameraController", true, false)
	if found != null and found.has_method("play_shot") \
			and found.has_method("cancel_shot") and found.has_method("get_snapshot"):
		return found
	return null

func _connect_controller() -> void:
	if not is_instance_valid(_controller): return
	_controller.shot_started.connect(_on_controller_started)
	_controller.shot_phase_changed.connect(_on_controller_phase_changed)
	_controller.shot_finished.connect(_on_controller_finished)

func _disconnect_controller() -> void:
	if not is_instance_valid(_controller): return
	if _controller.shot_started.is_connected(_on_controller_started):
		_controller.shot_started.disconnect(_on_controller_started)
	if _controller.shot_phase_changed.is_connected(_on_controller_phase_changed):
		_controller.shot_phase_changed.disconnect(_on_controller_phase_changed)
	if _controller.shot_finished.is_connected(_on_controller_finished):
		_controller.shot_finished.disconnect(_on_controller_finished)

func _render_shot_list(selected_id: int) -> void:
	_shot_list.clear()
	_shot_names.clear()
	for index in _shots.size():
		var shot := _shots[index]
		var name := String(shot.name)
		var path := String(shot.get_path())
		_shot_names.append(name)
		_shot_list.add_item("%s  [%s]  pause_world=%s" % [
			name, path, str(shot.pause_world)])
		_shot_list.set_item_tooltip(index, path)
		_shot_list.set_item_metadata(index, shot.get_instance_id())
	if _shot_list.item_count == 0: return
	var selected_index := 0
	if selected_id != 0:
		for index in _shot_list.item_count:
			if int(_shot_list.get_item_metadata(index)) == selected_id:
				selected_index = index
				break
	_shot_list.select(selected_index)

func _render_state() -> void:
	_status.text = _status_text()
	_play.disabled = _shots.is_empty() or not is_instance_valid(_controller)
	var phase := _phase()
	_cancel.disabled = not is_instance_valid(_controller) or phase == &"idle"

func _clear_state() -> void:
	_disconnect_controller()
	_controller = null
	_clear_refs()
	_notice = &""
	_recent_result = &""
	_scene_id = 0
	_refresh_queued = false
	if is_node_ready():
		_render_state()

func _clear_refs() -> void:
	_shots.clear()
	_shot_names.clear()
	if not is_node_ready(): return
	_shot_list.clear()
	_shot_list.select(-1)

func _selected_shot() -> CinematicShot3D:
	var index := _shot_list.selected
	if index < 0 or index >= _shots.size(): return null
	var shot := _shots[index]
	return shot if is_instance_valid(shot) else null

func _selected_instance_id() -> int:
	var shot := _selected_shot()
	return shot.get_instance_id() if shot != null else 0

func _phase() -> StringName:
	if not is_instance_valid(_controller): return &"idle"
	return _controller.get_snapshot().get("phase", &"idle")

func _status_text() -> String:
	var phase := _phase()
	var parts := PackedStringArray([String(phase)])
	var shot := _selected_shot()
	if phase != &"idle" and shot != null and shot.pause_world:
		parts.append("pause_world=true")
	if not _notice.is_empty():
		parts.append(String(_notice))
	elif is_instance_valid(_controller):
		var last_error: StringName = _controller.get_snapshot().get("last_error", &"")
		if not last_error.is_empty():
			parts.append(String(last_error))
		elif not _recent_result.is_empty():
			parts.append(String(_recent_result))
	elif not _recent_result.is_empty():
		parts.append(String(_recent_result))
	return " | ".join(parts)

func _path_before(left: CinematicShot3D, right: CinematicShot3D) -> bool:
	return String(left.get_path()) < String(right.get_path())

func _exit_tree() -> void:
	if is_instance_valid(_debug_settings) \
			and _debug_settings.changed.is_connected(_on_debug_changed):
		_debug_settings.changed.disconnect(_on_debug_changed)
	var tree := get_tree()
	if tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.disconnect(_on_tree_node_added)
	if tree.node_removed.is_connected(_on_tree_node_removed):
		tree.node_removed.disconnect(_on_tree_node_removed)
	_disconnect_controller()
