@tool
extends EditorInspectorPlugin

const PROBABILITY_FIELDS := {
	"initial_accuracy": "初始中心概率",
	"stabilize_seconds": "恢复到满概率用时",
	"moving_accuracy_cap": "移动惩罚概率下限",
	"player_move_accuracy_loss_per_meter": "持枪者每米降低概率",
	"shot_accuracy_penalty": "每枪降低概率",
	"minimum_accuracy": "连射概率下限",
	"accuracy_recovery_delay": "恢复等待时间",
	"target_move_accuracy_loss_per_meter_slow": "慢速目标每米惩罚",
	"target_move_accuracy_loss_per_meter_fast": "高速目标每米惩罚",
	"target_move_minimum_accuracy": "跟枪概率下限",
	"target_move_fast_speed": "高速目标速度",
}
const SPREAD_FIELDS := {
	"min_spread_angle_degrees": "最小散布半角",
	"max_spread_angle_degrees": "最大散布半角",
	"initial_spread_angle_degrees": "初始散布半角",
	"spread_recovery_degrees_per_second": "每秒收拢角度",
	"moving_spread_angle_degrees": "移动最大散布",
	"player_move_spread_degrees_per_meter": "玩家每米扩大角度",
	"shot_spread_penalty_degrees": "每枪扩大角度",
	"shot_max_spread_angle_degrees": "连射最大散布",
	"spread_recovery_delay": "收拢等待时间",
	"target_move_spread_degrees_per_meter_slow": "慢速目标每米扩散",
	"target_move_spread_degrees_per_meter_fast": "高速目标每米扩散",
	"target_move_max_spread_angle_degrees": "跟枪最大散布",
	"spread_target_move_fast_speed": "高速目标速度",
}
const COMMON_FIELDS := {
	"damage": "单发伤害", "aim_range": "锁定距离", "fire_range": "弹道射程",
	"cone_angle_degrees": "索敌总角度", "locked_move_multiplier": "锁定移动倍率",
	"shot_interval": "射击间隔",
	"shot_noise_radius": "枪声半径（米）",
	"melee_damage": "近战伤害", "melee_range": "近战距离（米）",
	"melee_stamina_cost": "近战体力消耗（仅玩家）",
	"melee_angle_degrees": "近战总角度", "melee_height_tolerance": "近战高度容差",
	"melee_windup_seconds": "近战前摇（秒）", "melee_recovery_seconds": "近战收招（秒）",
	"melee_interval": "近战间隔（秒）", "melee_knockback_distance": "击退距离（米）",
	"melee_knockback_seconds": "击退时长（秒）",
}
const PERCENT_FIELDS := [
	"initial_accuracy", "moving_accuracy_cap", "shot_accuracy_penalty", "minimum_accuracy",
	"target_move_accuracy_loss_per_meter_slow", "target_move_accuracy_loss_per_meter_fast",
	"target_move_minimum_accuracy", "player_move_accuracy_loss_per_meter",
]
const FIREARM_FIELDS := [
	"ammo_type", "magazine_capacity", "reload_seconds", "shot_noise", "shot_noise_radius",
	"damage", "aim_range", "fire_range", "cone_angle_degrees", "locked_move_multiplier",
	"shot_interval",
]


func _can_handle(object: Object) -> bool:
	return object is WeaponData


func _parse_property(object: Object, type: Variant.Type, path: String, hint: PropertyHint,
		hint_text: String, _usage: int, _wide: bool) -> bool:
	if path == "fire_mode":
		var editor := FireModeProperty.new()
		editor.configure(hint_text, int(object.fire_mode))
		add_property_editor(path, editor)
		return true
	if object.fire_mode == WeaponData.FireMode.MELEE and (path in FIREARM_FIELDS or PROBABILITY_FIELDS.has(path) or SPREAD_FIELDS.has(path)):
		return true
	var mode: int = _context_mode(object)
	if (mode == 0 and SPREAD_FIELDS.has(path)) or (mode == 1 and PROBABILITY_FIELDS.has(path)):
		return true
	if type != TYPE_FLOAT or hint != PROPERTY_HINT_RANGE:
		return false
	var label_text: String = COMMON_FIELDS.get(path, PROBABILITY_FIELDS.get(path, SPREAD_FIELDS.get(path, "")))
	if label_text.is_empty():
		return false
	var editor := NumberProperty.new()
	editor.configure(hint_text, path in PERCENT_FIELDS)
	add_property_editor(path, editor, false, label_text)
	return true


