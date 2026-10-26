@tool
extends EditorInspectorPlugin

var undo_redo: EditorUndoRedoManager
var _creating_native_property := false
const TacticsSettings = preload("res://scripts/enemy/config/tactics_settings.gd")
const CooperationSettings = preload("res://scripts/enemy/config/cooperation_settings.gd")
const SCORE_LABELS := {
	"score_cover_preference": ["掩体偏好", "仅普通／强配合：越大越倾向躲藏、探头和掩护撤退。默认1.35，1恢复原评分；不是概率，不改变躲藏时长。"],
	"score_action_cost_weight": ["行动代价权重", "仅普通／强配合：统一缩放动作原代价，包含路径耗时及暴露等估计。默认1；越大越重视个人行动成本，0只比较整队软代价；不改变真实移速。"],
	"score_fire_continuity_weight": ["持续火力权重", "仅普通／强配合交战：越大越重视保留攻击岗位和当前火力，越小越能接受暂时停火转移。默认1，0关闭这两项软代价；仍需实际满足开火条件。"],
	"score_crossfire_weight": ["交叉火力权重", "仅普通／强配合的全远程布局：越大越不愿重复同侧射界。默认1，0关闭软偏好；身体间距和友军枪线检查保留。"],
	"score_melee_support_weight": ["远近协同权重", "仅普通／强配合的混编布局：越大越重视远程后侧位置、远近间距和避开队友枪线。默认1，0关闭软代价；攻击范围和通行限制保留。"],
	"score_search_support_weight": ["搜索掩护权重", "仅普通／强配合搜索：越大越重视避免漏配或重复配置掩护。默认1，0关闭软代价；掩护仍必须关联真实检查者。"],
}

func _can_handle(object: Object) -> bool:
	if _creating_native_property: return false
	return object is EnemyUnitProfile or object is EnemyTrainingProfile or object.get_script() in [TacticsSettings, CooperationSettings] or object.get_script() == preload("res://scripts/enemy/enemy_training.gd")

func _parse_begin(object: Object) -> void:
	if object.get_script() in [TacticsSettings, CooperationSettings]: return
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
	elif object.get_script() == CooperationSettings and SCORE_LABELS.has(path): label_text = SCORE_LABELS[path][0]
	if label_text.is_empty(): return false
	# 只改标签，原生资源展开、拖放、布尔编辑、撤销和存储键保持。
	# 原生工厂也会询问插件，构造期间跳过自己以避免递归。
	_creating_native_property = true
	var editor := EditorInspector.instantiate_property_editor(object, type, path, hint, hint_text, usage, wide)
	_creating_native_property = false
	if editor == null: return false
	if object.get_script() == CooperationSettings:
		editor.tooltip_text = SCORE_LABELS[path][1]
		_set_score_tooltip(editor, SCORE_LABELS[path][1])
	else:
		editor.tooltip_text = "作战能力包含移动开火、反应、受击倍率及被动防护；内部tactics资源键保持兼容。" if path == "tactics" else "开启后免于爆头秒杀，仍承受攻击武器配置的倍率伤害和存活硬直；不会按外观自动判断头盔。"
	add_property_editor(path, editor, false, label_text)
	return true

func _set_score_tooltip(node: Node, description: String) -> void:
	# Inspector会重设属性行的tooltip；帮助同时挂到实际数值控件，悬停输入框即可查看。
	if node is EditorSpinSlider or node is LineEdit: node.tooltip_text = description
	for child in node.get_children(): _set_score_tooltip(child, description)
