@tool
extends EditorInspectorPlugin

var _creating_native_property := false
const ENEMY_RECOVERY_FIELDS := ["spread_recovery_degrees_per_second", "stabilize_seconds", "settle_seconds"]
const PLAYER_CONVERGENCE_FIELDS := ["convergence_model", "convergence_seconds", "convergence_exponent_k"]
const MELEE_OPENING_FIELDS := ["melee_headshot_opening_enabled", "melee_headshot_accuracy_threshold"]

const PatternProperty = preload("res://addons/weapon_mode_inspector/shotgun_pattern_property.gd")
const CoverageProperty = preload("res://addons/weapon_mode_inspector/shotgun_coverage_property.gd")
const PatternPreview = preload("res://scripts/debug/shotgun_pattern_preview.gd")

const PROBABILITY_FIELDS := {
	"initial_accuracy": "初始中心概率",
	"stabilize_seconds": "敌人概率恢复时间",
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
	"spread_recovery_degrees_per_second": "原散布接口每秒收拢角度",
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
	"convergence_seconds": "收敛时间（最大→最小）", "convergence_exponent_k": "指数强度 k",
	"headshot_accuracy_threshold": "爆头起始准度", "headshot_damage_multiplier": "未秒杀时伤害倍率", "headshot_stagger_seconds": "被爆头状态时长",
	"headshot_movement_multiplier": "被爆头时保留移速", "headshot_accuracy_cap": "被爆头期间精度上限",
	"hit_accuracy_loss": "命中精度损失", "suppression_accuracy_loss": "被压制精度损失",
	"near_miss_radius": "擦过检测范围（米）", "hit_speed_loss": "击中速度损失",
	"hit_speed_loss_seconds": "击中减速时长（秒）", "melee_accuracy_loss": "眩晕命中精度损失",
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
	"melee_slow_multiplier": "眩晕时保留移速", "melee_slow_seconds": "眩晕持续时间（秒）",
	"melee_headshot_accuracy_threshold": "眩晕破绽爆头起始准度（仅敌人受方）",
}
const PERCENT_FIELDS := [
	"headshot_accuracy_threshold", "melee_headshot_accuracy_threshold",
	"headshot_movement_multiplier", "headshot_accuracy_cap",
	"hit_accuracy_loss", "suppression_accuracy_loss", "hit_speed_loss", "melee_accuracy_loss",
	"initial_accuracy", "moving_accuracy_cap", "shot_accuracy_penalty", "minimum_accuracy",
	"target_move_accuracy_loss_per_meter_slow", "target_move_accuracy_loss_per_meter_fast",
	"target_move_minimum_accuracy", "player_move_accuracy_loss_per_meter",
	"melee_slow_multiplier",
]
const FIREARM_FIELDS := [
	"convergence_model", "convergence_seconds", "convergence_exponent_k",
	"headshot_enabled", "headshot_accuracy_threshold", "headshot_damage_multiplier",
	"headshot_instant_kill_enabled", "headshot_stagger_seconds", "headshot_stagger_refresh_mode",
	"headshot_movement_multiplier", "headshot_accuracy_cap",
	"hit_accuracy_loss", "suppression_accuracy_loss", "near_miss_radius", "hit_speed_loss", "hit_speed_loss_seconds",
	"ammo_type", "ammo_definition", "magazine_capacity", "reload_seconds", "shot_noise", "shot_noise_radius",
	"damage", "aim_range", "fire_range", "cone_angle_degrees", "locked_move_multiplier",
	"shot_interval",
]

