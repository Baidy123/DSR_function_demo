@tool
extends EditorInspectorPlugin

var _creating_native_property := false
var _history: EditorUndoRedoManager
const ENEMY_RECOVERY_FIELDS := ["spread_recovery_degrees_per_second", "stabilize_seconds", "settle_seconds"]
const PLAYER_CONVERGENCE_FIELDS := ["convergence_model", "convergence_seconds", "convergence_exponent_k"]
const PLAYER_CONE_FIELDS := ["min_spread_angle_degrees", "max_spread_angle_degrees", "initial_spread_angle_degrees",
	"moving_spread_angle_degrees", "player_move_spread_degrees_per_meter", "shot_spread_penalty_degrees", "shot_max_spread_angle_degrees"]
const PLAYER_SHOTGUN_FIELDS := ["stable_jitter_degrees", "unstable_jitter_degrees", "starting_stability", "movement_loss_per_meter",
	"movement_stability_floor", "shell_stability_loss", "shell_stability_floor", "stability_recovery_delay"]
const PLAYER_HIT_FIELDS := ["hit_accuracy_loss_multiplier", "suppression_accuracy_loss_multiplier"]
const MELEE_OPENING_FIELDS := ["melee_headshot_opening_enabled", "melee_headshot_threshold_multiplier"]

const PatternProperty = preload("res://addons/weapon_mode_inspector/shotgun_pattern_property.gd")
const CoverageProperty = preload("res://addons/weapon_mode_inspector/shotgun_coverage_property.gd")
const AimModeProperty = preload("res://addons/weapon_mode_inspector/aim_mode_property.gd")
const PatternPreview = preload("res://scripts/debug/shotgun_pattern_preview.gd")

const ENEMY_PROBABILITY_FIELDS := {
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
	"tracking_parallel_tolerance_degrees": "跟枪免罚半角（仅玩家）",
	"convergence_model": "收敛公式",
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
	"melee_headshot_threshold_multiplier": "眩晕破绽门槛倍率（仅敌人受方）",
}
const PAIRED_LABELS := {
	"spread_recovery_delay": "散布锥恢复等待",
	"stable_jitter_degrees": "稳定时最大随机偏移", "unstable_jitter_degrees": "不稳定时最大随机偏移",
	"starting_stability": "初始稳定度", "movement_loss_per_meter": "每米移动损耗",
	"movement_stability_floor": "移动稳定度下限", "shell_stability_loss": "每枪稳定度损耗",
	"shell_stability_floor": "开火稳定度下限", "stability_recovery_delay": "恢复等待时间",
	"crouch_spread_reduction": "最大散布缩减", "hit_accuracy_loss_multiplier": "命中精度损失倍率",
	"suppression_accuracy_loss_multiplier": "压制精度损失倍率",
}
const PAIRED_PERCENT_FIELDS := ["starting_stability", "movement_loss_per_meter", "movement_stability_floor",
	"shell_stability_loss", "shell_stability_floor", "crouch_spread_reduction"]
