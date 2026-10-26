@tool
extends EditorInspectorPlugin

var _creating_native_property := false
const LEGACY_RECOVERY_FIELDS := ["spread_recovery_degrees_per_second", "stabilize_seconds", "settle_seconds"]

const PatternProperty = preload("res://addons/weapon_mode_inspector/shotgun_pattern_property.gd")
const CoverageProperty = preload("res://addons/weapon_mode_inspector/shotgun_coverage_property.gd")
const PatternPreview = preload("res://scripts/debug/shotgun_pattern_preview.gd")

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
	"convergence_seconds": "收敛时间（最大→最小）", "convergence_exponent_k": "指数强度 k",
	"headshot_chance": "爆头概率", "headshot_damage_multiplier": "未秒杀时伤害倍率", "headshot_stagger_seconds": "被爆头状态时长",
	"headshot_movement_multiplier": "被爆头时保留移速", "headshot_accuracy_cap": "被爆头期间精度上限",
	"hit_accuracy_loss": "命中精度损失", "suppression_accuracy_loss": "被压制精度损失",
	"near_miss_radius": "擦过检测范围（米）", "hit_speed_loss": "击中速度损失",
	"hit_speed_loss_seconds": "击中减速时长（秒）", "melee_accuracy_loss": "近战命中精度损失",
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
	"melee_slow_multiplier": "命中后移动速度", "melee_slow_seconds": "命中减速时长（秒）",
}
const PERCENT_FIELDS := [
	"headshot_chance",
	"headshot_movement_multiplier", "headshot_accuracy_cap",
	"hit_accuracy_loss", "suppression_accuracy_loss", "hit_speed_loss", "melee_accuracy_loss",
	"initial_accuracy", "moving_accuracy_cap", "shot_accuracy_penalty", "minimum_accuracy",
	"target_move_accuracy_loss_per_meter_slow", "target_move_accuracy_loss_per_meter_fast",
	"target_move_minimum_accuracy", "player_move_accuracy_loss_per_meter",
	"melee_slow_multiplier",
]
const FIREARM_FIELDS := [
	"convergence_model", "convergence_seconds", "convergence_exponent_k",
	"headshot_enabled", "headshot_chance", "headshot_damage_multiplier",
	"headshot_instant_kill_enabled", "headshot_stagger_seconds", "headshot_stagger_refresh_mode",
	"headshot_movement_multiplier", "headshot_accuracy_cap",
	"hit_accuracy_loss", "suppression_accuracy_loss", "near_miss_radius", "hit_speed_loss", "hit_speed_loss_seconds",
	"ammo_type", "magazine_capacity", "reload_seconds", "shot_noise", "shot_noise_radius",
	"damage", "aim_range", "fire_range", "cone_angle_degrees", "locked_move_multiplier",
	"shot_interval",
]

