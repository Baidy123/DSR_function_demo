@tool
class_name WeaponData
extends Resource

enum FireMode { SEMI_AUTO, AUTOMATIC, MELEE, SHOTGUN }
enum AmmoType { RIFLE, PISTOL, SMG, SHOTGUN }
enum StaggerRefresh { KEEP_LONGER, RESTART }

const ShotgunConfig = preload("res://scripts/weapons/shotgun_settings.gd")

@export_group("相机视野（仅玩家）")
## 开启后按 Aim Range、相机倾角及实际窗口比例计算视野；调整锁定距离即可同步调整画面范围。
@export var camera_follows_aim_range: bool = true
## 关闭范围联动时手动指定正交 Size；0沿用场景原视野。开启联动时不使用此值。
@export_range(0.0, 60.0, 0.1, "suffix:m") var camera_view_size: float = 0.0
## 切换到这把枪时的视野过渡秒数；0立即切换，出生直接使用初始武器视野。
@export_range(0.0, 3.0, 0.05, "suffix:s") var camera_transition_seconds: float = 0.25

@export_group("武器外观")
## 可选纯外观场景；留空显示方块占位，不参与弹道、命中或装备资格。
@export var visual_model: PackedScene
## 相对于角色武器挂点的模型偏移；同一资源可由多个持有者独立显示。
@export var visual_position: Vector3 = Vector3.ZERO
@export var visual_rotation_degrees: Vector3 = Vector3.ZERO
@export var visual_scale: Vector3 = Vector3.ONE

@export_group("弹匣与换弹")
## 玩家使用对应类型的共享备弹池；敌人仍使用有限弹匣、无限备弹。
@export_enum("步枪弹药:0", "手枪弹药:1", "冲锋枪弹药:2", "霰弹枪弹药:3") var ammo_type: int = AmmoType.PISTOL
## 每把枪独立保存弹匣余量；12发为可调试玩初值。
@export_range(1, 300, 1) var magazine_capacity: int = 12
## 正常换弹耗时（秒）。玩家奔跑倍率在Combat调整；敌人不受移动影响。
@export_range(0.1, 20.0, 0.1) var reload_seconds: float = 2.0

@export_group("共用参数")
## 武器显示名称。
@export var display_name: String = "测试手枪"
## 玩家或敌人实际开枪产生的逻辑声源；留空关闭。Audio Stream仅预留，不播放音频。
@export var shot_noise: NoiseData = preload("res://resources/noise/gunshot_noise.tres")
## 成功开火产生的声音半径（米），玩家和敌人都读取各自武器；0关闭枪声事件。
@export_range(0.0, 100.0, 0.5) var shot_noise_radius: float = 14.0
## 实际射线命中后的单发伤害。
@export_range(1.0, 1000.0, 1.0) var damage: float = 25.0
## 锁定距离（米）：玩家相机默认据此计算；远程敌人默认以此距离加训练中的感知余量作为视距。
@export_range(0.5, 50.0, 0.5) var aim_range: float = 8.0
## 子弹射线的最大距离（米）。
@export_range(0.5, 200.0, 0.5) var fire_range: float = 30.0
## 玩家索敌扇形总角度，不是子弹散布角，也不修改敌人的视野。
@export_range(1.0, 180.0, 1.0) var cone_angle_degrees: float = 70.0
## 玩家锁定时的走路速度倍率，锁定期间禁跑；敌人移动由 AI 决定。
@export_range(0.1, 1.0, 0.05) var locked_move_multiplier: float = 0.5
## 单发每次按下一枪，自动按住持续射击；近战仅允许近战兵装备，不使用枪械参数。
## 单发0、自动1、近战2保留原编号；霰弹3为半自动，每按一次打一组弹丸。
## 调大射击间隔可模拟泵动节奏；敌人的射击请求仍由原 AI 控制。
@export_enum("单发:0", "自动:1", "近战:2", "霰弹:3") var fire_mode: int = FireMode.SEMI_AUTO:
	set(value):
		fire_mode = value
		if value == FireMode.SHOTGUN and shotgun == null: shotgun = ShotgunConfig.new()
		notify_property_list_changed()
## Fire Mode 选霰弹后自动提供默认九点图样；展开配置每颗伤害、图样与稳定度。
## 切回原模式时保留此配置但不使用，不修改原单发／自动参数或弹药类型。
@export var shotgun: ShotgunSettings
## 两次射击的最短间隔（秒）。
@export_range(0.05, 3.0, 0.05) var shot_interval: float = 0.2