const PERCENT_FIELDS := [
	"headshot_accuracy_threshold",
	"headshot_movement_multiplier", "headshot_accuracy_cap",
	"hit_accuracy_loss", "suppression_accuracy_loss", "hit_speed_loss", "melee_accuracy_loss",
	"initial_accuracy", "moving_accuracy_cap", "shot_accuracy_penalty", "minimum_accuracy",
	"target_move_accuracy_loss_per_meter_slow", "target_move_accuracy_loss_per_meter_fast",
	"target_move_minimum_accuracy", "player_move_accuracy_loss_per_meter",
	"melee_slow_multiplier",
]
const FIREARM_FIELDS := [
	"tracking_parallel_tolerance_degrees",
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
	"convergence_model": "线性匀速；二次和指数前快后慢。三者在同一完整时间到达最准。",
	"crouch_spread_reduction": "蹲姿时最大散布或最大霰弹随机偏移的缩减比例。0% 关闭。",
	"hit_accuracy_loss_multiplier": "攻击武器的命中精度损失乘此倍率。×0 免除该模式的损失。",
	"suppression_accuracy_loss_multiplier": "敌方弹道擦过时，攻击武器的压制精度损失乘此倍率。×0 免除该模式的损失。",
	"tracking_parallel_tolerance_degrees": "仅玩家使用此枪时有效。目标沿瞄准连线靠近／远离，在两侧各25°（默认）的范围内不扣目标移动精度；超出后连续增加损失。0使用纯横向投影；玩家自身移动、受击等惩罚保持。敌人使用同一枪时不读取此项。",
	"stabilize_seconds": "从初始概率恢复到100%的秒数。初始100%时按0到100%。供AI恢复与掩体阶段估时使用。",
	"settle_seconds": "仅敌人：霰弹从初始稳定度恢复到最准的秒数；初始100%时按0到100%。玩家不读取；玩家霰弹统一使用所属武器的玩家收敛时间与公式。",
	"convergence_seconds": "仅玩家使用。从最大散布到最小散布的完整秒数，不含恢复等待。线性、二次、指数均用此时间从曲线对应位置继续，霰弹对应最大到最小随机偏移。默认4秒，最小0.01秒。旧0值按4秒。",
	"convergence_exponent_k": "指数曲线的前后速度差，越大前段越快、尾段越慢；0按线性，默认3。总收敛时间由上一项控制。",
	"headshot_accuracy_threshold": "基础准度在此门槛时爆头率为0，至100%准度线性增加到必爆头；仍须实际命中，不保证秒杀。0表示从0%准度开始增长，关闭请使用启用爆头。",
	"melee_headshot_threshold_multiplier": "仅玩家近战命中敌人：随后射击武器的普通爆头起始准度×此倍率，例如80%×0.8=64%。0将门槛降至0，1不降低门槛；不增加玩家准度。倍率在近战出手时冻结，首次有效枪击后消费。",
	"headshot_damage_multiplier": "武器不启用秒杀或敌人开启爆头防护时使用。默认3倍；霰弹乘实际命中该目标的弹丸总伤害，不放大干扰、减速或击退。",
	"headshot_stagger_seconds": "存活敌人应用本武器移速与精度限制的秒数；默认1秒，0关闭。复用原受击效果，不禁止开枪或取消AI动作；转向、换弹、近战、重力和碰撞继续。",
	"headshot_movement_multiplier": "状态期间保留多少自主移速；默认0%不能走动，100%不减速。与普通受击减速取较强者，不影响重力或击退；不取消AI动作。",
	"headshot_accuracy_cap": "状态期间的最高精度；默认0%。不会抬高本来更差的精度，不禁止开枪；状态结束后沿原武器规则恢复。",
	"target_move_accuracy_loss_per_meter_slow": "慢速目标每米降低的概率，按目标位移计算。",
	"target_move_accuracy_loss_per_meter_fast": "高速目标每米降低的概率，按目标位移计算。",
	"target_move_fast_speed": "目标达到此速度时采用高速每米惩罚（米/秒）。",
	"target_move_spread_degrees_per_meter_slow": "慢速目标每米扩大的散布半角，按平行容差处理后的有效横向距离计算。",
	"target_move_spread_degrees_per_meter_fast": "高速目标每米扩大的散布半角，按有效横向距离和速度计算。",
	"spread_target_move_fast_speed": "目标有效横向速度达到此值时采用高速每米扩散（米/秒），较低速度在两种每米扩散量之间插值。",
	"hit_accuracy_loss": "攻击武器命中后扣目标的精度，按百分点计算。20%×受方倍率0.5=扣10个百分点，80%变70%；0关闭。不影响自己的后坐力。",
	"suppression_accuracy_loss": "敌方子弹擦过时扣目标的精度，再乘受方压制精度倍率；0只关闭精度损失，仍保留真实近弹警戒。",
	"near_miss_radius": "目标胸部到实际弹道线段的最大距离（米）；0关闭擦过检测。弹道在第一碰撞截断，墙后延长线无效；与枪声范围无关。",
	"hit_speed_loss": "子弹命中损失的自主速度比例。30%×受方速度损失倍率0.5=减速15%、保留85%；0关闭。不影响击退或重力，擦过不减速。",
	"hit_speed_loss_seconds": "子弹命中减速持续秒数；0关闭。有效新命中刷新强度与时长，不叠乘；受方倍率只改强度，不缩放时间。",
	"melee_accuracy_loss": "眩晕命中时一次扣除的基础精度，乘原受方倍率。100%×0.5只扣50个百分点；不改成持续精度上限，不禁止开枪，0关闭本项损失。",
	"melee_slow_multiplier": "眩晕时基础保留移速。保留50%且受方倍率0.5时实际保留75%。100%只关闭减速，不关闭敌人的眩晕计时与爆头破绽；击退独立。",
	"melee_slow_seconds": "近战眩晕与移动减速的初始秒数，0关闭持续效果；不禁止攻击或暂停AI。重复命中仍刷新普通减速，但不延长当前敌人眩晕或补发已消费的破绽。",
	"moving_accuracy_cap": "持枪者自身移动惩罚的中心概率下限。概率已低于此值时，移动惩罚停扣，持枪者移动期间暂停恢复。",
	"accuracy_recovery_delay": "中心概率开始恢复前的等待秒数。持枪者持续移动会刷新等待，换弹、开火和额外精度损失也会触发等待。",
	"spread_recovery_degrees_per_second": "保留原散布锥恢复接口与保存值，每秒收拢多少度，0不恢复。玩家不读取；当前敌人身体使用概率恢复时间，不读取散布锥角速度。",
	"moving_spread_angle_degrees": "正常移动惩罚的最大半角，不会瞬间收拢更大散布。受击等造成额外散布时，经过恢复等待后可边走边逐渐收拢到本值；未瞄准不比初始散布更小。",
	"spread_recovery_delay": "新的精度损失后等多久开始收拢（秒）。比移动最大散布更散时，继续走路不会反复刷新等待；新命中、擦过或射击会重新等待。",
}