## 自定义数值控件也提供直接提示；脚本的 ## 属性文档同时保留原生检查器帮助。
const EFFECT_HELP := {
	"stabilize_seconds": "仅敌人：从初始概率恢复到100%的秒数；初始100%时按0到100%。继续供原AI恢复与掩体阶段估时使用。玩家不读取，不受玩家公式和收敛时间影响。",
	"settle_seconds": "仅敌人：霰弹从初始稳定度恢复到最准的秒数；初始100%时按0到100%。玩家不读取；玩家霰弹统一使用所属武器的玩家收敛时间与公式。",
	"convergence_seconds": "仅玩家：从最大散布到最小散布的完整秒数，不含恢复等待；当前状态从曲线对应位置继续。线性、二次、指数均只用此时间；概率模式对应0到100%，霰弹对应最大到最小随机偏移。默认4秒，最小0.01秒；旧0值按4秒，不再启用旧参数。敌人保持原算法。",
	"convergence_exponent_k": "指数曲线的前后速度差，越大前段越快、尾段越慢；0按线性，默认3。总收敛时间由上一项控制。",
	"headshot_accuracy_threshold": "基础准度在此门槛时爆头率为0，至100%准度线性增加到必爆头；仍须实际命中，不保证秒杀。0表示从0%准度开始增长，关闭请使用启用爆头。",
	"melee_headshot_accuracy_threshold": "仅玩家近战命中敌人：玩家随后枪击此目标时的爆头起始准度，与本枪普通门槛取较低者。不增加玩家准度；首次有效枪击后消费，其他目标不受影响。",
	"headshot_damage_multiplier": "武器不启用秒杀或敌人开启爆头防护时使用。默认3倍；霰弹乘实际命中该目标的弹丸总伤害，不放大干扰、减速或击退。",
	"headshot_stagger_seconds": "存活敌人应用本武器移速与精度限制的秒数；默认1秒，0关闭。复用原受击效果，不禁止开枪或取消AI动作；转向、换弹、近战、重力和碰撞继续。",
	"headshot_movement_multiplier": "状态期间保留多少自主移速；默认0%不能走动，100%不减速。与普通受击减速取较强者，不影响重力或击退；不取消AI动作。",
	"headshot_accuracy_cap": "状态期间的最高精度；默认0%。不会抬高本来更差的精度，不禁止开枪；状态结束后沿原武器规则恢复。",
	"target_move_accuracy_loss_per_meter_slow": "慢速目标每米降低的概率。玩家按平行容差处理后的有效横向距离计算；前后移动不扣这一项。敌人仍按原目标位移。",
	"target_move_accuracy_loss_per_meter_fast": "高速目标每米降低的概率。玩家按有效横向距离和速度计算；径向速度不加重惩罚。敌人规则保留。",
	"target_move_fast_speed": "达到该速度时采用高速每米惩罚。玩家使用有效横向速度，敌人使用原目标速度（米/秒）。",
	"target_move_spread_degrees_per_meter_slow": "慢速目标每米扩大的散布半角。玩家按平行容差处理后的有效横向距离计算；前后移动不扣这一项。敌人规则保留。",
	"target_move_spread_degrees_per_meter_fast": "高速目标每米扩大的散布半角。玩家按有效横向距离和速度计算；径向速度不加重惩罚。敌人规则保留。",
	"spread_target_move_fast_speed": "达到该速度时采用高速每米扩散。玩家使用有效横向速度，敌人使用原目标速度（米/秒）。",
	"hit_accuracy_loss": "攻击武器命中后扣目标的精度，按百分点计算。20%×受方倍率0.5=扣10个百分点，80%变70%；0关闭。不影响自己的后坐力。",
	"suppression_accuracy_loss": "敌方子弹擦过时扣目标的精度，再乘受方压制精度倍率；0只关闭精度损失，仍保留真实近弹警戒。",
	"near_miss_radius": "目标胸部到实际弹道线段的最大距离（米）；0关闭擦过检测。弹道在第一碰撞截断，墙后延长线无效；与枪声范围无关。",
	"hit_speed_loss": "子弹命中损失的自主速度比例。30%×受方速度损失倍率0.5=减速15%、保留85%；0关闭。不影响击退或重力，擦过不减速。",
	"hit_speed_loss_seconds": "子弹命中减速持续秒数；0关闭。有效新命中刷新强度与时长，不叠乘；受方倍率只改强度，不缩放时间。",
	"melee_accuracy_loss": "眩晕命中时一次扣除的基础精度，乘原受方倍率。100%×0.5只扣50个百分点；不改成持续精度上限，不禁止开枪，0关闭本项损失。",
	"melee_slow_multiplier": "眩晕时基础保留移速。保留50%且受方倍率0.5时实际保留75%。100%只关闭减速，不关闭敌人的眩晕计时与爆头破绽；击退独立。",
	"melee_slow_seconds": "近战眩晕与移动减速的初始秒数，0关闭持续效果；不禁止攻击或暂停AI。重复命中仍刷新普通减速，但不延长当前敌人眩晕或补发已消费的破绽。",
	"moving_accuracy_cap": "正常移动惩罚的概率下限，不会瞬间抬高更差的精度。受击等造成更低概率时，经过恢复等待后可边走边逐渐恢复到本值；未瞄准不超过初始概率。",
	"accuracy_recovery_delay": "新的精度损失后等多久开始恢复（秒）。低于移动下限时，继续走路不会反复刷新等待；新命中、擦过或射击会重新等待。",
	"spread_recovery_degrees_per_second": "保留原散布锥恢复接口与保存值，每秒收拢多少度，0不恢复。玩家不读取；当前敌人身体使用概率恢复时间，不读取散布锥角速度。",
	"moving_spread_angle_degrees": "正常移动惩罚的最大半角，不会瞬间收拢更大散布。受击等造成额外散布时，经过恢复等待后可边走边逐渐收拢到本值；未瞄准不比初始散布更小。",
	"spread_recovery_delay": "新的精度损失后等多久开始收拢（秒）。比移动最大散布更散时，继续走路不会反复刷新等待；新命中、擦过或射击会重新等待。",
}


func _can_handle(object: Object) -> bool:
	if _creating_native_property: return false
	return object is WeaponData or object is ShotgunPattern or object is ShotgunSettings or object is PatternPreview