@export_group("精准爆头（仅玩家）")
## 玩家开火前达到最准精度时，实际命中才判定概率爆头；不分身体部位，不额外等待。敌人和近战不使用。
@export var headshot_enabled: bool = true
## 最准时每枪对每个实际命中目标判定一次，霰弹也只判定一次。0关闭，1表示100%。
@export_range(0.0, 1.0, 0.01) var headshot_chance: float = 0.1
## 开启且敌人没有训练“爆头防护”时，爆头走原死亡流程。关闭仍使用倍率伤害和被爆头状态。
@export var headshot_instant_kill_enabled: bool = true
## 未秒杀时的总伤害倍率，3表示普通伤害的300%；霰弹乘实际命中弹丸总伤害。旧资源显式保存的倍率保留。
@export_range(1.0, 10.0, 0.05, "suffix:×") var headshot_damage_multiplier: float = 3.0
## 存活敌人的被爆头状态秒数，默认1秒：通过原受击流程应用下方移速与精度限制；不禁射、不取消AI动作。0关闭。
@export_range(0.0, 10.0, 0.05, "or_greater", "suffix:s") var headshot_stagger_seconds: float = 1.0
## 被爆头状态内保留的自主移速比例，默认0即不能走动；1不减速。与已有受击减速取较强者，不限制重力或击退。
@export_range(0.0, 1.0, 0.01) var headshot_movement_multiplier: float = 0.0
## 被爆头状态内的精度上限，默认0%；不会抬高更差的精度，不禁止开枪，结束后按原规则恢复。
@export_range(0.0, 1.0, 0.01) var headshot_accuracy_cap: float = 0.0
## 连续爆头时保留较长剩余时间，或从本次秒数重新计时；均不累加，每目标每枪只处理一次。
@export_enum("保留较长剩余时间:0", "按本次时长重新计时:1") var headshot_stagger_refresh_mode: int = StaggerRefresh.KEEP_LONGER

@export_group("对目标命中与压制效果")
## 命中目标时扣除的基础精度；按百分点扣减。20%×受方倍率0.5=扣10个百分点，80%变70%；0关闭。
## 这是给目标的干扰，不是持枪者自己的后坐力；射击命中时冻结本次值。
@export_range(0.0, 1.0, 0.01) var hit_accuracy_loss: float = 0.15
## 子弹擦过敌方目标时扣除的基础精度；再乘受方被压制精度倍率。0只关闭精度损失，不取消真实警戒事实。
@export_range(0.0, 1.0, 0.01) var suppression_accuracy_loss: float = 0.02
## 从目标胸部到本次真实弹道线段的最大擦过距离（米）；0关闭擦过检测。墙后的延长线无效，与枪声半径无关。
@export_range(0.0, 10.0, 0.1, "suffix:m") var near_miss_radius: float = 1.5
## 子弹命中后目标损失的自主速度比例；30%×受方速度损失倍率0.5=减速15%，保留85%速度。0关闭。
## 不影响击退或重力，也不作用于擦过；附带近战的基础减速仍在近战参数中配置。
@export_range(0.0, 1.0, 0.01) var hit_speed_loss: float = 0.5
## 子弹命中减速持续时间（秒）；0关闭。有效新命中刷新强度和时长，不叠乘；受方倍率不缩放时长。
@export_range(0.0, 5.0, 0.05, "suffix:s") var hit_speed_loss_seconds: float = 0.5