## 自定义数值控件也提供直接提示；脚本的 ## 属性文档同时保留原生检查器帮助。
const EFFECT_HELP := {
	"stabilize_seconds": "原概率模式从初始到满概率的秒数；初始100%时按0到100%。玩家收敛时间为0时由本项换算；设定新收敛时间后玩家改用新值，敌人仍使用本项。",
	"settle_seconds": "霰弹从初始稳定度到最准的原恢复用时。所属武器的玩家收敛时间为0时由本项换算；时间大于0时玩家不使用本项，敌人仍使用。独立打开霰弹配置时无法确定所属武器，请同时查看武器的瞄准与散布／恢复。",
	"convergence_seconds": "玩家从最大散布到最小散布的完整秒数，不含恢复等待；当前精度从曲线对应位置继续。0按原模式恢复速度换算；大于0时只使用此时间。概率模式对应0到100%，霰弹对应最大到最小随机偏移。敌人仍使用原恢复参数。",
	"convergence_exponent_k": "指数曲线的前后速度差，越大前段越快、尾段越慢；0按线性，默认3。总收敛时间由上一项控制。",
	"headshot_chance": "仅玩家开火前达到最准时，实际命中才掷概率。普通枪和霰弹都每枪每目标判定一次，不保证命中；0关闭，100%必定触发合格命中。",
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
	"melee_accuracy_loss": "近战基础精度损失，乘与射击共用的受方命中精度倍率。100%×0.5只扣50个百分点，不会再额外强制清零；0关闭。",
	"melee_slow_multiplier": "近战命中后基础保留速度。保留50%=基础损失50%；受方速度损失倍率0.5时只损失25%、实际保留75%。100%不减速。",
	"melee_slow_seconds": "近战命中减速持续秒数；0关闭。使用与射击共用的受方速度损失倍率，倍率不改变本时长；无减速命中不清除已有减速。",
	"moving_accuracy_cap": "正常移动惩罚的概率下限，不会瞬间抬高更差的精度。受击等造成更低概率时，经过恢复等待后可边走边逐渐恢复到本值；未瞄准不超过初始概率。",
	"accuracy_recovery_delay": "新的精度损失后等多久开始恢复（秒）。低于移动下限时，继续走路不会反复刷新等待；新命中、擦过或射击会重新等待。",
	"spread_recovery_degrees_per_second": "玩家收敛时间为0时：线性按本角速度恢复；二次／指数用(最大角度-最小角度)/本值换算完整时间，实际速度随曲线变化。0关闭原速度恢复。收敛时间大于0时玩家不使用本项。恢复等待、移动／跟枪上限与开火惩罚仍有效。",
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
			_add_recovery_editor(object, path, hint_text, "原恢复用时（初始→最准）")
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
	if path == "convergence_model":
		var note := Label.new()
		note.name = "AimRecoveryHelp"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.text = "时间大于0：玩家按新时间恢复，旧速度不参与；时间为0：按旧速度换算。\n二次／指数只改变过程；恢复等待、移动与开火惩罚继续生效。"
		note.add_theme_font_size_override("font_size", 13)
		add_custom_control(note)
		var editor := RefreshingEnumProperty.new()
		editor.configure(hint_text, int(object.convergence_model))
		editor.tooltip_text = "线性匀速；二次和指数前快后慢。三者在同一完整时间到达最准；增加总时间可提高等待最准的成本。仅玩家生效。"
		add_property_editor(path, editor, false, "收敛公式")
		return true
	if path == "convergence_exponent_k" and object.convergence_model != WeaponData.ConvergenceModel.EXPONENTIAL:
		return true
	var headshot_labels := {"headshot_enabled": "启用爆头", "headshot_instant_kill_enabled": "启用爆头秒杀", "headshot_stagger_refresh_mode": "连续硬直刷新方式"}
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
	if path in LEGACY_RECOVERY_FIELDS:
		_add_recovery_editor(object, path, hint_text, PROBABILITY_FIELDS.get(path, SPREAD_FIELDS.get(path, "")))
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


## 只限制确定属于玩家装备的控件；共享资源和敌人仍可编辑原恢复参数。
func _add_recovery_editor(object: Object, path: String, hint_text: String, label_text: String) -> void:
	var editor := RecoveryProperty.new()
	var weapon := _recovery_owner(object)
	var selected := EditorInterface.get_inspector().get_edited_object()
	var player_context := false
	if selected != null and selected.get_script() != null and weapon != null and _context_mode(weapon) >= 0:
		player_context = selected.get_script().resource_path in ["res://scripts/player/player_weapon_slots.gd", "res://scripts/player/player_combat_v3.gd"]
	editor.configure(hint_text, false)
	editor.configure_recovery(weapon, player_context, label_text, EFFECT_HELP[path])
	add_property_editor(path, editor, false, label_text)


## 独立 ShotgunSettings 不保存反向父引用；多个槽共享同一配置时不猜测归属。
func _recovery_owner(object: Object) -> WeaponData:
	if object is WeaponData: return object
	var selected := EditorInterface.get_inspector().get_edited_object()
	if selected == null: return null
	if selected is WeaponData: return selected if selected.shotgun == object else null
	if selected.get_script() == null: return null
	var candidates: Array = []
	match selected.get_script().resource_path:
		"res://scripts/player/player_weapon_slots.gd":
			candidates = [selected.get("primary_weapon"), selected.get("secondary_weapon")]
		"res://scripts/player/player_combat_v3.gd", "res://scripts/enemy/enemy_actor.gd":
			candidates = [selected.get("weapon")]
	var owner_weapon: WeaponData
	for candidate in candidates:
		if candidate is WeaponData and candidate.shotgun == object:
			if owner_weapon != null and owner_weapon != candidate: return null
			owner_weapon = candidate
	return owner_weapon


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


## 面板原生刷新时重新核对依赖，覆盖内嵌资源、撤销与脚本热更新；不写回任何武器参数。
class RecoveryProperty extends NumberProperty:
	var weapon: WeaponData
	var player_context := false
	var original_label := ""
	var original_help := ""
	var inspector_read_only := false

	func configure_recovery(data: WeaponData, for_player: bool, text: String, help: String) -> void:
		weapon = data
		player_context = for_player
		original_label = text
		original_help = help
		_update_availability()

	func _update_property() -> void:
		super._update_property()
		_update_availability()

	func _set_read_only(read_only: bool) -> void:
		inspector_read_only = read_only
		_update_availability()

	func _update_availability() -> void:
		var overridden := weapon != null and is_finite(weapon.convergence_seconds) and weapon.convergence_seconds > 0.0
		spin.editable = not inspector_read_only and not (player_context and overridden)
		label = original_label + ("（玩家未使用）" if overridden else "")
		tooltip_text = original_help
		if overridden:
			tooltip_text += "\n当前玩家由收敛时间决定恢复；把收敛时间设为0可恢复使用本项。敌人仍使用原参数。"
		spin.tooltip_text = tooltip_text