func _can_handle(object: Object) -> bool:
	if _creating_native_property: return false
	return object is WeaponData or object is ShotgunPattern or object is ShotgunSettings or object is PatternPreview \
		or _is_player_combat(object)


func _parse_property(object: Object, type: Variant.Type, path: String, hint: PropertyHint,
		hint_text: String, usage: int, wide: bool) -> bool:
	if _is_player_combat(object):
		if path == "crouch_spread_reduction":
			_add_mode_pair(object, object, path, [path])
			return true
		if path in PLAYER_HIT_FIELDS:
			if path == PLAYER_HIT_FIELDS[0]:
				_add_mode_pair(object, object, path, PLAYER_HIT_FIELDS)
			return true
		return false
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
		if path in PLAYER_SHOTGUN_FIELDS and _shows_paired_shotgun(object):
			return true
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
		var history := _editor_history()
		editor.configure(hint_text, int(object.fire_mode), history.get_history_undo_redo(history.get_object_history_id(object)))
		add_property_editor(path, editor)
		return true
	if path == "shotgun":
		return object.fire_mode != WeaponData.FireMode.SHOTGUN
	if _parse_weapon_pairs(object, path):
		return true
	var enemy_probability_field := ENEMY_PROBABILITY_FIELDS.has(path)
	var spread_field := SPREAD_FIELDS.has(path)
	if object.fire_mode == WeaponData.FireMode.SHOTGUN and (path == "damage" or enemy_probability_field or spread_field):
		return true
	if object.fire_mode == WeaponData.FireMode.MELEE and (path in FIREARM_FIELDS or enemy_probability_field or spread_field):
		return true
	if (enemy_probability_field and _is_player_context()) or (spread_field and _is_enemy_context()): return true
	if path in ENEMY_RECOVERY_FIELDS and _is_player_context(): return true
	if path == "tracking_parallel_tolerance_degrees" and _is_enemy_context(): return true
	if path in MELEE_OPENING_FIELDS and (_is_enemy_context() or object.fire_mode == WeaponData.FireMode.MELEE): return true
	if path == "melee_headshot_threshold_multiplier" and not object.melee_headshot_opening_enabled: return true
	var headshot_labels := {"headshot_enabled": "启用爆头", "headshot_instant_kill_enabled": "启用爆头秒杀", "headshot_stagger_refresh_mode": "连续硬直刷新方式",
		"melee_headshot_opening_enabled": "眩晕爆头破绽（仅玩家近战命中敌人）"}
	if headshot_labels.has(path):
		_creating_native_property = true
		var native := EditorInspector.instantiate_property_editor(object, type, path, hint, hint_text, usage, wide)
		_creating_native_property = false
		if native == null: return false
		add_property_editor(path, native, false, headshot_labels[path])
		return true
	if type != TYPE_FLOAT or hint != PROPERTY_HINT_RANGE:
		return false
	var label_text: String = COMMON_FIELDS.get(path, ENEMY_PROBABILITY_FIELDS.get(path, SPREAD_FIELDS.get(path, "")))
	if label_text.is_empty():
		return false
	var editor := NumberProperty.new()
	editor.configure(hint_text, path in PERCENT_FIELDS)
	var help_text: String = EFFECT_HELP.get(path, "")
	if enemy_probability_field:
		help_text = "仅敌人使用。" + help_text
	editor.tooltip_text = help_text
	editor.spin.tooltip_text = help_text
	add_property_editor(path, editor, false, label_text)
	return true