@export_group("近战参数")
## 附带近战／专用近战命中时的基础精度损失；乘与射击共用的受方命中精度倍率。
## 100%且倍率1可降到0；倍率0.5只扣50个百分点，不会再额外强制清零。0关闭精度损失。
@export_range(0.0, 1.0, 0.01) var melee_accuracy_loss: float = 1.0
## 远程武器的附带近战或近战武器的攻击开关；不消耗弹药。
@export var melee_enabled: bool = true
## 近战伤害，与单发子弹伤害分别配置。
@export_range(0.0, 1000.0, 1.0) var melee_damage: float = 25.0
## 仅玩家生效：成功开始近战时扣除的体力；不足则不能发起，0关闭消耗。
## 敌人目前没有体力系统，不读取此字段；敌人武器中此值不影响近战。
@export_range(0.0, 100.0, 1.0) var melee_stamina_cost: float = 20.0
## 角色脚底间的最大水平距离（米）。
@export_range(0.1, 5.0, 0.05) var melee_range: float = 1.6
## 正前方扇形总角度；90表示左右各45度。
@export_range(1.0, 180.0, 1.0) var melee_angle_degrees: float = 90.0
## 目标脚底与自身允许的最大高度差（米）。
@export_range(0.0, 3.0, 0.05) var melee_height_tolerance: float = 1.0
## 开始动作到实际出手的时间（秒）；出手时才确定是否命中。
@export_range(0.0, 2.0, 0.01) var melee_windup_seconds: float = 0.12
## 出手后恢复射击、换弹和切枪操作的时间（秒）。
@export_range(0.0, 2.0, 0.01) var melee_recovery_seconds: float = 0.25
## 两次近战开始的最短间隔；实际至少覆盖前摇与收招。
@export_range(0.05, 5.0, 0.01) var melee_interval: float = 0.6
## 无遮挡且目标不主动移动时的击退参考距离（米）。
@export_range(0.0, 5.0, 0.05) var melee_knockback_distance: float = 1.0
## 击退外力衰减至零的时间（秒）。
@export_range(0.05, 2.0, 0.01) var melee_knockback_seconds: float = 0.2
## 近战命中后目标自主移动保留的基础比例；50%表示基础损失50%，再乘与射击共用的受方速度损失倍率。
## 例如保留50%且受方倍率0.5，实际只损失25%、保留75%；100%不减速，不缩小击退外力。
@export_range(0.0, 1.0, 0.05) var melee_slow_multiplier: float = 0.5
## 命中减速持续时间（秒）；0关闭。再次命中刷新本次效果，不叠乘速度。
@export_range(0.0, 5.0, 0.05, "suffix:s") var melee_slow_seconds: float = 0.5

@export_group("概率模式参数（百分比）")
## 初始直射中心概率：0.5表示50%；松开瞄准也将概率限制到不超过本值。
@export_range(0.0, 1.0, 0.01) var initial_accuracy: float = 0.5
## 从初始概率恢复到100%需要的秒数，不含恢复延迟；初始为100%时按从0到100%计算。
@export_range(0.1, 10.0, 0.1) var stabilize_seconds: float = 2.0
## 玩家移动惩罚最多将中心概率降到此值：0.35表示35%；不会瞬间抬高已经更低的概率。
## 若受击等造成更低概率，经过恢复延迟后可边走边逐渐恢复到此值；未瞄准仍不超过初始概率。
@export_range(0.0, 1.0, 0.01) var moving_accuracy_cap: float = 0.35
## 玩家实际水平移动每米降低多少概率；0.15表示15个百分点，0表示不增加移动惩罚。
@export_range(0.0, 1.0, 0.005) var player_move_accuracy_loss_per_meter: float = 0.15
## 每枪结束后降低多少中心概率：0.05表示5个百分点，连续射击累积。
@export_range(0.0, 1.0, 0.01) var shot_accuracy_penalty: float = 0.25
## 射击惩罚的中心概率下限：0.1表示10%；不会抬高其他因素造成的更低概率。
@export_range(0.0, 1.0, 0.01) var minimum_accuracy: float = 0.1
## 新的精度损失后等多久开始恢复中心概率（秒）；低于移动下限时，继续走路不会反复刷新等待。
@export_range(0.0, 3.0, 0.05) var accuracy_recovery_delay: float = 0.6
## 目标慢速移动时，每米扣除的中心概率：0.03表示每米3个百分点。
## 玩家按平行容差处理后的有效横向距离计算；敌人沿用原目标位移。
@export_range(0.0, 0.5, 0.005) var target_move_accuracy_loss_per_meter_slow: float = 0.03
## 目标高速移动时，每米扣除的中心概率：0.10表示每米10个百分点。
## 玩家按有效横向距离和速度计算；敌人沿用原目标位移和速度。
@export_range(0.0, 0.5, 0.005) var target_move_accuracy_loss_per_meter_fast: float = 0.10
## 跟枪惩罚的概率下限，至少比射击下限高1个百分点，最高100%。
@export_range(0.0, 1.0, 0.01) var target_move_minimum_accuracy: float = 0.30
## 目标达到此速度（米/秒）时使用高速惩罚，较慢时在两种每米惩罚间插值。
## 玩家使用有效横向速度，迎面／背离的径向速度不增加惩罚；敌人规则保留。
@export_range(0.1, 30.0, 0.1) var target_move_fast_speed: float = 6.0

