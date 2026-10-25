@tool
extends EditorInspectorPlugin

var undo_redo: EditorUndoRedoManager
var _creating_native_property := false
const TacticsSettings = preload("res://scripts/enemy/config/tactics_settings.gd")

func _can_handle(object: Object) -> bool:
	if _creating_native_property: return false
	return object is EnemyUnitProfile or object is EnemyTrainingProfile or object.get_script() == TacticsSettings or object.get_script() == preload("res://scripts/enemy/enemy_training.gd")

func _parse_begin(object: Object) -> void:
	if object.get_script() == TacticsSettings: return
	if object is EnemyUnitProfile:
		var validation = preload("res://addons/enemy_training_inspector/unit_validation.gd").new()
		validation.unit = object
		add_custom_control(validation)
		return
	var panel = preload("res://addons/enemy_training_inspector/tactics_panel.gd").new()
	panel.configure(object, undo_redo)
	add_custom_control(panel)


func _parse_property(object: Object, type: Variant.Type, path: String, hint: PropertyHint,
		hint_text: String, usage: int, wide: bool) -> bool:
	var label_text := ""
	if object is EnemyTrainingProfile and path == "tactics": label_text = "作战能力"
	elif object.get_script() == TacticsSettings and path == "headshot_protection": label_text = "爆头防护"
	if label_text.is_empty(): return false
	# 只改标签，原生资源展开、拖放、布尔编辑、撤销和存储键保持。
	# 原生工厂也会询问插件，构造期间跳过自己以避免递归。
	_creating_native_property = true
	var editor := EditorInspector.instantiate_property_editor(object, type, path, hint, hint_text, usage, wide)
	_creating_native_property = false
	if editor == null: return false
	editor.tooltip_text = "作战能力包含移动开火、反应、受击倍率及被动防护；内部tactics资源键保持兼容。" if path == "tactics" else "开启后免于爆头秒杀，仍承受攻击武器配置的倍率伤害和存活硬直；不会按外观自动判断头盔。"
	add_property_editor(path, editor, false, label_text)
	return true
