@tool
extends EditorProperty

const ActionPicker = preload("res://addons/scene_event_inspector/action_picker.gd")
static var _host_bindings: Dictionary = {}

var edited_object: Object
var array_property: StringName
var undo_redo: EditorUndoRedoManager
var rows: VBoxContainer
var diagnostics_label: Label


class ReorderRow extends HBoxContainer:
	signal reorder_requested(from: int, to: int)
	var item_index := -1
	var scope_token: String

	func configure(index: int, token: String) -> void:
		item_index = index
		scope_token = token
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		tooltip_text = "拖动可调整队列顺序"

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if is_inside_tree():
			var preview := Label.new()
			preview.text = "移动第 %d 项" % (item_index + 1)
			set_drag_preview(preview)
		return {"scene_event_queue": scope_token, "from": item_index}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.get("scene_event_queue", "") == scope_token \
			and int(data.get("from", -1)) != item_index

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if _can_drop_data(_at_position, data):
			reorder_requested.emit(int(data.from), item_index)


func configure(object: Object, property_name: StringName, history: EditorUndoRedoManager) -> void:
	edited_object = object
	array_property = property_name
	undo_redo = history
	_build()
	refresh()


func _build() -> void:
	if rows != null:
		return
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	if array_property == &"actions":
		var picker = ActionPicker.new()
		picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picker.action_selected.connect(add_item)
		header.add_child(picker)
	else:
		var add_button := Button.new()
		add_button.text = "添加事件"
		add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_button.pressed.connect(func(): add_item(SceneEventDefinition.new()))
		header.add_child(add_button)
	panel.add_child(header)
	rows = VBoxContainer.new()
	panel.add_child(rows)
	diagnostics_label = Label.new()
	diagnostics_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	diagnostics_label.modulate = Color(1.0, 0.55, 0.4)
	panel.add_child(diagnostics_label)
	add_child(panel)
	set_bottom_editor(panel)


func _update_property() -> void:
	refresh()


func refresh() -> void:
	if rows == null or edited_object == null:
		return
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var values: Array = edited_object.get(array_property)
	for index in values.size():
		rows.add_child(_row(values[index], index, values.size()))
	diagnostics_label.text = "\n".join(_diagnostics(values))


func _row(item: Variant, index: int, total: int) -> Control:
	var row := ReorderRow.new()
	row.configure(index, "%d:%s" % [edited_object.get_instance_id(), array_property])
	row.reorder_requested.connect(move_item)
	var summary := Button.new()
	summary.flat = true
	summary.alignment = HORIZONTAL_ALIGNMENT_LEFT
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.text = event_summary(item, index) if array_property == &"event_sequences" \
		else action_summary(item, index)
	summary.disabled = not item is Resource
	if item is Resource:
		if is_external_resource(item):
			summary.text = "🔗 " + summary.text
			summary.tooltip_text = "外部资源：多个引用会共享修改。"
		summary.pressed.connect(_edit_item.bind(item))
	row.add_child(summary)
	row.add_child(_button("↑", index > 0, move_item.bind(index, index - 1)))
	row.add_child(_button("↓", index + 1 < total, move_item.bind(index, index + 1)))
	var duplicate_button := _button("共享引用" if item is Resource and is_external_resource(item) \
		else "复制", item is Resource, duplicate_item.bind(index))
	if item is Resource and is_external_resource(item):
		duplicate_button.tooltip_text = "新增同一外部 .tres 的共享引用；修改会影响所有引用。"
	row.add_child(duplicate_button)
	row.add_child(_button("删除", true, remove_item.bind(index)))
	return row


func _edit_item(item: Resource) -> void:
	var host: Node
	if array_property == &"event_sequences" and edited_object is Node:
		host = edited_object
	elif array_property == &"actions" and edited_object is Resource:
		host = host_for(edited_object)
	if is_instance_valid(host):
		bind_host(item, host)
	EditorInterface.edit_resource(item)