@export_group("散布锥模式参数（角度）")
## 完全稳定时的最小散布半角；0度可完全收拢，大于0仍会随机射偏。
@export_range(0.0, 45.0, 0.1, "suffix:°") var min_spread_angle_degrees: float = 0.0
## 最不稳定时的最大散布半角，通常不小于最小半角；全开角是半角两倍。
@export_range(0.0, 45.0, 0.1, "suffix:°") var max_spread_angle_degrees: float = 12.0
## 装备时的散布半角；松开瞄准后，散布也不会比本值更小。
@export_range(0.0, 45.0, 0.1, "suffix:°") var initial_spread_angle_degrees: float = 6.0
## 经过恢复延迟后，每秒收拢多少度；0表示不自动收拢。
## 玩家走路时额外散布最多收拢到移动最大散布，停步且未瞄准时收拢到初始散布。
@export_range(0.0, 90.0, 0.1, "suffix:°/s") var spread_recovery_degrees_per_second: float = 3.0
## 持枪者移动惩罚最多把半角扩大到多少度；不会瞬间收拢其他原因造成的更大散布。
## 玩家受击等造成额外散布时，经过恢复延迟后可边走边逐渐收拢到此值，未瞄准不比初始散布更小。
@export_range(0.0, 45.0, 0.1, "suffix:°") var moving_spread_angle_degrees: float = 7.8
## 持枪者实际水平移动每米扩大多少度；随距离逐渐累积，0表示不增加移动散布。
@export_range(0.0, 45.0, 0.05, "suffix:°/m") var player_move_spread_degrees_per_meter: float = 3.0
## 每枪结束后扩大多少度，连续射击累积；例如1表示半角增加1度。
@export_range(0.0, 45.0, 0.05, "suffix:°") var shot_spread_penalty_degrees: float = 3.0
## 仅连射惩罚最多把半角扩大到多少度；不会收拢其他因素已经扩得更大的散布。
@export_range(0.0, 45.0, 0.1, "suffix:°") var shot_max_spread_angle_degrees: float = 10.8
## 新的精度损失后等多久开始收拢（秒）；比移动最大散布更散时，继续走路不会反复刷新等待。
@export_range(0.0, 3.0, 0.05) var spread_recovery_delay: float = 0.6
## 目标慢速移动时，每米扩大多少度。
## 玩家按平行容差处理后的有效横向距离计算；敌人沿用原目标位移。
@export_range(0.0, 45.0, 0.01, "suffix:°/m") var target_move_spread_degrees_per_meter_slow: float = 0.36
## 目标高速移动时，每米扩大多少度。
## 玩家按有效横向距离和速度计算；敌人沿用原目标位移和速度。
@export_range(0.0, 45.0, 0.01, "suffix:°/m") var target_move_spread_degrees_per_meter_fast: float = 1.2
## 仅跟枪惩罚最多把半角扩大到多少度；不会把其他原因造成的更大散布继续扩大。
@export_range(0.0, 45.0, 0.1, "suffix:°") var target_move_max_spread_angle_degrees: float = 8.4
## 目标达到此速度（米/秒）时使用高速每米扩散；较慢时在慢/高速扩散之间插值。
## 玩家使用有效横向速度，迎面／背离的径向速度不增加惩罚；敌人规则保留。
@export_range(0.1, 30.0, 0.1) var spread_target_move_fast_speed: float = 6.0


