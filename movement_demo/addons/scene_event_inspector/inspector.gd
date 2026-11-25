@tool
extends EditorInspectorPlugin

const HostScript = preload("res://scripts/world/enemy_wave_controller.gd")
const SequenceProperty = preload("res://addons/scene_event_inspector/event_sequence_property.gd")

var undo_redo: EditorUndoRedoManager


class DirectorNodePathProperty extends EditorProperty:
	var resource: Resource
	var property_name: StringName
	var host: Node
	var history: EditorUndoRedoManager
	var button: Button
	var popup: PopupPanel
	var tree: Tree

	func configure(target_resource: Resource, path_property: StringName, director_host: Node,
			undo_history: EditorUndoRedoManager, expected_types: String) -> void:
		resource = target_resource
		property_name = path_property
		host = director_host
		history = undo_history
		var row := HBoxContainer.new()
		button = Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = "从当前场景选择节点；保存值会自动转换为相对 SceneDirector 的路径。需要类型：%s" % expected_types
		button.pressed.connect(_open_picker)
		row.add_child(button)
		var clear := Button.new()
		clear.text = "清空"
		clear.pressed.connect(func(): _commit(NodePath()))
		row.add_child(clear)
		add_child(row)
		popup = PopupPanel.new()
		var content := VBoxContainer.new()
		var hint := Label.new()
		hint.text = "选择节点（将保存为相对 SceneDirector 的路径）"
		content.add_child(hint)
		tree = Tree.new()
		tree.custom_minimum_size = Vector2(460, 520)
		tree.hide_root = false
		tree.item_activated.connect(_select_tree_item)
		content.add_child(tree)
		popup.add_child(content)
		add_child(popup)
		_update_property()

	func _update_property() -> void:
		if button == null or resource == null:
			return
		var path: NodePath = resource.get(property_name)
		button.text = String(path) if not path.is_empty() else "选择节点…"

	func _open_picker() -> void:
		tree.clear()
		var scene_root := EditorInterface.get_edited_scene_root()
		if scene_root == null or not is_instance_valid(host):
			return
		_fill_tree(scene_root, null)
		popup.popup_centered(Vector2i(480, 600))

	func _fill_tree(node: Node, parent: TreeItem) -> void:
		var item := tree.create_item(parent)
		item.set_text(0, node.name)
		item.set_tooltip_text(0, String(host.get_path_to(node)))
		item.set_metadata(0, node.get_instance_id())
		for child in node.get_children():
			if not child.is_internal():
				_fill_tree(child, item)

	func _select_tree_item() -> void:
		var item := tree.get_selected()
		if item == null:
			return
		var node := instance_from_id(int(item.get_metadata(0))) as Node
		if select_node(node):
			popup.hide()

	func select_node(node: Node) -> bool:
		if not is_instance_valid(node) or not is_instance_valid(host) \
				or _top_node(host) != _top_node(node):
			return false
		_commit(host.get_path_to(node))
		return true

	func _top_node(node: Node) -> Node:
		var current := node
		while current.get_parent() != null:
			current = current.get_parent()
		return current

	func _commit(value: NodePath) -> void:
		var before: NodePath = resource.get(property_name)
		if before == value:
			return
		if history == null:
			resource.set(property_name, value)
			resource.emit_changed()
			_update_property()
			return
		history.create_action("设置场景动作节点路径", UndoRedo.MERGE_DISABLE, resource)
		history.add_do_property(resource, property_name, value)
		history.add_undo_property(resource, property_name, before)
		history.add_do_method(resource, &"emit_changed")
		history.add_undo_method(resource, &"emit_changed")
		history.commit_action()
		_update_property()


func configure(history: EditorUndoRedoManager) -> void:
	undo_redo = history


func handles_property(object: Object, property_name: String) -> bool:
	if property_name == "event_sequences" and object is Node:
		return _is_scene_event_host(object)
	return property_name == "actions" and object is SceneEventDefinition


func _can_handle(object: Object) -> bool:
	return object is SceneEventDefinition or object is SceneAction or _is_scene_event_host(object)


func _is_scene_event_host(object: Object) -> bool:
	if not object is Node:
		return false
	var script: Script = object.get_script()
	while script != null:
		if script == HostScript:
			return true
		script = script.get_base_script()
	return false


func _parse_property(object: Object, _type: Variant.Type, path: String, _hint: PropertyHint,
		hint_text: String, _usage: int, _wide: bool) -> bool:
	if object is SceneAction and _type == TYPE_NODE_PATH:
		var host := SequenceProperty.host_for(object)
		if is_instance_valid(host):
			var node_path_property := DirectorNodePathProperty.new()
			node_path_property.configure(object, StringName(path), host, undo_redo, hint_text)
			add_property_editor(path, node_path_property)
			return true
	if not handles_property(object, path):
		return false
	var property = SequenceProperty.new()
	property.configure(object, StringName(path), undo_redo)
	add_property_editor(path, property)
	return true