func _parse_weapon_pairs(weapon: WeaponData, path: String) -> bool:
	var player_gun := not _is_enemy_context() and weapon.fire_mode != WeaponData.FireMode.MELEE
	var shotgun := weapon.fire_mode == WeaponData.FireMode.SHOTGUN
	if path == "mouse_aim_accuracy":
		if player_gun and shotgun:
			_add_mode_pair(weapon, weapon.get_shotgun_settings(), path, PLAYER_SHOTGUN_FIELDS)
		return true
	if path in PLAYER_CONVERGENCE_FIELDS:
		if player_gun and path == PLAYER_CONVERGENCE_FIELDS[0]:
			_add_mode_pair(weapon, weapon, path, PLAYER_CONVERGENCE_FIELDS)
		return true
	if not player_gun: return false
	if path == "headshot_accuracy_threshold":
		_add_mode_pair(weapon, weapon, path, [path])
		return true
	if path == "spread_recovery_delay":
		if not shotgun:
			_add_mode_pair(weapon, weapon, path, [path])
		return true
	if path in PLAYER_CONE_FIELDS:
		if not shotgun and path == PLAYER_CONE_FIELDS[0]:
			_add_mode_pair(weapon, weapon, path, PLAYER_CONE_FIELDS)
		return true
	return false


func _add_mode_pair(owner: Object, tracking: Object, anchor: String, paths: Array) -> void:
	var properties := {}
	for field in tracking.get_property_list():
		properties[field.name] = field
	var fields: Array[Dictionary] = []
	for path in paths:
		var field: Dictionary = properties[path]
		field.label = PAIRED_LABELS.get(path, COMMON_FIELDS.get(path, SPREAD_FIELDS.get(path, path)))
		field.help = EFFECT_HELP.get(path, "")
		field.percentage = path in PERCENT_FIELDS or path in PAIRED_PERCENT_FIELDS
		fields.append(field)
	var editor := AimModeProperty.new()
	editor.configure(owner, tracking, fields, _editor_history())
	add_property_editor(anchor, editor)


func _editor_history() -> EditorUndoRedoManager:
	if _history == null:
		var bridge := EditorPlugin.new()
		_history = bridge.get_undo_redo()
		bridge.free()
	return _history


func _is_player_combat(object: Object) -> bool:
	return object is Node and object.get_script() != null \
		and object.get_script().resource_path == "res://scripts/player/player_combat_v3.gd"


func _shows_paired_shotgun(settings: ShotgunSettings) -> bool:
	var selected := EditorInterface.get_inspector().get_edited_object()
	if selected is WeaponData: return selected.shotgun == settings
	if not _is_player_context(): return false
	var slots: Node = selected.get_node_or_null("../Equipment") if _is_player_combat(selected) else selected
	if slots == null: return false
	for slot in ["primary_weapon", "secondary_weapon"]:
		var weapon := slots.get(slot) as WeaponData
		if weapon != null and weapon.shotgun == settings: return true
	return false


# Nested resources follow the selected owner; standalone resources show both interfaces.
func _is_player_context() -> bool:
	return _selected_script() in ["res://scripts/player/player_weapon_slots.gd", "res://scripts/player/player_combat_v3.gd"]


func _is_enemy_context() -> bool:
	return _selected_script() == "res://scripts/enemy/enemy_actor.gd"


func _selected_script() -> String:
	var selected := EditorInterface.get_inspector().get_edited_object()
	return selected.get_script().resource_path if selected != null and selected.get_script() != null else ""


# 保留原资源字段与原生撤销；已打开资源热更新后可能漏发 setter 通知，
# 因此选择结束及撤销／重做更新控件时，由检查器延迟请求一次面板重建。
class RefreshingEnumProperty extends EditorProperty:
	var option := OptionButton.new()
	var shown_mode: int = -1
	var _object_history: UndoRedo

	func _init() -> void:
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(option)
		add_focusable(option)
		option.item_selected.connect(_on_selected)

	func configure(enum_hint: String, current_mode: int, history: UndoRedo) -> void:
		shown_mode = current_mode
		_object_history = history
		for entry in enum_hint.split(","):
			var parts := entry.rsplit(":", true, 1)
			option.add_item(parts[0], int(parts[1]) if parts.size() == 2 else option.item_count)


	func _ready() -> void:
		if _object_history != null:
			_object_history.version_changed.connect(_update_property)


	func _update_property() -> void:
		var weapon := get_edited_object()
		if weapon == null: return
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
		scale_factor = AimModeProperty.configure_spin(spin, range_hint, percentage)

	func _update_property() -> void:
		spin.set_value_no_signal(float(get_edited_object().get(get_edited_property())) * scale_factor)

	func _set_read_only(read_only: bool) -> void:
		spin.editable = not read_only

	func _on_value_changed(value: float) -> void:
		if not spin.editable: return
		emit_changed(get_edited_property(), value / scale_factor)