func _parse_property(object: Object, type: Variant.Type, path: String, hint: PropertyHint,
		hint_text: String, usage: int, wide: bool) -> bool:
	if (object is ShotgunSettings and path == "spread_mode") or (object is PatternPreview and path == "preview_spread_mode"):
		_creating_native_property = true
		var native := EditorInspector.instantiate_property_editor(object, type, path, hint, hint_text, usage, wide)
		_creating_native_property = false
		if native == null: return false
		native.tooltip_text = "随机偏移：保留原360°扰动。不向圆心偏移：允许侧向和斜外侧，只禁止朝图样原点偏移；中心弹丸仍向四周偏移，没有最低偏移距离。"
		add_property_editor(path, native, false, "预览偏移方式" if object is PatternPreview else "偏移方式")
		return true
	if object is PatternPreview:
		if path == "preview_pattern_angle_degrees":
			add_property_editor(path, CoverageProperty.new(true), false, "预览图样覆盖范围")
			return true
		return false
	if object is ShotgunSettings:
		if path == "pattern_angle_degrees":
			add_property_editor(path, CoverageProperty.new(), false, "图样覆盖范围")
			return true
		if path == "settle_seconds":
			if _is_player_context(): return true
			var editor := NumberProperty.new()
			editor.configure(hint_text, false)
			editor.tooltip_text = EFFECT_HELP[path]
			editor.spin.tooltip_text = EFFECT_HELP[path]
			add_property_editor(path, editor, false, "敌人霰弹恢复时间")
			return true
		return false
	if object is ShotgunPattern:
		if path == "points":
			add_property_editor(path, PatternProperty.new(), false, "弹丸落点画板")
			return true
		return false
	if path == "fire_mode":
		var editor := RefreshingEnumProperty.new()
		editor.configure(hint_text, int(object.fire_mode))
		add_property_editor(path, editor)
		return true
	if path == "shotgun":
		return object.fire_mode != WeaponData.FireMode.SHOTGUN
	if object.fire_mode == WeaponData.FireMode.SHOTGUN and (path == "damage" or PROBABILITY_FIELDS.has(path) or SPREAD_FIELDS.has(path)):
		return true
	if object.fire_mode == WeaponData.FireMode.MELEE and (path in FIREARM_FIELDS or PROBABILITY_FIELDS.has(path) or SPREAD_FIELDS.has(path)):
		return true
	if path in ENEMY_RECOVERY_FIELDS and _is_player_context(): return true
	if path in PLAYER_CONVERGENCE_FIELDS and _is_enemy_context(): return true
	if path in MELEE_OPENING_FIELDS and (_is_enemy_context() or object.fire_mode == WeaponData.FireMode.MELEE): return true
	if path == "melee_headshot_accuracy_threshold" and not object.melee_headshot_opening_enabled: return true
	if path == "convergence_model":
		var note := Label.new()
		note.name = "AimRecoveryHelp"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.text = "玩家三种公式统一使用收敛时间；二次／指数前快后慢。\n恢复等待与惩罚继续生效；敌人使用独立的原算法接口。"
		note.add_theme_font_size_override("font_size", 13)
		add_custom_control(note)
		var editor := RefreshingEnumProperty.new()
		editor.configure(hint_text, int(object.convergence_model))
		editor.tooltip_text = "线性匀速；二次和指数前快后慢。三者在同一完整时间到达最准；增加总时间可提高等待最准的成本。仅玩家生效。"
		add_property_editor(path, editor, false, "收敛公式")
		return true
	if path == "convergence_exponent_k" and object.convergence_model != WeaponData.ConvergenceModel.EXPONENTIAL:
		return true
	var headshot_labels := {"headshot_enabled": "启用爆头", "headshot_instant_kill_enabled": "启用爆头秒杀", "headshot_stagger_refresh_mode": "连续硬直刷新方式",
		"melee_headshot_opening_enabled": "眩晕爆头破绽（仅玩家近战命中敌人）"}
	if headshot_labels.has(path):
		_creating_native_property = true
		var native := EditorInspector.instantiate_property_editor(object, type, path, hint, hint_text, usage, wide)
		_creating_native_property = false
		if native == null: return false
		add_property_editor(path, native, false, headshot_labels[path])
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
	if EFFECT_HELP.has(path):
		editor.tooltip_text = EFFECT_HELP[path]
		editor.spin.tooltip_text = EFFECT_HELP[path]
	add_property_editor(path, editor, false, label_text)
	return true


# Nested resources follow the selected owner; standalone resources show both interfaces.
func _is_player_context() -> bool:
	return _selected_script() in ["res://scripts/player/player_weapon_slots.gd", "res://scripts/player/player_combat_v3.gd"]


func _is_enemy_context() -> bool:
	return _selected_script() == "res://scripts/enemy/enemy_actor.gd"


func _selected_script() -> String:
	var selected := EditorInterface.get_inspector().get_edited_object()
	return selected.get_script().resource_path if selected != null and selected.get_script() != null else ""


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
class RefreshingEnumProperty extends EditorProperty:
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
		# 面板重建可能把同一选值再提交一次；不让无变化操作占据原生撤销历史。
		if int(weapon.get(get_edited_property())) == shown_mode: return
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
		spin.allow_greater = parts.has("or_greater")
		spin.allow_lesser = parts.has("or_less")
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
		if not spin.editable: return
		emit_changed(get_edited_property(), value / scale_factor)