func _context_mode(weapon: Object) -> int:
	var combat = EditorInterface.get_inspector().get_edited_object()
	if combat == null or combat.get_script() == null:
		return -1
	var script_path: String = combat.get_script().resource_path
	if script_path == "res://scripts/player/player_weapon_slots.gd":
		if weapon != combat.get("primary_weapon") and weapon != combat.get("secondary_weapon"):
			return -1
		var player_combat = combat.get_node_or_null("../Combat")
		return int(player_combat.get("aim_mode")) if player_combat != null else -1
	if script_path not in ["res://scripts/player/player_combat_v3.gd", "res://scripts/enemy/enemy_actor.gd"]:
		return -1
	if combat.get("weapon") != weapon:
		return -1
	return 0 if script_path == "res://scripts/enemy/enemy_actor.gd" else int(combat.get("aim_mode"))


# 保留原资源字段与原生撤销；已打开资源热更新后可能漏发 setter 通知，
# 因此选择结束及撤销／重做更新控件时，由检查器延迟请求一次面板重建。
class FireModeProperty extends EditorProperty:
	var option := OptionButton.new()
	var shown_mode: int = -1

	func _init() -> void:
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(option)
		add_focusable(option)
		option.item_selected.connect(_on_selected)

	func configure(enum_hint: String, current_mode: int) -> void:
		shown_mode = current_mode
		for entry in enum_hint.split(","):
			var parts := entry.rsplit(":", true, 1)
			option.add_item(parts[0], int(parts[1]) if parts.size() == 2 else option.item_count)

	func _update_property() -> void:
		var weapon := get_edited_object()
		var mode: int = int(weapon.get(get_edited_property()))
		option.select(option.get_item_index(mode))
		if mode != shown_mode:
			shown_mode = mode
			weapon.notify_property_list_changed.call_deferred()

	func _set_read_only(read_only: bool) -> void:
		option.disabled = read_only

	func _on_selected(index: int) -> void:
		var weapon := get_edited_object()
		shown_mode = option.get_item_id(index)
		emit_changed(get_edited_property(), shown_mode)
		weapon.notify_property_list_changed.call_deferred()


# 仍把修改交给原生资源 Inspector，因此撤销、资源脏标记和保存保持正常。
# 仅在界面把概率0～1显示为0～100%，资源和战斗代码仍保留原存储值。
class NumberProperty extends EditorProperty:
	var spin := SpinBox.new()
	var scale_factor: float = 1.0

	func _init() -> void:
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(spin)
		add_focusable(spin.get_line_edit())
		spin.value_changed.connect(_on_value_changed)

	func configure(range_hint: String, percentage: bool) -> void:
		var parts := range_hint.split(",")
		scale_factor = 100.0 if percentage else 1.0
		spin.min_value = float(parts[0]) * scale_factor
		spin.max_value = float(parts[1]) * scale_factor
		spin.step = float(parts[2]) * scale_factor
		if percentage:
			spin.suffix = "%"
		else:
			for part in parts:
				if part.begins_with("suffix:"):
					spin.suffix = part.trim_prefix("suffix:")

	func _update_property() -> void:
		spin.set_value_no_signal(float(get_edited_object().get(get_edited_property())) * scale_factor)

	func _set_read_only(read_only: bool) -> void:
		spin.editable = not read_only

	func _on_value_changed(value: float) -> void:
		emit_changed(get_edited_property(), value / scale_factor)