## 两套输入在这里换算，战斗脚本继续共用惩罚、等待、恢复流程。
func get_aim_settings(use_spread: bool) -> Dictionary:
	if fire_mode == FireMode.SHOTGUN:
		return get_shotgun_settings().get_aim_settings(use_spread)
	if not use_spread:
		# 初始100%也会因换弹/受伤下降，恢复速度不能因此永久变成零。
		var recovery_span := 1.0 - clampf(initial_accuracy, 0.0, 1.0)
		if is_zero_approx(recovery_span): recovery_span = 1.0
		return {
			"initial": initial_accuracy,
			"recovery": recovery_span / maxf(stabilize_seconds, 0.01),
			"moving_cap": moving_accuracy_cap,
			"player_move_loss": maxf(0.0, player_move_accuracy_loss_per_meter),
			"shot_penalty": shot_accuracy_penalty,
			"shot_floor": minimum_accuracy,
			"delay": accuracy_recovery_delay,
			"slow": target_move_accuracy_loss_per_meter_slow,
			"fast": target_move_accuracy_loss_per_meter_fast,
			"target_floor": minf(1.0, maxf(target_move_minimum_accuracy, minimum_accuracy + 0.01)),
			"fast_speed": target_move_fast_speed,
		}
	var minimum: float = clampf(min_spread_angle_degrees, 0.0, 45.0)
	var maximum: float = clampf(max_spread_angle_degrees, minimum, 45.0)
	var span: float = maximum - minimum
	# 零宽度的锥始终使用同一角度，变化量为0，避免除零。
	var degrees_to_fraction: float = 1.0 / span if span > 0.00001 else 0.0
	return {
		"initial": _angle_to_stability(initial_spread_angle_degrees, minimum, span),
		"recovery": maxf(0.0, spread_recovery_degrees_per_second) * degrees_to_fraction,
		"moving_cap": _angle_to_stability(moving_spread_angle_degrees, minimum, span),
		"player_move_loss": maxf(0.0, player_move_spread_degrees_per_meter) * degrees_to_fraction,
		"shot_penalty": maxf(0.0, shot_spread_penalty_degrees) * degrees_to_fraction,
		"shot_floor": _angle_to_stability(shot_max_spread_angle_degrees, minimum, span),
		"delay": maxf(0.0, spread_recovery_delay),
		"slow": maxf(0.0, target_move_spread_degrees_per_meter_slow) * degrees_to_fraction,
		"fast": maxf(0.0, target_move_spread_degrees_per_meter_fast) * degrees_to_fraction,
		"target_floor": _angle_to_stability(target_move_max_spread_angle_degrees, minimum, span),
		"fast_speed": spread_target_move_fast_speed,
	}


## 正常由 Fire Mode 创建配置；外部代码清空时只读使用默认值，不写回共享资源。
func get_shotgun_settings() -> ShotgunSettings:
	return shotgun if shotgun != null else ShotgunConfig.new()


## 只返回配置与精度资格；是否实际命中、掷概率及伤害由玩家原射击流程负责。
func get_headshot_chance(stability: float) -> float:
	if not headshot_enabled or fire_mode == FireMode.MELEE or not is_finite(stability) or stability < 1.0 - 0.000001:
		return 0.0
	return _valid_fraction(headshot_chance)


func get_headshot_damage_multiplier() -> float:
	return maxf(1.0, headshot_damage_multiplier) if is_finite(headshot_damage_multiplier) else 1.0


## 一枪一次的纯值快照；外部修改资源从下一枪生效，不改变本枪后续目标。
func get_headshot_settings(stability: float) -> Dictionary:
	return {"chance": get_headshot_chance(stability), "instant_kill": headshot_instant_kill_enabled,
		"multiplier": get_headshot_damage_multiplier(), "stagger_seconds": _valid_seconds(headshot_stagger_seconds),
		"movement_multiplier": clampf(headshot_movement_multiplier, 0.0, 1.0) if is_finite(headshot_movement_multiplier) else 0.0,
		"accuracy_cap": clampf(headshot_accuracy_cap, 0.0, 1.0) if is_finite(headshot_accuracy_cap) else 0.0,
		"stagger_refresh_mode": StaggerRefresh.RESTART if headshot_stagger_refresh_mode == StaggerRefresh.RESTART else StaggerRefresh.KEEP_LONGER}


func _angle_to_stability(angle: float, minimum: float, span: float) -> float:
	if span <= 0.00001:
		return 1.0
	return 1.0 - clampf((angle - minimum) / span, 0.0, 1.0)


## 攻击者在开火／近战起手时取得纯值快照；之后切枪或修改资源不改变这一击。
func get_attack_effects(melee: bool = false) -> Dictionary:
	return {
		"melee": melee,
		"hit_accuracy_loss": _valid_fraction(melee_accuracy_loss if melee else hit_accuracy_loss),
		"suppression_accuracy_loss": 0.0 if melee else _valid_fraction(suppression_accuracy_loss),
		"near_miss_radius": 0.0 if melee or not is_finite(near_miss_radius) else maxf(0.0, near_miss_radius),
		"hit_speed_loss": _valid_fraction(1.0 - melee_slow_multiplier if melee else hit_speed_loss),
		"hit_speed_loss_seconds": _valid_seconds(melee_slow_seconds if melee else hit_speed_loss_seconds),
	}

func _valid_fraction(value: float) -> float:
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0

func _valid_seconds(value: float) -> float:
	return maxf(0.0, value) if is_finite(value) else 0.0