static func bind_host(resource: Resource, host: Node) -> void:
	if resource == null or not is_instance_valid(host):
		return
	_host_bindings[resource.get_instance_id()] = {
		"resource": weakref(resource),
		"host": weakref(host),
	}


static func host_for(resource: Resource) -> Node:
	if resource == null:
		return null
	var entry: Dictionary = _host_bindings.get(resource.get_instance_id(), {})
	if entry.is_empty() or entry.resource.get_ref() != resource:
		_host_bindings.erase(resource.get_instance_id())
		return null
	var host: Node = entry.host.get_ref()
	if not is_instance_valid(host):
		_host_bindings.erase(resource.get_instance_id())
		return null
	return host


func _button(label: String, enabled: bool, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.disabled = not enabled
	button.pressed.connect(callback)
	return button


func add_item(item: Variant) -> void:
	if item == null:
		return
	var before: Array = edited_object.get(array_property).duplicate()
	var after: Array = before.duplicate()
	after.append(item)
	_commit_array("添加场景事件动作" if array_property == &"actions" else "添加场景事件", before, after)


func remove_item(index: int) -> void:
	var before: Array = edited_object.get(array_property).duplicate()
	if index < 0 or index >= before.size():
		return
	var after: Array = before.duplicate()
	after.remove_at(index)
	_commit_array("删除场景事件项", before, after)


func move_item(from: int, to: int) -> void:
	var before: Array = edited_object.get(array_property).duplicate()
	if from < 0 or from >= before.size() or to < 0 or to >= before.size() or from == to:
		return
	var after: Array = before.duplicate()
	var item = after.pop_at(from)
	after.insert(to, item)
	_commit_array("排序场景事件项", before, after)


func duplicate_item(index: int) -> void:
	var before: Array = edited_object.get(array_property).duplicate()
	if index < 0 or index >= before.size() or not before[index] is Resource:
		return
	var after: Array = before.duplicate()
	after.insert(index + 1, duplicate_inline_resource(before[index]))
	_commit_array("复制场景事件项", before, after)


func _commit_array(title: String, before: Array, after: Array) -> void:
	if undo_redo == null:
		edited_object.set(array_property, after)
		_after_change()
		return
	undo_redo.create_action(title, UndoRedo.MERGE_DISABLE, edited_object)
	undo_redo.add_do_property(edited_object, array_property, after)
	undo_redo.add_undo_property(edited_object, array_property, before)
	undo_redo.add_do_method(edited_object, &"notify_property_list_changed")
	undo_redo.add_undo_method(edited_object, &"notify_property_list_changed")
	if edited_object is Resource:
		undo_redo.add_do_method(edited_object, &"emit_changed")
		undo_redo.add_undo_method(edited_object, &"emit_changed")
	undo_redo.commit_action()
	refresh()


func _after_change() -> void:
	if edited_object is Resource:
		edited_object.emit_changed()
	refresh()


func _diagnostics(values: Array) -> PackedStringArray:
	var messages := PackedStringArray()
	for index in values.size():
		if values[index] == null:
			messages.append("第 %d 项为空。" % (index + 1))
	if array_property == &"event_sequences":
		var ids := {}
		for index in values.size():
			var event := values[index] as SceneEventDefinition
			if event == null:
				continue
			if event.event_id.is_empty():
				messages.append("第 %d 个事件缺少 Event ID。" % (index + 1))
			elif ids.has(event.event_id):
				messages.append("Event ID 重复：%s。" % event.event_id)
			else:
				ids[event.event_id] = true
			if event.actions.is_empty():
				messages.append("事件 %s 没有动作。" % event.event_id)
			for trigger_index in event.triggers.size():
				messages.append_array(_trigger_diagnostics(event.triggers[trigger_index],
					"事件 %s 触发器 %d" % [event.event_id, trigger_index + 1]))
			for condition_index in event.conditions.size():
				messages.append_array(_resource_target_diagnostics(event.conditions[condition_index],
					"事件 %s 条件 %d" % [event.event_id, condition_index + 1]))
			for action_index in event.actions.size():
				messages.append_array(_resource_target_diagnostics(event.actions[action_index],
					"事件 %s 动作 %d" % [event.event_id, action_index + 1]))
	return messages


func _resource_target_diagnostics(resource: Resource, prefix: String) -> PackedStringArray:
	var messages := PackedStringArray()
	if resource == null:
		messages.append(prefix + " 为空。")
		return messages
	for required_path in _required_paths(resource):
		var required_value: NodePath = resource.get(required_path)
		if required_value.is_empty():
			messages.append("%s 缺少必填路径 %s。" % [prefix, required_path])
	if resource is MoveActorAction and resource.target_path.is_empty() == resource.route_path.is_empty():
		messages.append(prefix + " 必须且只能设置目标点或路线之一。")
	if resource is WaitSignalAction:
		messages.append_array(_trigger_diagnostics(resource.trigger, prefix + " 等待信号"))
	for property in resource.get_property_list():
		if int(property.type) != TYPE_NODE_PATH or not (int(property.usage) & PROPERTY_USAGE_STORAGE):
			continue
		var path: NodePath = resource.get(property.name)
		if path.is_empty():
			continue
		var target: Node = _resolve_editor_target(path)
		if target == null:
			if not _is_declared_autoload(path):
				messages.append("%s 的 %s 目标不存在：%s。" % [prefix, property.name, path])
			continue
		if int(property.hint) == PROPERTY_HINT_NODE_PATH_VALID_TYPES:
			var allowed := String(property.hint_string).split(",", false)
			var valid_type := allowed.is_empty()
			for type_name in allowed:
				if _node_matches_type(target, type_name.strip_edges()):
					valid_type = true
					break
			if not valid_type:
				messages.append("%s 的 %s 类型不匹配：需要 %s，实际 %s。" % [prefix,
					property.name, property.hint_string, target.get_class()])
		messages.append_array(_capability_diagnostics(resource, StringName(property.name), target, prefix))
	return messages


func _trigger_diagnostics(trigger: SceneEventTrigger, prefix: String) -> PackedStringArray:
	var messages := PackedStringArray()
	if trigger == null:
		messages.append(prefix + " 为空。")
		return messages
	if trigger.source_path.is_empty():
		messages.append(prefix + " 缺少来源节点。")
		return messages
	var source: Node = _resolve_editor_target(trigger.source_path)
	if source == null:
		if not _is_declared_autoload(trigger.source_path):
			messages.append("%s 来源不存在：%s。" % [prefix, trigger.source_path])
		return messages
	if trigger.signal_name.is_empty() or not source.has_signal(trigger.signal_name):
		messages.append("%s 信号不存在：%s.%s。" % [prefix, trigger.source_path, trigger.signal_name])
		return messages
	var arguments: Array = []
	for metadata in source.get_signal_list():
		if metadata.name == trigger.signal_name:
			arguments = metadata.args
			break
	if arguments.size() > 8:
		messages.append("%s 的信号参数超过支持的 8 个。" % prefix)
		return messages
	for filter_index in trigger.filters.size():
		var filter := trigger.filters[filter_index]
		if filter == null:
			messages.append("%s 的过滤器 %d 为空。" % [prefix, filter_index + 1])
			continue
		var error: String = filter.validate(arguments)
		if not error.is_empty():
			messages.append("%s 的过滤器 %d：%s" % [prefix, filter_index + 1, error])
	return messages


func _required_paths(resource: Resource) -> PackedStringArray:
	if resource is SpawnWaveAction or resource is WaitWaveClearedAction:
		return PackedStringArray(["wave_path"])
	if resource is CameraAction or resource is PlayAudioAction or resource is RunProviderAction:
		return PackedStringArray(["target_path"])
	if resource is DialogueAction:
		return PackedStringArray(["target_path", "player_path"])
	if resource is MoveActorAction or resource is SetActorVisibleAction:
		return PackedStringArray(["actor_path"])
	if resource is SeatActorAction:
		return PackedStringArray(["actor_path", "seat_path"])
	if resource is SetDoorAction:
		return PackedStringArray(["door_path"])
	if resource is CallInteractionAction:
		return PackedStringArray(["interaction_path", "player_path"])
	if resource is GiveEquipmentAction:
		return PackedStringArray(["grant_path"])
	if resource is SetFlagAction:
		return PackedStringArray(["state_path"])
	if resource is UpdateQuestAction:
		return PackedStringArray(["controller_path"])
	if resource is SceneFlagCondition or resource is SceneItemCondition:
		return PackedStringArray(["state_path"])
	if resource is SceneMethodCondition or resource is SceneNodeCondition:
		return PackedStringArray(["target_path"])
	if resource is SceneQuestCondition:
		return PackedStringArray(["controller_path"])
	if resource is SceneWaveCondition:
		return PackedStringArray(["wave_path"])
	return PackedStringArray()


func _capability_diagnostics(resource: Resource, property_name: StringName,
		target: Node, prefix: String) -> PackedStringArray:
	var messages := PackedStringArray()
	var required_methods := PackedStringArray()
	if resource is MoveActorAction and property_name == &"actor_path" \
			or resource is SetDoorAction and property_name == &"door_path" \
			or resource is GiveEquipmentAction and property_name == &"grant_path" \
			or resource is RunProviderAction and property_name == &"target_path":
		required_methods = PackedStringArray(["begin_scene_action", "cancel_scene_action"])
	elif resource is CallInteractionAction and property_name == &"interaction_path":
		required_methods = PackedStringArray(["execute_scene_interaction"])
	elif resource is SetFlagAction and property_name == &"state_path":
		required_methods = PackedStringArray(["set_flag"])
	elif resource is UpdateQuestAction and property_name == &"controller_path":
		var quest_methods := [&"accept", &"refuse", &"complete", &"fail", &"set_status"]
		required_methods = PackedStringArray([quest_methods[int(resource.operation)]])
	elif resource is SceneFlagCondition and property_name == &"state_path":
		required_methods = PackedStringArray(["get_flag"])
	elif resource is SceneItemCondition and property_name == &"state_path":
		required_methods = PackedStringArray(["get_item_count"])
	elif resource is SceneQuestCondition and property_name == &"controller_path":
		required_methods = PackedStringArray(["status_of"])
	elif resource is SceneMethodCondition and property_name == &"target_path":
		if resource.method.is_empty() or not target.has_method(resource.method):
			messages.append("%s 的查询方法不存在：%s。" % [prefix, resource.method])
	if resource is PlayAudioAction and property_name == &"target_path" \
			and not target is AudioStreamPlayer and not target is AudioStreamPlayer3D:
		messages.append(prefix + " 的音频目标必须是 AudioStreamPlayer 或 AudioStreamPlayer3D。")
	for method in required_methods:
		if not target.has_method(method):
			messages.append("%s 的 %s 缺少接口 %s。" % [prefix, property_name, method])
	return messages


func _is_declared_autoload(path: NodePath) -> bool:
	var text := String(path)
	if not text.begins_with("/root/"):
		return false
	var autoload_name := text.trim_prefix("/root/").get_slice("/", 0)
	return not autoload_name.is_empty() and ProjectSettings.has_setting("autoload/" + autoload_name)


func _resolve_editor_target(path: NodePath) -> Node:
	if path.is_empty() or not edited_object is Node:
		return null
	if path.is_absolute() and not edited_object.is_inside_tree():
		return null
	return edited_object.get_node_or_null(path)


static func _node_matches_type(target: Node, type_name: String) -> bool:
	if target.is_class(type_name):
		return true
	var script: Script = target.get_script()
	var global_classes: Array[Dictionary] = ProjectSettings.get_global_class_list()
	while script != null:
		for entry in global_classes:
			if String(entry.get("class", "")) == type_name \
					and String(entry.get("path", "")) == script.resource_path:
				return true
		script = script.get_base_script()
	return false


static func event_summary(event: Variant, index: int) -> String:
	if not event is SceneEventDefinition:
		return "%02d 空事件" % (index + 1)
	var name: String = event.label.strip_edges()
	if name.is_empty():
		name = String(event.event_id)
	if name.is_empty():
		name = "未命名事件"
	return "%02d 事件：%s（%d 个动作）" % [index + 1, name, event.actions.size()]


static func action_summary(action: Variant, index: int) -> String:
	if not action is SceneAction:
		return "%02d 空动作" % (index + 1)
	var entry := ActionPicker.entry_for_action(action)
	var category := "未分类"
	var detail: String = action.get_class()
	if not entry.is_empty():
		category = ActionPicker.CATEGORY_NAMES[entry.category]
		detail = entry.name
	if action is MoveActorAction:
		var actor := _node_name(action.actor_path)
		if not action.route_path.is_empty():
			detail = "%s 沿 %s 移动" % [actor, _node_name(action.route_path)]
		else:
			detail = "%s 移动到 %s" % [actor, _node_name(action.target_path)]
	elif action is SeatActorAction:
		detail = "%s %s %s" % [_node_name(action.actor_path), "入座" if action.mode == SeatActorAction.Mode.SIT else "离席", _node_name(action.seat_path)]
	elif action is SetActorVisibleAction:
		detail = "%s%s" % ["显示" if action.visible else "隐藏", _node_name(action.actor_path)]
	elif action is SpawnWaveAction:
		detail = "生成 %s" % _node_name(action.wave_path)
	elif action is WaitWaveClearedAction:
		detail = "等待 %s 清场" % _node_name(action.wave_path)
	elif action is CameraAction:
		detail = "镜头展示 %s" % _node_name(action.target_path)
	elif action is DialogueAction:
		detail = "触发对话 %s" % (action.dialogue.resource_path.get_file() \
			if action.dialogue != null else "未指定")
	elif action is SetDoorAction:
		detail = "%s %s" % ["打开" if action.open else "关闭", _node_name(action.door_path)]
	elif action is SetFlagAction:
		detail = "设置 %s = %s" % [action.flag, action.value]
	elif action is UpdateQuestAction:
		detail = "更新任务 %s" % action.quest_id
	return "%02d %s：%s" % [index + 1, category, detail]


static func duplicate_inline_resource(source: Resource) -> Resource:
	if source == null or is_external_resource(source):
		return source
	var copy := source.duplicate(false)
	for property in source.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE):
			continue
		var property_name: StringName = property.name
		if property_name in [&"script", &"resource_name", &"resource_path", &"resource_local_to_scene"]:
			continue
		copy.set(property_name, _duplicate_value(source.get(property_name)))
	return copy


static func _duplicate_value(value: Variant) -> Variant:
	if value is Resource:
		return value if is_external_resource(value) else duplicate_inline_resource(value)
	if value is Array:
		var array: Array = value.duplicate()
		for index in array.size():
			array[index] = _duplicate_value(array[index])
		return array
	if value is Dictionary:
		var dictionary: Dictionary = value.duplicate()
		for key in dictionary.keys():
			dictionary[key] = _duplicate_value(dictionary[key])
		return dictionary
	return value


static func is_external_resource(resource: Resource) -> bool:
	if resource == null or resource.resource_path.is_empty():
		return false
	# Saved scene-local subresources use `scene.tscn::SubResource_*`; they still
	# belong to that scene and must be cloned. A path without `::` is a true
	# external resource whose sharing is intentional.
	return not "::" in resource.resource_path


static func _node_name(path: NodePath) -> String:
	if path.is_empty():
		return "未指定"
	return String(path).get_file()
