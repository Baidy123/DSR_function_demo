@tool
extends EditorProperty

const Canvas = preload("res://addons/weapon_mode_inspector/shotgun_pattern_canvas.gd")
const PRESETS = [preload("res://resources/weapons/patterns/balanced.tres"),
	preload("res://resources/weapons/patterns/horizontal.tres"), preload("res://resources/weapons/patterns/vertical.tres")]
var canvas := Canvas.new()
var counter := Label.new()
var presets := OptionButton.new()
var clear_button := Button.new()
var save_button := Button.new()
var copy_button := Button.new()
var status := Label.new()
var copy_dialog := FileDialog.new()
var _pending_copy: ShotgunPattern
var _undo_redo: EditorUndoRedoManager


func _init() -> void:
	var bridge := EditorPlugin.new()
	_undo_redo = bridge.get_undo_redo()
	bridge.free()
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	add_child(content)
	set_bottom_editor(content)
	var hint := Label.new()
	hint.text = "左键加点 · 拖动移动 · 右键删点"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(hint)
	content.add_child(canvas)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.points_edited.connect(_commit_points)
	add_focusable(canvas)
	content.add_child(counter)
	var tools := HBoxContainer.new()
	content.add_child(tools)
	presets.add_item("载入图样…")
	for preset in PRESETS: presets.add_item(preset.display_name)
	presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	presets.item_selected.connect(_select_preset)
	tools.add_child(presets)
	clear_button.text = "清空"
	clear_button.pressed.connect(func(): _commit_points(PackedVector2Array()))
	tools.add_child(clear_button)
	var saving := HBoxContainer.new()
	content.add_child(saving)
	save_button.text = "保存当前"
	save_button.pressed.connect(_save_current)
	saving.add_child(save_button)
	copy_button.text = "另存副本…"
	copy_button.pressed.connect(_save_copy)
	saving.add_child(copy_button)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status)
	copy_dialog.title = "另存霰弹图样副本"
	copy_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	copy_dialog.access = FileDialog.ACCESS_RESOURCES
	copy_dialog.add_filter("*.tres", "霰弹图样资源")
	copy_dialog.file_selected.connect(_save_copy_to_path)
	copy_dialog.canceled.connect(func(): _pending_copy = null)
	add_child(copy_dialog)


func _update_property() -> void:
	var pattern := get_edited_object() as ShotgunPattern
	if pattern == null: return
	canvas.set_points(pattern.points)
	counter.text = "%d / 64 颗弹丸" % pattern.points.size() if not pattern.points.is_empty() else "0 个点；运行时会回退为中心 1 颗"
	var external := not pattern.resource_path.is_empty() and not pattern.is_built_in()
	save_button.disabled = canvas.read_only or not external
	save_button.tooltip_text = "保存到 " + pattern.resource_path if external else "内嵌或未保存图样请另存副本，再拖到武器的 Pattern。"


func _commit_points(value: PackedVector2Array) -> void:
	if canvas.read_only: return
	var pattern := get_edited_object() as ShotgunPattern
	if pattern == null or value == pattern.points: return
	# 每次点击／拖动是一条独立的原生撤销记录，不能把连续画点合并成整幅图的一次撤销。
	_undo_redo.create_action("编辑霰弹落点", UndoRedo.MERGE_DISABLE, pattern)
	_undo_redo.add_do_property(pattern, "points", value.duplicate())
	_undo_redo.add_undo_property(pattern, "points", pattern.points.duplicate())
	_undo_redo.add_do_method(pattern, "emit_changed")
	_undo_redo.add_undo_method(pattern, "emit_changed")
	_undo_redo.commit_action()
	status.text = "已修改；可撤销。保存后生效于引用此图样的武器。"
	_update_property()


func _select_preset(index: int) -> void:
	if index > 0: _commit_points(PRESETS[index - 1].points.duplicate())
	presets.select(0)


func _save_current() -> void:
	var pattern := get_edited_object() as ShotgunPattern
	if canvas.read_only or pattern == null or pattern.resource_path.is_empty() or pattern.is_built_in(): return
	var error := ResourceSaver.save(pattern, pattern.resource_path)
	if error == OK:
		EditorInterface.get_resource_filesystem().update_file(pattern.resource_path)
		status.text = "已保存：" + pattern.resource_path.get_file()
	else:
		status.text = "保存失败：" + error_string(error)


func _save_copy() -> void:
	var pattern := get_edited_object() as ShotgunPattern
	if pattern == null: return
	_pending_copy = pattern.duplicate(true) as ShotgunPattern
	copy_dialog.current_dir = "res://resources/weapons/patterns"
	copy_dialog.current_file = "my_pattern.tres"
	copy_dialog.popup_centered_ratio(0.65)


func _save_copy_to_path(path: String) -> void:
	if _pending_copy == null: return
	var copy := _pending_copy
	_pending_copy = null
	var error := ResourceSaver.save(copy, path, ResourceSaver.FLAG_CHANGE_PATH)
	if error != OK:
		status.text = "另存失败：" + error_string(error)
		return
	copy.take_over_path(path)
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.edit_resource.call_deferred(copy)


func _set_read_only(value: bool) -> void:
	canvas.read_only = value
	presets.disabled = value
	clear_button.disabled = value
	_update_property()
