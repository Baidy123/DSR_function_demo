@tool
extends SceneTree

const ActionPicker = preload("res://addons/scene_event_inspector/action_picker.gd")
const SequenceProperty = preload("res://addons/scene_event_inspector/event_sequence_property.gd")
const SceneEventInspector = preload("res://addons/scene_event_inspector/inspector.gd")
const HostScript = preload("res://scripts/world/enemy_wave_controller.gd")

const TEMP_SCENE := "res://tests/.scene_event_inspector_roundtrip.tscn"
const TEMP_ACTION := "res://tests/.scene_event_shared_action.tres"
const EXPECTED_CHECKS := 25

var checks := 0
var failures := 0

class SignalProbe extends Node:
	signal ping(value: int)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	var bridge := EditorPlugin.new()
	var history := bridge.get_undo_redo()
	_check_registry()
	await _check_inspector_routing(history)
	_check_array_editing(history)
	_check_duplication()
	_check_persistence()
	_cleanup()
	if checks != EXPECTED_CHECKS:
		failures += 1
		push_error("检查数量不符：期望 %d，实际 %d" % [EXPECTED_CHECKS, checks])
	print("Scene event inspector: %d checks; %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _check_registry() -> void:
	check(ActionPicker.category_names() == PackedStringArray([
		"流程", "战斗", "演出", "角色/NPC", "世界", "状态", "场景切换", "高级"
	]), "动作选择器按设计顺序显示八个分类")
	var entries: Array[Dictionary] = ActionPicker.registry()
	check(entries.size() == 19, "动作选择器完整列出十八个类型化动作和一个高级适配器")
	check(entries.all(func(entry): return entry.has("icon") and not String(entry.icon).is_empty()),
		"显式动作注册表为每个条目提供图标提示")
	var all_actions := true
	var all_summaries := true
	for entry in entries:
		var action := ActionPicker.create_action(entry.id)
		all_actions = all_actions and action is SceneAction
		all_summaries = all_summaries and not SequenceProperty.action_summary(action, 0).is_empty()
	check(all_actions, "注册表中的每一项都创建明确的 SceneAction 子类型")
	check(all_summaries, "每种新建动作在尚未配置时也能安全生成摘要")
	var move := MoveActorAction.new()
	move.actor_path = ^"Runner"
	move.route_path = ^"RunnerToStaffDoor"
	check(SequenceProperty.action_summary(move, 2) == "03 角色/NPC：Runner 沿 RunnerToStaffDoor 移动",
		"折叠摘要包含序号、类别、角色和路线")


func _check_inspector_routing(history: EditorUndoRedoManager) -> void:
	var host := Node3D.new()
	host.set_script(HostScript)
	var event := SceneEventDefinition.new()
	var inspector = SceneEventInspector.new()
	inspector.configure(history)
	var derived_script := GDScript.new()
	derived_script.source_code = "@tool\nextends \"res://scripts/world/enemy_wave_controller.gd\"\n"
	derived_script.reload()
	var derived_host := Node3D.new()
	derived_host.set_script(derived_script)
	check(inspector.handles_property(host, "event_sequences") \
		and inspector.handles_property(derived_host, "event_sequences"),
		"插件接管真实导演宿主及其派生脚本的事件序列")
	check(inspector.handles_property(event, "actions"), "插件接管事件资源的动作队列")
	check(not inspector.handles_property(event, "conditions"), "条件数组仍使用原生 Resource 编辑器")
	EditorInterface.edit_resource(event)
	for frame in 20:
		await process_frame
	var found_native_property := false
	for node in _descendants(EditorInterface.get_inspector()):
		if node.get_script() == SequenceProperty and node.get_edited_object() == event \
				and node.get_edited_property() == "actions":
			found_native_property = true
			break
	check(found_native_property, "启用插件后原生检查器实际挂载动作队列控件")
	var target := Node3D.new()
	target.name = "Target"
	host.add_child(target)
	var move := MoveActorAction.new()
	SequenceProperty.bind_host(move, host)
	EditorInterface.edit_resource(move)
	for frame in 20:
		await process_frame
	var path_editor: EditorProperty
	for node in _descendants(EditorInterface.get_inspector()):
		if node is EditorProperty and node.get_edited_object() == move \
				and node.get_edited_property() == "target_path" and node.has_method(&"select_node"):
			path_editor = node
			break
	var selected: bool = path_editor != null and bool(path_editor.call(&"select_node", target))
	check(selected and move.target_path == ^"Target" and host.get_node_or_null(move.target_path) == target,
		"动作节点选择器保存可由 SceneDirector 直接解析的相对路径")
	derived_host.free()
	host.free()


func _check_array_editing(history: EditorUndoRedoManager) -> void:
	var event := SceneEventDefinition.new()
	var property = SequenceProperty.new()
	property.configure(event, &"actions", history)
	var wait := WaitAction.new()
	var move := MoveActorAction.new()
	property.add_item(wait)
	property.add_item(move)
	check(event.actions.size() == 2 and event.actions[0] == wait and event.actions[1] == move,
		"添加动作保持线性队列顺序")
	var second_row = property.rows.get_child(1)
	var first_row = property.rows.get_child(0)
	var drag_data = second_row._get_drag_data(Vector2.ZERO)
	first_row._drop_data(Vector2.ZERO, drag_data)
	check(event.actions[0] == move, "动作可通过队列行拖放排序")
	property.duplicate_item(0)
	check(event.actions.size() == 3 and event.actions[1] is MoveActorAction \
		and event.actions[1] != move, "复制动作生成独立的内建资源")
	property.remove_item(2)
	check(event.actions.size() == 2, "动作可从队列删除")
	var resource_history := history.get_history_undo_redo(history.get_object_history_id(event))
	if resource_history == null:
		resource_history = history.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
	property.free()
	check(resource_history != null and resource_history.undo() and event.actions.size() == 3,
		"队列控件销毁后一次原生 Undo 仍恢复一次删除操作")
	check(resource_history != null and resource_history.redo() and event.actions.size() == 2,
		"队列控件销毁后一次原生 Redo 仍重做一次删除操作")
	var host := Node3D.new()
	host.set_script(HostScript)
	var signal_probe := SignalProbe.new()
	signal_probe.name = "SignalProbe"
	host.add_child(signal_probe)
	var valid_route := TavernRoute.new()
	valid_route.name = "ValidRoute"
	host.add_child(valid_route)
	var events_property = SequenceProperty.new()
	# Diagnostics do not need another editor history entry; the host is deliberately
	# detached so this fixture cannot affect the currently open scene history.
	events_property.configure(host, &"event_sequences", null)
	var first := SceneEventDefinition.new()
	first.event_id = &"duplicate"
	var missing_move := MoveActorAction.new()
	missing_move.actor_path = ^"MissingActor"
	missing_move.route_path = ^"ValidRoute"
	var invalid_audio := PlayAudioAction.new()
	invalid_audio.target_path = ^"ValidRoute"
	first.actions = [missing_move, SetDoorAction.new(), SetFlagAction.new(), invalid_audio]
	first.conditions = [SceneQuestCondition.new()]
	var missing_trigger := SceneEventTrigger.new()
	missing_trigger.source_path = ^"MissingSource"
	missing_trigger.signal_name = &"started"
	var invalid_filter_trigger := SceneEventTrigger.new()
	invalid_filter_trigger.source_path = ^"SignalProbe"
	invalid_filter_trigger.signal_name = &"ping"
	var invalid_filter := SceneEventFilter.new()
	invalid_filter.parameter_index = 1
	invalid_filter_trigger.filters = [invalid_filter]
	first.triggers = [missing_trigger, invalid_filter_trigger]
	var second := SceneEventDefinition.new()
	second.event_id = &"duplicate"
	events_property.add_item(first)
	events_property.add_item(second)
	check("Event ID 重复" in events_property.diagnostics_label.text \
		and "没有动作" in events_property.diagnostics_label.text \
		and "来源不存在" in events_property.diagnostics_label.text \
		and "目标不存在" in events_property.diagnostics_label.text \
		and "过滤器" in events_property.diagnostics_label.text \
		and "缺少必填路径 door_path" in events_property.diagnostics_label.text \
		and "缺少必填路径 controller_path" in events_property.diagnostics_label.text \
		and "音频目标必须" in events_property.diagnostics_label.text \
		and not "state_path 目标不存在：/root/GameState" in events_property.diagnostics_label.text \
		and not "route_path 类型不匹配" in events_property.diagnostics_label.text,
		"事件队列诊断触发/过滤器、必填路径和目标能力，同时接受 autoload 与自定义类型")
	events_property.queue_free()
	host.free()


func _check_duplication() -> void:
	var source := SceneEventDefinition.new()
	source.event_id = &"source"
	var move := MoveActorAction.new()
	move.actor_path = ^"Runner"
	source.actions = [move]
	var copy: SceneEventDefinition = SequenceProperty.duplicate_inline_resource(source)
	(copy.actions[0] as MoveActorAction).actor_path = ^"CopyRunner"
	copy.event_id = &"copy"
	check(copy != source and copy.actions[0] != source.actions[0],
		"复制事件会递归复制内建动作")
	check(source.event_id == &"source" and (source.actions[0] as MoveActorAction).actor_path == ^"Runner",
		"修改复制项不会污染来源事件")


func _check_persistence() -> void:
	_cleanup()
	var shared := WaitAction.new()
	shared.seconds = 1.75
	check(ResourceSaver.save(shared, TEMP_ACTION) == OK, "外部动作资源可显式保存")
	shared = load(TEMP_ACTION)

	var root := Node3D.new()
	root.name = "Root"
	var host := Node3D.new()
	host.name = "Director"
	host.set_script(HostScript)
	root.add_child(host)
	host.owner = root
	var event := SceneEventDefinition.new()
	event.event_id = &"roundtrip"
	var move := MoveActorAction.new()
	move.actor_path = ^"Runner"
	move.route_path = ^"RunnerToStaffDoor"
	move.speed_override = 3.25
	event.actions = [move, shared, shared]
	var events: Array[SceneEventDefinition] = [event]
	host.event_sequences = events
	var packed := PackedScene.new()
	var saved := packed.pack(root) == OK and ResourceSaver.save(packed, TEMP_SCENE) == OK
	root.free()
	check(saved, "包含内建事件资源的场景可以保存")
	var loaded: PackedScene = ResourceLoader.load(TEMP_SCENE, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var instance := loaded.instantiate() if loaded != null else null
	var loaded_host = instance.get_node("Director") if instance != null else null
	var loaded_event: SceneEventDefinition = loaded_host.event_sequences[0] if loaded_host != null else null
	var loaded_move: MoveActorAction = loaded_event.actions[0] if loaded_event != null else null
	check(loaded_move != null and loaded_move.actor_path == ^"Runner" \
		and loaded_move.route_path == ^"RunnerToStaffDoor" \
		and is_equal_approx(loaded_move.speed_override, 3.25),
		"保存重载保留动作类型、NodePath 和参数")
	check(loaded_event != null and loaded_event.actions[1] == loaded_event.actions[2] \
		and not loaded_event.actions[1].resource_path.is_empty(),
		"显式外部动作在多个引用间保持共享")
	var loaded_copy: SceneEventDefinition = SequenceProperty.duplicate_inline_resource(loaded_event)
	(loaded_copy.actions[0] as MoveActorAction).actor_path = ^"CopiedRunner"
	check(loaded_copy != loaded_event and loaded_copy.actions[0] != loaded_event.actions[0] \
		and (loaded_event.actions[0] as MoveActorAction).actor_path == ^"Runner" \
		and loaded_copy.actions[1] == loaded_event.actions[1],
		"保存重载后的场景内建事件仍深复制，而外部动作继续共享")
	if instance != null:
		instance.free()


func _cleanup() -> void:
	for path in [TEMP_SCENE, TEMP_ACTION]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


func check(value: bool, label: String) -> void:
	checks += 1
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
