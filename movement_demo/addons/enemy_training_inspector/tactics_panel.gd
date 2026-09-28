@tool
extends VBoxContainer

const Library = preload("res://scripts/enemy/enemy_action_library.gd")
var inspected: Object
var undo_redo: EditorUndoRedoManager
var preview_unit: EnemyUnitProfile
var rows: VBoxContainer
var signature: int = -1
var elapsed := 0.0

func configure(object: Object, history: EditorUndoRedoManager) -> void:
	inspected = object
	undo_redo = history
	var heading := Label.new()
	heading.text = "战术解锁"
	add_child(heading)
	if inspected is EnemyTrainingProfile:
		var hint := Label.new()
		hint.text = "请选择预览兵种（仅影响此面板）"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(hint)
		var picker := EditorResourcePicker.new()
		picker.base_type = "EnemyUnitProfile"
		picker.resource_changed.connect(func(resource): preview_unit = resource; refresh(true))
		add_child(picker)
	rows = VBoxContainer.new()
	add_child(rows)
	refresh(true)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= 0.25:
		elapsed = 0.0
		refresh()

func profile() -> EnemyTrainingProfile:
	if not is_instance_valid(inspected): return null
	return inspected if inspected is EnemyTrainingProfile else inspected.profile

func unit() -> EnemyUnitProfile:
	if inspected is EnemyTrainingProfile: return preview_unit
	if not is_instance_valid(inspected): return null
	var node = inspected.get_node_or_null("../UnitType")
	return node.profile if node != null else null

func refresh(force: bool = false) -> void:
	var training := profile()
	var source := unit()
	var value := hash([source.fingerprint() if source != null else 0, training.selected_tactics if training != null else [], training])
	if not force and signature == value: return
	signature = value
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	if source == null or training == null:
		_note("配置兵种与训练资源后显示可选战术。")
		return
	var resolved := Library.resolve(source, training)
	var seen: Array[StringName] = []
	for definition in source.tactical_actions:
		if definition == null or seen.has(definition.action_id): continue
		var id: StringName = definition.action_id
		seen.append(id)
		var probe := EnemyTrainingProfile.new()
		probe.selected_tactics = [id]
		var eligibility := Library.resolve(source, probe)
		var invalid: bool = not eligibility.definitions.has(id)
		var included: Array = resolved.included_by.get(id, [])
		var checkbox := CheckBox.new()
		checkbox.text = definition.display_name
		checkbox.button_pressed = resolved.definitions.has(id)
		checkbox.disabled = invalid or not included.is_empty()
		if invalid:
			checkbox.tooltip_text = "无法启用：" + "; ".join(eligibility.errors)
		elif not included.is_empty():
			var names := PackedStringArray()
			for parent in included: names.append(source.definition(parent).display_name)
			checkbox.text += "（由 %s 包含）" % "、".join(names)
			checkbox.tooltip_text = "取消相应高级项后才可单独修改；原有手动选择会保留。"
		else:
			checkbox.tooltip_text = "手动启用" if training.selected_tactics.has(id) else "尚未解锁"
		checkbox.toggled.connect(_toggle.bind(training, id))
		rows.add_child(checkbox)
		if invalid: _note(checkbox.tooltip_text)
	if seen.is_empty(): _note("此兵种尚未配置战术动作。")

func _toggle(enabled: bool, training: EnemyTrainingProfile, id: StringName) -> void:
	var before: Array[StringName] = training.selected_tactics.duplicate()
	var after: Array[StringName] = before.duplicate()
	after.erase(id)
	if enabled: after.append(id)
	undo_redo.create_action("更改敌人战术解锁", UndoRedo.MERGE_DISABLE, training)
	undo_redo.add_do_property(training, &"selected_tactics", after)
	undo_redo.add_undo_property(training, &"selected_tactics", before)
	undo_redo.add_do_method(training, &"emit_changed")
	undo_redo.add_undo_method(training, &"emit_changed")
	undo_redo.commit_action()
	refresh(true)

func _note(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(label)
